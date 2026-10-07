// Combines the screenshots into screenshots.png for the README: Light and Dark across the top,
// Menu bar icon, Menu bar panel and Settings window down the side. Run by update-screenshots.sh from the
// repo root.
import AppKit

let dir = "docs/images"
let scale: CGFloat = 2  // output pixels per point

func load(_ name: String) -> NSImage {
    guard let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: "\(dir)/\(name).png"))) else {
        fatalError("can't read \(name).png")
    }
    // Size in points: the panel and the menu bar strip are rendered at 4x, the Settings captures
    // are Retina (2x)
    let pixelsPerPoint: CGFloat = name.hasPrefix("settings") ? 2 : 4
    let image = NSImage(size: CGSize(width: CGFloat(rep.pixelsWide) / pixelsPerPoint,
                                     height: CGFloat(rep.pixelsHigh) / pixelsPerPoint))
    image.addRepresentation(rep)
    return image
}

/// Scales an image to `width` points wide, keeping its proportions.
func fit(_ image: NSImage, width: CGFloat) -> NSImage {
    image.size = CGSize(width: width, height: image.size.height * width / image.size.width)
    return image
}

// The panel and the menu bar strip are narrower than the Settings window, so they're enlarged to
// the same width; that's why they're rendered at 4x, so they're only ever scaled down.
let settingsWidth = load("settings-light").size.width
let rows: [(label: String, light: NSImage, dark: NSImage)] = [
    ("Menu bar icon", fit(load("menubar-light"), width: settingsWidth), fit(load("menubar-dark"), width: settingsWidth)),
    ("Menu bar panel", fit(load("panel-light"), width: settingsWidth), fit(load("panel-dark"), width: settingsWidth)),
    ("Settings window", load("settings-light"), load("settings-dark")),
]

// Layout, in points
let margin: CGFloat = 48, labelWidth: CGFloat = 200, columnGap: CGFloat = 24, rowGap: CGFloat = 8, headerHeight: CGFloat = 72
let columnWidth = rows.flatMap { [$0.light.size.width, $0.dark.size.width] }.max()!
let rowHeights = rows.map { max($0.light.size.height, $0.dark.size.height) }
let size = CGSize(width: margin * 2 + labelWidth + columnWidth * 2 + columnGap,
                  height: margin * 2 + headerHeight + rowHeights.reduce(0, +) + rowGap * CGFloat(rows.count - 1))

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

// A soft neutral card, so the dark labels read on both GitHub themes
NSColor(srgbRed: 0.933, green: 0.941, blue: 0.957, alpha: 1).setFill()
NSBezierPath(roundedRect: CGRect(origin: .zero, size: size), xRadius: 28, yRadius: 28).fill()

func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, in box: CGRect, centered: Bool) {
    let style = NSMutableParagraphStyle()
    style.alignment = centered ? .center : .left
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                     .foregroundColor: color, .paragraphStyle: style]
    let height = (text as NSString).size(withAttributes: attributes).height
    (text as NSString).draw(in: CGRect(x: box.minX, y: box.midY - height / 2, width: box.width, height: height),
                            withAttributes: attributes)
}

let ink = NSColor(srgbRed: 0.11, green: 0.114, blue: 0.13, alpha: 1)
let columnX = [margin + labelWidth, margin + labelWidth + columnWidth + columnGap]

// Header: Light and Dark over their columns (AppKit's origin is bottom-left)
var top = size.height - margin
for (x, title) in zip(columnX, ["Light", "Dark"]) {
    draw(title, size: 40, weight: .bold, color: ink, in: CGRect(x: x, y: top - headerHeight, width: columnWidth, height: headerHeight), centered: true)
}
top -= headerHeight

for (row, height) in zip(rows, rowHeights) {
    let box = CGRect(x: margin, y: top - height, width: labelWidth, height: height)
    draw(row.label, size: 24, weight: .semibold, color: ink, in: box, centered: false)
    for (x, image) in zip(columnX, [row.light, row.dark]) {
        let origin = CGPoint(x: x + (columnWidth - image.size.width) / 2, y: top - height + (height - image.size.height) / 2)
        image.draw(in: CGRect(origin: origin, size: image.size))
    }
    top -= height + rowGap
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/screenshots.png"))
print("Wrote \(dir)/screenshots.png, \(rep.pixelsWide) × \(rep.pixelsHigh)")
