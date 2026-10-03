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

/// The optional Dock icon. Info.plist's LSUIElement keeps the app out of the Dock by default;
/// switching the activation policy shows or hides the icon without a relaunch.
@MainActor
enum DockIcon {
    static func show(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }

    /// Opens the menu bar panel by clicking the app's own menu bar icon, since SwiftUI's
    /// MenuBarExtra has no API to open it. Finding that icon relies on AppKit's private
    /// NSStatusBarWindow class name, so if it isn't found (a future macOS, or the icon hidden),
    /// this opens Settings instead, through the app menu's Settings… item.
    static func openPanel() {
        let statusWindows = NSApp.windows.filter { $0.className.contains("NSStatusBarWindow") }
        if let button = statusWindows.lazy.compactMap({ $0.contentView.flatMap(firstButton) }).first {
            button.performClick(nil)
            return
        }
        openSettings()
    }

    private static func firstButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton { return button }
        return view.subviews.lazy.compactMap(firstButton).first
    }

    /// The app menu's Settings… item (⌘,), which SwiftUI adds for the Settings scene.
    private static func openSettings() {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu,
              let index = appMenu.items.firstIndex(where: { $0.keyEquivalent == "," })
        else { return }
        appMenu.performActionForItem(at: index)
    }
}
