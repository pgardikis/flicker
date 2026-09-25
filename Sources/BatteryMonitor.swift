import Foundation
import IOKit.ps

/// Reads the battery state, listens for power changes, and decides when to warn.
@MainActor
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    @Published private(set) var percent: Int?
    @Published private(set) var onBattery = false
    @Published private(set) var minutesRemaining: Int?

    /// Percentage at the last warning; nil once charging or back above the threshold.
    private var lastWarned: Int?
    private var timer: Timer?

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

    func start() {
        refresh()

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

    func sendTest() {
        readBattery()
        Notifier.warn(percent: percent ?? 0, threshold: Settings.threshold, minutesRemaining: minutesRemaining)
    }

    private func readBattery() {
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

    private func evaluate() {
        guard let percent else { return }
        let threshold = Settings.threshold

        // Reset when charging or back above threshold, so the next drop warns again
        if !onBattery || percent >= threshold {
            lastWarned = nil
            return
        }

        if let lastWarned {
            let remindEvery = Settings.remindEvery
            if remindEvery <= 0 || percent > lastWarned - remindEvery { return }
        }

        lastWarned = percent
        Notifier.warn(percent: percent, threshold: threshold, minutesRemaining: minutesRemaining)
    }
}
