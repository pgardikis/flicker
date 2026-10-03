import ServiceManagement
import SwiftUI
import UserNotifications

@main
struct BatteryNotifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = BatteryMonitor.shared
    @AppStorage(Settings.showPercentKey) private var showPercent = Settings.defaultShowPercent

    var body: some Scene {
        MenuBarExtra {
            PanelView().environmentObject(monitor)
        } label: {
            HStack {
                Image(systemName: monitor.isMuted ? "fuelpump.slash"
                    : monitor.isLow ? "fuelpump.exclamationmark.fill" : "fuelpump")
                if showPercent, let percent = monitor.percent {
                    Text("\(percent)%")
                }
            }
        }
        .menuBarExtraStyle(.window)

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

        // Turn on launch at login the first time the app runs
        if !UserDefaults.standard.bool(forKey: Settings.didSetupLoginItemKey) {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: Settings.didSetupLoginItemKey)
        }

        BatteryMonitor.shared.start()
    }

    /// Clicking the Dock icon opens the panel, as clicking the menu bar icon does.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DockIcon.openPanel()
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
}
