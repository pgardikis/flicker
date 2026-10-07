// Combines the screenshots into screenshots.png for the README: Light and Dark across the top, and
// the menu bar icon, the menu bar panel and the Settings window down each column. Run by
// update-screenshots.sh from the repo root.
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

// Each image has a transparent margin for its shadow. Items are sized and placed by what's inside
// it, so the panel and the menu bar strip match the Settings window's width (rendered at 4x, they're
// only ever scaled down), and the shadows spill into the gaps instead of widening the image.
// Margins in points at the image's own size: sides, top, bottom. The menu bar strip has room for
// its captions below; a window's shadow falls lower than it reaches above.
let shadowMargin: [String: (side: CGFloat, top: CGFloat, bottom: CGFloat)] = [
    "menubar": (240 * 24 / 300, 4, 18), "panel": (24, 20, 28), "settings": (56, 37.5, 74.5),
]
let windowWidth = load("settings-light").size.width - 2 * shadowMargin["settings"]!.side
func item(_ name: String) -> (image: NSImage, side: CGFloat, top: CGFloat, bottom: CGFloat) {
    let image = load(name), margin = shadowMargin[String(name.prefix { $0 != "-" })]!
    let zoom = windowWidth / (image.size.width - 2 * margin.side)
    return (fit(image, width: image.size.width * zoom), margin.side * zoom, margin.top * zoom, margin.bottom * zoom)
}
let rows = ["menubar", "panel", "settings"].map { (light: item("\($0)-light"), dark: item("\($0)-dark")) }

// Layout, in points
let margin: CGFloat = 48, columnGap: CGFloat = 48, rowGap: CGFloat = 40, headerHeight: CGFloat = 64
// A row is as tall as its content, without the margins above and below
let rowHeights = rows.map { $0.light.image.size.height - $0.light.top - $0.light.bottom }
let size = CGSize(width: margin * 2 + windowWidth * 2 + columnGap,
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
let columnX = [margin, margin + windowWidth + columnGap]

// Header: Light and Dark over their columns (AppKit's origin is bottom-left)
var top = size.height - margin
for (x, title) in zip(columnX, ["Light", "Dark"]) {
    draw(title, size: 32, weight: .bold, color: ink, in: CGRect(x: x, y: top - headerHeight, width: windowWidth, height: headerHeight), centered: true)
}
top -= headerHeight

for (row, height) in zip(rows, rowHeights) {
    for (x, item) in zip(columnX, [row.light, row.dark]) {
        item.image.draw(in: CGRect(origin: CGPoint(x: x - item.side, y: top - height - item.bottom), size: item.image.size))
    }
    top -= height + rowGap
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/screenshots.png"))
print("Wrote \(dir)/screenshots.png, \(rep.pixelsWide) × \(rep.pixelsHigh)")
