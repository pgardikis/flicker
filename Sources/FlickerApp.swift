import ServiceManagement
import SwiftUI
import UserNotifications

@main
struct FlickerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = BatteryMonitor.shared

    // The menu bar icon and panel are AppKit's (StatusItem), so this is the only scene
    var body: some Scene {
        SwiftUI.Settings {
            SettingsView().environmentObject(monitor)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second copy means two menu bar icons and duplicate warnings, so the
        // newcomer steps aside and leaves the already-running one alone.
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            NSApp.terminate(nil)
            return
        }

        Settings.registerDefaults()
        DockIcon.show(Settings.showInDock)
        UNUserNotificationCenter.current().delegate = self
        Notifier.requestPermission()
        Notifier.registerActions()

        // Turn on launch at login the first time the app runs
        if !UserDefaults.standard.bool(forKey: Settings.didSetupLoginItemKey) {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: Settings.didSetupLoginItemKey)
        }

        BatteryMonitor.shared.start()
        StatusItem.shared.start()
    }

    /// Clicking the Dock icon, or a warning banner, opens the panel, as clicking the menu bar icon
    /// does. macOS sends a reopen event for both.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        StatusItem.shared.show()
        return false
    }

    // Menu bar apps count as "in the foreground", so explicitly allow banners
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    /// The banner's Options menu: the mute choices.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        completionHandler()
        Task { @MainActor in Notifier.handleAction(action) }
    }
}
