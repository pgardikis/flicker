// Renders AppIcon.iconset PNGs: usage `make-icon <output.iconset>`
import AppKit

let outputDir = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let size = CGFloat(pixels)
    let inset = size * 0.1
    let background = NSBezierPath(
        roundedRect: NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2),
        xRadius: size * 0.18, yRadius: size * 0.18)
    NSGradient(
        starting: NSColor(red: 1.0, green: 0.55, blue: 0.25, alpha: 1),
        ending: NSColor(red: 0.9, green: 0.2, blue: 0.3, alpha: 1))!.draw(in: background, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: size * 0.36, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "battery.25percent", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let s = symbol.size
        symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: URL(fileURLWithPath: "\(outputDir)/icon_\(base)x\(base).png"))
    try render(base * 2).write(to: URL(fileURLWithPath: "\(outputDir)/icon_\(base)x\(base)@2x.png"))
}
