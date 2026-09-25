import AppKit
import UserNotifications

/// Shows the low battery warning as a notification or alert, with sound.
@MainActor
enum Notifier {
    static let soundsDirectory = "/System/Library/Sounds"

    /// Replacing the previous warning instead of stacking a new one in Notification Center.
    private static let warningIdentifier = "low-battery"

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

    static func warn(percent: Int, threshold: Int, minutesRemaining: Int?) {
        let title = "Low Battery: \(percent)%"
        var message = "Battery is below \(threshold)%. Plug in your charger."
        if let minutes = minutesRemaining, minutes > 0 {
            message += " (\(minutes / 60):\(String(format: "%02d", minutes % 60)) remaining)"
        }

        playSound()

        if Settings.style == "alert" {
            showAlert(title: title, message: message)
        } else {
            postNotification(title: title, message: message)
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

    private static func showAlert(title: String, message: String) {
        // runModal blocks here, so a warning arriving meanwhile must not open a second dialog
        guard !alertShowing else { return }
        alertShowing = true
        defer { alertShowing = false }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private static func postNotification(title: String, message: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            DispatchQueue.main.async {
                if allowed {
                    let content = UNMutableNotificationContent()
                    content.title = title
                    content.body = message
                    // A low battery is worth breaking through Focus / Do Not Disturb, but
                    // macOS honours this only with the com.apple.developer.usernotifications
                    // .time-sensitive entitlement, which needs a provisioning profile from a
                    // paid Developer ID. Ad-hoc signing can't have it: embedding it anyway
                    // makes AMFI refuse to launch the app. So this is a no-op on an ad-hoc
                    // build, kept for when the app is signed properly. Use Style = Alert to
                    // get a warning that Focus cannot suppress.
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
