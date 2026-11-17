import AppKit

/// The optional Dock icon. Info.plist's LSUIElement keeps the app out of the Dock by default;
/// switching the activation policy shows or hides the icon without a relaunch.
@MainActor
enum DockIcon {
    static func show(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }
}
