import Foundation
import IOKit.ps

/// Reads the battery state, listens for power changes, and decides when to warn.
@MainActor
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    @Published private(set) var percent: Int?
    @Published private(set) var onBattery = false
    @Published private(set) var minutesRemaining: Int?
    @Published private(set) var details: BatteryDetails?
    /// When muted warnings resume; `.distantFuture` means when the charger is connected.
    @Published private(set) var mutedUntil: Date?

    /// Percentage at the last warning; nil once charging or back above the threshold.
    private var lastWarned: Int?
    private var timer: Timer?
    private var muteTimer: Timer?

    var isMuted: Bool { mutedUntil != nil }

    var mutedText: String? {
        guard let mutedUntil else { return nil }
        if mutedUntil == .distantFuture { return "Warnings muted until plugged in" }
        return "Warnings muted until \(mutedUntil.formatted(date: .omitted, time: .shortened))"
    }

    var isLow: Bool {
        guard let percent else { return false }
        return onBattery && percent < Settings.threshold
    }

    var symbolName: String {
        guard let percent else { return "battery.0percent" }
        if !onBattery { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var statusText: String {
        guard percent != nil else { return "No battery found" }
        guard onBattery else { return "Power adapter connected" }
        guard let minutes = minutesRemaining, minutes > 0 else { return "On battery" }
        return "On battery · \(minutes / 60):\(String(format: "%02d", minutes % 60)) remaining"
    }

    /// nil until system_profiler has answered, or when it reports no health for this battery.
    var healthText: String? {
        guard let health = details?.health else { return nil }
        // system_profiler's JSON says "Good" where System Settings shows "Normal"
        return "Battery health: \(health == "Good" ? "Normal" : health)"
    }

    var healthIsNormal: Bool { details?.health == "Good" }

    /// system_profiler reports maximum capacity as text such as "80%".
    var maximumCapacityPercent: Int? {
        details?.maximumCapacity.flatMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) }
    }

    func start() {
        refresh()
        refreshDetails()

        // Instant updates when the power source or level changes
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)?.takeRetainedValue() {
            // Common modes, so updates keep arriving while a modal alert or menu is up
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        // Fallback poll, also picks up settings changes
        let timer = Timer(timeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { BatteryMonitor.shared.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        readBattery()
        evaluate()
    }

    /// Health, maximum capacity and cycle count barely move, so they're read on launch and when
    /// the panel opens rather than on every refresh. They come from system_profiler so they match
    /// System Settings: IOKit only has raw mAh figures, and its health rating can disagree.
    func refreshDetails() {
        Task.detached {
            let details = Self.readDetails()
            await MainActor.run { self.details = details }
        }
    }

    /// Mutes warnings below the critical level, for `duration` or, when nil, until the charger is
    /// connected. Plugging in ends any mute.
    func mute(for duration: TimeInterval?) {
        muteTimer?.invalidate()
        muteTimer = nil
        guard let duration else {
            mutedUntil = .distantFuture
            return
        }
        mutedUntil = Date().addingTimeInterval(duration)
        // Fire on time rather than waiting for the next poll, so a warning due meanwhile isn't late
        let timer = Timer(timeInterval: duration, repeats: false) { _ in
            MainActor.assumeIsolated { BatteryMonitor.shared.unmute() }
        }
        RunLoop.main.add(timer, forMode: .common)
        muteTimer = timer
    }

    /// Re-evaluates straight away, so a warning held back by the mute arrives now.
    func unmute() {
        muteTimer?.invalidate()
        muteTimer = nil
        mutedUntil = nil
        refresh()
    }

    func sendTest(critical: Bool = false) {
        readBattery()
        Notifier.warn(percent: percent ?? 0, threshold: Settings.threshold,
                      critical: critical ? Settings.critical : nil, minutesRemaining: minutesRemaining)
    }

    private func readBattery() {
        let wasOnBattery = onBattery
        defer {
            if wasOnBattery && !onBattery && isMuted {
                muteTimer?.invalidate()
                muteTimer = nil
                mutedUntil = nil
            }
        }

        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  desc[kIOPSIsPresentKey] as? Bool != false,
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }

            percent = current * 100 / max
            onBattery = desc[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            minutesRemaining = desc[kIOPSTimeToEmptyKey] as? Int
            return
        }

        // No usable battery: clear everything, so nothing stale is left behind
        percent = nil
        onBattery = false
        minutesRemaining = nil
    }

    private nonisolated static func readDetails() -> BatteryDetails? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["SPPowerDataType"] as? [[String: Any]],
              let health = items.lazy.compactMap({ $0["sppower_battery_health_info"] as? [String: Any] }).first
        else { return nil }
        return BatteryDetails(
            health: health["sppower_battery_health"] as? String,
            maximumCapacity: health["sppower_battery_health_maximum_capacity"] as? String,
            cycleCount: health["sppower_battery_cycle_count"] as? Int)
    }

    private func evaluate() {
        guard let percent else { return }
        let threshold = Settings.threshold
        let critical = Settings.critical

        // Reset when charging or back above threshold, so the next drop warns again
        if !onBattery || percent >= threshold {
            lastWarned = nil
            return
        }

        let isCritical = critical > 0 && percent < critical
        if let lastWarned {
            // Dropping into the critical level always warns, even with reminders off
            let enteredCritical = isCritical && lastWarned >= critical
            let remindEvery = Settings.remindEvery
            if !enteredCritical && (remindEvery <= 0 || percent > lastWarned - remindEvery) { return }
        }

        // The critical level gets through a mute: that's where a missed warning costs unsaved
        // work. Returning before lastWarned is set means the held-back warning fires on unmute.
        if isMuted && !isCritical { return }

        lastWarned = percent
        Notifier.warn(percent: percent, threshold: threshold, critical: isCritical ? critical : nil,
                      minutesRemaining: minutesRemaining)
    }
}

/// Battery health as System Settings shows it, read from system_profiler.
struct BatteryDetails: Sendable {
    let health: String?
    let maximumCapacity: String?
    let cycleCount: Int?
}
