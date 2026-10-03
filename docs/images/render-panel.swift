// Renders the menu bar panel to panel-light.png and panel-dark.png at 3x, straight from the app's
// own PanelView. Built and run by update-screenshots.sh; it shows the battery as it is right now,
// with default settings.
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
    }

    @MainActor
    static func render<V: View>(_ view: V, dark: Bool, to path: String) {
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let window = ActiveWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0.01  // on screen so it lays out, but invisible
        window.contentView = hosting
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        let scale = 3
        let bounds = hosting.bounds
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width) * scale,
                                   pixelsHigh: Int(bounds.height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = bounds.size
        hosting.cacheDisplay(in: bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        window.orderOut(nil)
        print("Wrote \(path), \(rep.pixelsWide) × \(rep.pixelsHigh)")
    }
}
