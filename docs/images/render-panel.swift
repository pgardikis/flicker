// Renders the menu bar panel to panel-light.png and panel-dark.png, straight from the app's own
// PanelView, and the menu bar icon's states to menubar-light.png and menubar-dark.png from
// MenuBarLabel, both at 4x. Built and run by update-screenshots.sh; the panel shows the battery as it is right
// now, with default settings.
import AppKit
import SwiftUI

/// Started from a terminal, the renderer can't become the active app, so the window claims to be
/// key and main itself.
final class ActiveWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

@main
enum RenderPanel {
    static func main() {
        MainActor.assumeIsolated { run(outputDirectory: CommandLine.arguments[1]) }
    }

    @MainActor
    static func run(outputDirectory: String) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        Settings.registerDefaults()
        BatteryMonitor.shared.start()
        RunLoop.main.run(until: Date().addingTimeInterval(2))  // let system_profiler answer

        for dark in [false, true] {
            // The real panel's rounded corners, hairline border and shadow
            let panel = PanelView()
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                .padding(24)
                .environmentObject(BatteryMonitor.shared)
            render(panel, dark: dark, to: "\(outputDirectory)/panel-\(dark ? "dark" : "light").png")
        }
        // Small, so compose.swift enlarges it to the Settings window's width
        for dark in [false, true] {
            render(MenuBarStates(dark: dark), dark: dark,
                   to: "\(outputDirectory)/menubar-\(dark ? "dark" : "light").png")
        }
    }

    @MainActor
    static func render<V: View>(_ view: V, dark: Bool, scale: Int = 4, to path: String) {
        // A window draws at its screen's pixel density, so it goes on the sharpest screen, and the
        // view is enlarged inside it to make up the rest of `scale`
        let screen = NSScreen.screens.max { $0.backingScaleFactor < $1.backingScaleFactor }!
        let zoom = CGFloat(scale) / screen.backingScaleFactor
        let pointSize = NSHostingView(rootView: view).fittingSize
        let hosting = NSHostingView(rootView: view
            .scaleEffect(zoom, anchor: .topLeading)
            .frame(width: pointSize.width * zoom, height: pointSize.height * zoom, alignment: .topLeading))
        let size = hosting.fittingSize
        let window = ActiveWindow(contentRect: CGRect(origin: screen.frame.origin, size: size), styleMask: [.borderless],
                                  backing: .buffered, defer: false, screen: screen)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0.01  // on screen so it lays out, but invisible
        window.contentView = hosting
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        let bounds = hosting.bounds
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds) else { fatalError("can't render \(path)") }
        hosting.cacheDisplay(in: bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        window.orderOut(nil)
        print("Wrote \(path), \(rep.pixelsWide) × \(rep.pixelsHigh)")
    }
}

/// A menu bar showing the icon in each state, captioned underneath. The captions use the same ink
/// as screenshots.png's labels, since the composite's card is light in both columns.
struct MenuBarStates: View {
    let dark: Bool
    private let states: [(caption: String, isLow: Bool, isMuted: Bool)] = [
        ("Normal", false, false), ("Low battery", true, false), ("Muted", false, true),
    ]
    private let ink = Color(red: 0.11, green: 0.114, blue: 0.13)

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(states, id: \.caption) { state in
                    MenuBarLabel(isLow: state.isLow, isMuted: state.isMuted, percent: nil)
                        .font(Font(NSFont.menuBarFont(ofSize: 0)))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 24)
            .background(dark ? Color(white: 0.13) : Color(white: 0.97))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            HStack(spacing: 0) {
                ForEach(states, id: \.caption) { state in
                    Text(state.caption).font(.system(size: 10, weight: .medium)).foregroundStyle(ink)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(width: 240)
        .padding(.top, 4)
        // Extra room below, so the gap to the panel matches the one between the panel and Settings
        .padding(.bottom, 18)
        // The panel image has 24 pt of shadow margin around a 300 pt panel; the same proportion here
        // lines the strip up with the panel once compose.swift enlarges both to one width
        .padding(.horizontal, 240 * 24 / 300)
    }
}
