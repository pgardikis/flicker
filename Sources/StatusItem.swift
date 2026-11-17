import AppKit
import Combine
import SwiftUI

/// The menu bar icon and its panel. Built on AppKit's NSStatusItem rather than SwiftUI's
/// MenuBarExtra, because MenuBarExtra has no API to open its panel, and on macOS 27 even
/// clicking its button from code does nothing, so a Dock or banner click couldn't open it.
@MainActor
final class StatusItem: NSObject, NSWindowDelegate {
    static let shared = StatusItem()

    private var item: NSStatusItem?
    private var panel: Panel?
    /// When the panel last closed because a click went elsewhere. A click on the icon closes it
    /// that way first, and the icon's own action mustn't then reopen it.
    private var closedByClickAt = Date.distantPast
    private var observers: Set<AnyCancellable> = []

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        // On press, as menu bar menus open
        item.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        self.item = item
        updateIcon()

        // objectWillChange fires before the change lands, so redraw on the next turn. The main
        // queue is serviced in common modes, so this keeps up while an alert is open.
        BatteryMonitor.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { _ in MainActor.assumeIsolated { StatusItem.shared.updateIcon() } }
            .store(in: &observers)
        // Show percentage in menu bar
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { _ in MainActor.assumeIsolated { StatusItem.shared.updateIcon() } }
            .store(in: &observers)
    }

    private func updateIcon() {
        guard let button = item?.button else { return }
        let monitor = BatteryMonitor.shared
        let percent = UserDefaults.standard.bool(forKey: Settings.showPercentKey) ? monitor.percent : nil
        let symbol = MenuBarLabel.symbolName(isLow: monitor.isLow, isMuted: monitor.isMuted)
        if button.image?.name() != symbol {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            image?.setName(symbol)
            image?.isTemplate = true
            button.image = image
        }
        button.title = percent.map { " \($0)%" } ?? ""
        button.imagePosition = percent == nil ? .imageOnly : .imageLeading
        button.setAccessibilityLabel(MenuBarLabel.accessibilityText(isLow: monitor.isLow, isMuted: monitor.isMuted,
                                                                    percent: percent))
    }

    @objc private func toggle() {
        if panel != nil {
            close()
        } else if Date().timeIntervalSince(closedByClickAt) > 0.3 {
            show()
        }
    }

    /// Opens the panel under the menu bar icon, or brings it forward if it's already open. Also
    /// used for a click on the Dock icon or a warning banner, which reach the app as a reopen.
    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        guard let button = item?.button, let anchor = button.window else { return }

        // A new view each time, so PanelView's onAppear re-reads the battery as the panel opens
        let content = NSHostingController(rootView: PanelView()
            .environmentObject(BatteryMonitor.shared)
            .background(PanelBackground())
            .clipShape(RoundedRectangle(cornerRadius: Panel.cornerRadius, style: .continuous)))
        // The panel follows the view's size, as the health line or the mute line come and go
        content.sizingOptions = [.preferredContentSize]

        let panel = Panel(contentViewController: content)
        panel.delegate = self
        panel.setContentSize(content.view.fittingSize)
        self.panel = panel
        place(panel, under: anchor)
        button.highlight(true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        panel.orderOut(nil)
        item?.button?.highlight(false)
    }

    /// Below the icon, left edges lined up like a menu's, and kept on the icon's screen.
    private func place(_ panel: NSPanel, under anchor: NSWindow) {
        let screen = (anchor.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let size = panel.frame.size
        let x = min(max(anchor.frame.minX, screen.minX + 8), screen.maxX - size.width - 8)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: anchor.frame.minY - 4))
    }

    // MARK: NSWindowDelegate

    /// A click anywhere else closes the panel, as with a menu. That includes the panel's own
    /// Settings… and About, which open windows that take over as key.
    func windowDidResignKey(_ notification: Notification) {
        closedByClickAt = Date()
        close()
    }

    /// The panel's Settings… and About buttons close it directly.
    func windowWillClose(_ notification: Notification) {
        close()
    }

    /// The window grows downward from where it was placed: AppKit keeps the bottom edge, so put
    /// the top edge back under the menu bar.
    func windowDidResize(_ notification: Notification) {
        guard let panel, let anchor = item?.button?.window else { return }
        place(panel, under: anchor)
    }
}

/// A borderless panel that can take key status, so its controls get clicks and Esc closes it,
/// without activating the app and pulling its other windows forward.
private final class Panel: NSPanel {
    static let cornerRadius: CGFloat = 12

    init(contentViewController: NSViewController) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.contentViewController = contentViewController
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        // A borderless window is left out of the accessibility tree unless it says it's a window
        setAccessibilityElement(true)
        setAccessibilityRole(.window)
        setAccessibilityLabel("Flicker")
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        StatusItem.shared.close()
    }
}

/// The translucent menu material behind the panel's content.
private struct PanelBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
