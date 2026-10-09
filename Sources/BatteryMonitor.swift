import AppKit
import IOKit
import IOKit.ps

/// Reads the battery state, listens for power changes, and decides when to warn.
@MainActor
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    @Published private(set) var percent: Int?
    @Published private(set) var onBattery = false
    @Published private(set) var minutesRemaining: Int?
    @Published private(set) var isCharging = false
    @Published private(set) var isCharged = false
    @Published private(set) var minutesToFull: Int?
    @Published private(set) var details: BatteryDetails?
    /// When muted warnings resume; `.distantFuture` means when the charger is connected.
    @Published private(set) var mutedUntil: Date?

    /// Percentage at the last warning; nil once charging or back above the threshold.
    private var lastWarned: Int?
    private var timer: Timer?
    private var muteTimer: Timer?

    /// When the adapter was first seen connected without charging. macOS reports that for a
    /// moment on every plug and unplug, so "Not charging" waits until it has lasted a while.
    private var notChargingSince: Date?
    private var settleTimer: Timer?
    private static let notChargingDelay: TimeInterval = 3
    /// Re-reads while a time estimate is still missing, so the battery controller's figure
    /// shows soon after it appears instead of at the next 60 s poll.
    private var estimateTimer: Timer?
    private var readingDetails = false

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
        guard let percent else { return "No battery found" }
        if onBattery {
            // macOS has no estimate (-1) for a minute or two after unplugging
            guard let minutes = minutesRemaining, minutes > 0 else { return "On battery · Calculating…" }
            return "On battery · \(Self.duration(minutes)) remaining"
        }
        if isCharging {
            guard let minutes = minutesToFull, minutes > 0 else { return "Charging" }
            return "Charging · \(Self.duration(minutes)) until full"
        }
        if isCharged || percent >= 100 { return "Fully charged" }
        // On the adapter but not charging below 100% means macOS is holding the charge, for
        // example Optimized Battery Charging pausing at 80%. Until that has lasted a few
        // seconds it's more likely the brief gap while plugging in or unplugging.
        if let notChargingSince, Date().timeIntervalSince(notChargingSince) >= Self.notChargingDelay {
            return "Not charging"
        }
        return "Power adapter connected"
    }

    /// Minutes as h:mm, the way macOS shows battery time.
    static func duration(_ minutes: Int) -> String {
        "\(minutes / 60):\(String(format: "%02d", minutes % 60))"
    }

    /// nil until system_profiler has answered, or when it reports no health for this battery.
    var healthRating: String? {
        guard let health = details?.health else { return nil }
        // system_profiler's JSON says "Good" where System Settings shows "Normal"
        return health == "Good" ? "Normal" : health
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

        // Timers don't count time asleep, so re-check straight away on wake
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { _ in
            MainActor.assumeIsolated { BatteryMonitor.shared.refresh() }
        }
    }

    func refresh() {
        readBattery()
        // The date decides when a mute ends: its timer runs late if the Mac slept meanwhile
        if let mutedUntil, mutedUntil <= Date() {
            muteTimer?.invalidate()
            muteTimer = nil
            self.mutedUntil = nil
        }
        evaluate()
    }

    /// Health, maximum capacity and cycle count barely move, so they're read on launch and when
    /// the panel opens rather than on every refresh. They come from system_profiler so they match
    /// System Settings: IOKit only has raw mAh figures, and its health rating can disagree.
    func refreshDetails() {
        // Opening the panel again before system_profiler answers shouldn't start a second run
        guard !readingDetails else { return }
        readingDetails = true
        Task.detached {
            let details = Self.readDetails()
            await MainActor.run {
                self.readingDetails = false
                // Keep the last good reading if this run failed, rather than blanking the health line
                if let details { self.details = details }
            }
        }
    }

    /// Mutes warnings below the critical level, for `duration` or, when nil, until the charger is
    /// connected. Plugging in ends any mute.
    func mute(for duration: TimeInterval?) {
        // On the adapter there's no unplug to wait for; the mute would last into the next one.
        // Checked first, so a timed mute already running keeps its timer.
        if duration == nil && !onBattery { return }
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
            if wasOnBattery && !onBattery {
                Notifier.clearWarning()
                if isMuted {
                    muteTimer?.invalidate()
                    muteTimer = nil
                    mutedUntil = nil
                }
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
            // macOS's own estimate takes about two minutes after unplugging or plugging in. The
            // battery controller has one after about one, and they agree, so it fills the gap.
            minutesRemaining = Self.minutes(desc[kIOPSTimeToEmptyKey])
                ?? (onBattery ? Self.controllerMinutesRemaining() : nil)
            isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            isCharged = desc[kIOPSIsChargedKey] as? Bool ?? false
            minutesToFull = Self.minutes(desc[kIOPSTimeToFullChargeKey])
                ?? (isCharging ? Self.controllerMinutesRemaining() : nil)
            trackNotCharging(!onBattery && !isCharging && !isCharged)
            waitForEstimate((onBattery && minutesRemaining == nil) || (isCharging && minutesToFull == nil))
            return
        }

        // No usable battery: clear everything, so nothing stale is left behind
        percent = nil
        onBattery = false
        minutesRemaining = nil
        isCharging = false
        isCharged = false
        minutesToFull = nil
        trackNotCharging(false)
        waitForEstimate(false)
    }

    /// IOKit reports -1 for "no estimate yet" and 0 when the figure doesn't apply.
    private static func minutes(_ value: Any?) -> Int? {
        guard let minutes = value as? Int, minutes > 0 else { return nil }
        return minutes
    }

    /// The battery controller's estimate: minutes to empty on battery, to full while charging.
    /// 65535 means it has none yet.
    private static func controllerMinutesRemaining() -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let property = IORegistryEntryCreateCFProperty(service, "TimeRemaining" as CFString, kCFAllocatorDefault, 0),
              let minutes = property.takeRetainedValue() as? Int,
              minutes > 0, minutes < 65535
        else { return nil }
        return minutes
    }

    private func waitForEstimate(_ missing: Bool) {
        guard missing else {
            estimateTimer?.invalidate()
            estimateTimer = nil
            return
        }
        guard estimateTimer == nil else { return }
        let timer = Timer(timeInterval: 10, repeats: false) { _ in
            MainActor.assumeIsolated {
                BatteryMonitor.shared.estimateTimer = nil
                BatteryMonitor.shared.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        estimateTimer = timer
    }

    private func trackNotCharging(_ notCharging: Bool) {
        guard notCharging else {
            notChargingSince = nil
            settleTimer?.invalidate()
            settleTimer = nil
            return
        }
        guard notChargingSince == nil else { return }
        notChargingSince = Date()
        // Re-read once the delay has passed, so the status switches to "Not charging" on time
        // instead of at the next poll
        let timer = Timer(timeInterval: Self.notChargingDelay, repeats: false) { _ in
            MainActor.assumeIsolated { BatteryMonitor.shared.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        settleTimer = timer
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
        let decision = WarningRules.decide(percent: percent, onBattery: onBattery, threshold: threshold,
                                           critical: critical, remindEvery: Settings.remindEvery,
                                           lastWarned: lastWarned, muted: isMuted)
        lastWarned = decision.lastWarned
        guard decision.warn else { return }
        Notifier.warn(percent: percent, threshold: threshold, critical: decision.critical ? critical : nil,
                      minutesRemaining: minutesRemaining)
    }
}

/// Battery health as System Settings shows it, read from system_profiler.
struct BatteryDetails: Sendable {
    let health: String?
    let maximumCapacity: String?
    let cycleCount: Int?
}
