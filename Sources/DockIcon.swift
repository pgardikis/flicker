import AppKit

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
