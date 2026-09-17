import ServiceManagement
import SwiftUI
import UserNotifications

@main
struct BatteryNotifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = BatteryMonitor.shared

    var body: some Scene {
        MenuBarExtra {
            SettingsView().environmentObject(monitor)
        } label: {
            Image(systemName: monitor.isLow ? "fuelpump.exclamationmark.fill" : "fuelpump")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        UNUserNotificationCenter.current().delegate = self
        Notifier.requestPermission()

        // Turn on launch at login the first time the app runs
        if !UserDefaults.standard.bool(forKey: Settings.didSetupLoginItemKey) {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: Settings.didSetupLoginItemKey)
        }

        BatteryMonitor.shared.start()
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
