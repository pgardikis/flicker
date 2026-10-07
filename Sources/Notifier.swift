import AppKit
import UserNotifications

/// Shows the low battery warning as a notification or alert, with sound.
@MainActor
enum Notifier {
    static let soundsDirectory = "/System/Library/Sounds"

    /// Replacing the previous warning instead of stacking a new one in Notification Center.
    private static let warningIdentifier = "low-battery"
    private static let muteHourAction = "mute-1-hour"
    private static let mutePluggedInAction = "mute-until-plugged-in"

    /// True while a modal alert is on screen, so a second warning can't stack another dialog.
    private static var alertShowing = false

    /// The system sounds directory doesn't change while the app runs, so list it once.
    static let availableSounds: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: soundsDirectory)) ?? []
        return files.filter { $0.hasSuffix(".aiff") }.map { String($0.dropLast(5)) }.sorted()
    }()

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// `critical` is the critical level when the battery is below it, nil otherwise.
    static func warn(percent: Int, threshold: Int, critical: Int? = nil, minutesRemaining: Int?) {
        let time = minutesRemaining.flatMap { $0 > 0 ? spokenDuration($0) : nil }
        let title: String
        let message: String
        if critical != nil {
            title = "Critical Battery: \(percent)%"
            message = (time.map { "About \($0) left. " } ?? "") + "Plug in now."
        } else {
            title = "Time to Charge"
            message = time.map { "\(percent)% · about \($0) left" } ?? "\(percent)% left"
        }

        playSound(name: critical != nil ? Settings.criticalSound : Settings.sound)

        // Focus can hide a notification but not an alert, so a critical warning is always an alert
        if let critical {
            showAlert(title: title, message: message, percent: percent, level: critical, critical: true)
        } else if Settings.style == "alert" {
            showAlert(title: title, message: message, percent: percent, level: threshold, critical: false)
        } else {
            postNotification(title: title, message: message)
        }
    }

    /// "1 hr 5 min" rather than the panel's "1:05", which on its own could pass for a clock time.
    private static func spokenDuration(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    /// Plugging in answers the warning, so the banner leaves Notification Center and an open
    /// alert closes.
    static func clearWarning() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [warningIdentifier])
        // The power source callback and timers run in common modes, so this lands inside runModal
        if alertShowing { NSApp.abortModal() }
    }

    /// The Options menu on the banner, which offers the panel's mute choices.
    static func registerActions() {
        let category = UNNotificationCategory(
            identifier: warningIdentifier,
            actions: [
                UNNotificationAction(identifier: muteHourAction, title: "Mute for 1 Hour"),
                UNNotificationAction(identifier: mutePluggedInAction, title: "Mute Until Plugged In"),
            ],
            intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func handleAction(_ identifier: String) {
        switch identifier {
        case muteHourAction: BatteryMonitor.shared.mute(for: 60 * 60)
        case mutePluggedInAction: BatteryMonitor.shared.mute(for: nil)
        default: break
        }
    }

    /// Plays via afplay so volume follows the speaker volume and can be boosted above 1.
    static func playSound(name: String = Settings.sound, volume: Double = Settings.volume) {
        // Only allow known system sounds, so the setting can't point afplay at arbitrary files
        guard !name.isEmpty, availableSounds.contains(name) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        process.arguments = ["-v", String(volume), "\(soundsDirectory)/\(name).aiff"]
        try? process.run()
    }

    /// `level` is the warning or critical level, marked on the alert's level bar.
    private static func showAlert(title: String, message: String, percent: Int, level: Int, critical: Bool) {
        // runModal blocks here, so a warning arriving meanwhile must not open a second dialog
        guard !alertShowing else { return }
        alertShowing = true
        defer { alertShowing = false }

        // Asks to come forward; macOS may decline while the user works in another app, which is
        // fine: a modal alert floats above other apps' windows either way, without taking focus
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = critical ? .critical : .warning
        alert.messageText = title
        alert.informativeText = message
        alert.accessoryView = LevelBar(percent: percent, level: level, critical: critical)
        alert.addButton(withTitle: "OK")
        // A mute doesn't hold back critical warnings, so the button would do nothing there
        if !critical {
            alert.addButton(withTitle: "Mute 1 Hour")
        }
        let response = alert.runModal()
        alert.window.orderOut(nil)
        if response == .alertSecondButtonReturn {
            BatteryMonitor.shared.mute(for: 60 * 60)
        }
    }

    private static func postNotification(title: String, message: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            DispatchQueue.main.async {
                if allowed {
                    let content = UNMutableNotificationContent()
                    content.title = title
                    content.body = message
                    content.categoryIdentifier = warningIdentifier
                    // A low battery is worth breaking through Focus / Do Not Disturb, but
                    // macOS honours this only with the com.apple.developer.usernotifications
                    // .time-sensitive entitlement, which needs a provisioning profile from a
                    // paid Developer ID. Ad-hoc signing can't have it: embedding it anyway
                    // makes AMFI refuse to launch the app. So this is a no-op on an ad-hoc
                    // build, kept for when the app is signed properly. Style = Alert gives a
                    // warning that Focus cannot suppress.
                    content.interruptionLevel = .timeSensitive
                    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: warningIdentifier, content: content, trigger: nil))
                } else {
                    // Permission denied or not yet granted: fall back to AppleScript notifications
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                    // Pass text as arguments, never interpolated into the script, to prevent AppleScript injection
                    process.arguments = [
                        "-e", "on run argv",
                        "-e", "display notification (item 1 of argv) with title (item 2 of argv)",
                        "-e", "end run",
                        message, title,
                    ]
                    try? process.run()
                }
            }
        }
    }
}

/// The battery level drawn as a battery, with a labelled tick at the warning or critical level.
private final class LevelBar: NSView {
    private let percent: Int
    private let level: Int
    private let critical: Bool
    private var label: String { critical ? "Critical level" : "Warning level" }

    init(percent: Int, level: Int, critical: Bool) {
        self.percent = percent
        self.level = level
        self.critical = critical
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 34))
        setAccessibilityElement(true)
        setAccessibilityRole(.levelIndicator)
        setAccessibilityLabel("Battery \(percent)%, \(label.lowercased()) \(level)%")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Body and nub, like the battery symbol
        let body = NSRect(x: 0.75, y: 2.75, width: bounds.width - 6.5, height: 14.5)
        let outline = NSBezierPath(roundedRect: body, xRadius: 4, yRadius: 4)
        outline.lineWidth = 1.5
        NSColor.secondaryLabelColor.setStroke()
        outline.stroke()
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: body.maxX + 1.5, y: 7, width: 3, height: 6), xRadius: 1.5, yRadius: 1.5).fill()

        let inside = body.insetBy(dx: 2.25, dy: 2.25)
        var fill = inside
        fill.size.width = max(3, inside.width * CGFloat(min(max(percent, 0), 100)) / 100)
        (critical ? NSColor.systemRed : NSColor.systemOrange).setFill()
        NSBezierPath(roundedRect: fill, xRadius: 2, yRadius: 2).fill()

        let x = (inside.minX + inside.width * CGFloat(level) / 100).rounded() - 1
        NSColor.labelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: 2, height: 20), xRadius: 1, yRadius: 1).fill()

        // Centered under the tick, kept inside the view
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize - 1),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let text = "\(label) \(level)%" as NSString
        let size = text.size(withAttributes: attributes)
        let textX = min(max(0, x + 1 - size.width / 2), bounds.width - size.width)
        text.draw(at: NSPoint(x: textX, y: 21), withAttributes: attributes)
    }
}
