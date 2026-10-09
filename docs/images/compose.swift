// Combines the screenshots into screenshots-light.png and screenshots-dark.png for the README, which
// shows the one matching the visitor's GitHub theme. Each has the menu bar icon, the menu bar panel
// and the Settings window down one column, labeled, in that appearance, with the other appearance
// peeking out behind like a stacked card. Run by update-screenshots.sh from the repo root.
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
// Margins are in points at the image's own size. The menu bar strip has room for its captions below;
// a window's shadow falls lower than it reaches above.
let shadowMargin: [String: (side: CGFloat, top: CGFloat, bottom: CGFloat)] = [
    "menubar": (240 * 24 / 300, 4, 18), "panel": (24, 20, 28), "settings": (56, 37.5, 74.5),
]
let windowWidth = load("settings-light").size.width - 2 * shadowMargin["settings"]!.side
func item(_ name: String) -> (image: NSImage, side: CGFloat, top: CGFloat, bottom: CGFloat) {
    let image = load(name), margin = shadowMargin[String(name.prefix { $0 != "-" })]!
    let zoom = windowWidth / (image.size.width - 2 * margin.side)
    return (fit(image, width: image.size.width * zoom), margin.side * zoom, margin.top * zoom, margin.bottom * zoom)
}

func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, in box: CGRect, centered: Bool) {
    let style = NSMutableParagraphStyle()
    style.alignment = centered ? .center : .left
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                     .foregroundColor: color, .paragraphStyle: style]
    let height = (text as NSString).size(withAttributes: attributes).height
    (text as NSString).draw(in: CGRect(x: box.minX, y: box.midY - height / 2, width: box.width, height: height),
                            withAttributes: attributes)
}

// Layout, in points
let margin: CGFloat = 48, rowGap: CGFloat = 48, labelWidth: CGFloat = 170, peek = CGSize(width: 56, height: 40)
let labels = ["Menu bar icon", "Menu bar panel", "Settings window"]
for front in ["light", "dark"] {
    let back = front == "light" ? "dark" : "light"
    let rows = ["menubar", "panel", "settings"].map { (name: $0, front: item("\($0)-\(front)"), back: item("\($0)-\(back)")) }
    let rowHeights = rows.map { $0.front.image.size.height - $0.front.top - $0.front.bottom + peek.height }
    let size = CGSize(width: margin * 2 + labelWidth + windowWidth + peek.width,
                      height: margin * 2 + rowHeights.reduce(0, +) + rowGap * CGFloat(rows.count - 1))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    // A card in the GitHub theme's own tone, with matching ink
    let dark = front == "dark"
    (dark ? NSColor(srgbRed: 0.086, green: 0.106, blue: 0.133, alpha: 1) : NSColor(srgbRed: 0.933, green: 0.941, blue: 0.957, alpha: 1)).setFill()
    NSBezierPath(roundedRect: CGRect(origin: .zero, size: size), xRadius: 28, yRadius: 28).fill()
    let ink = dark ? NSColor(srgbRed: 0.902, green: 0.929, blue: 0.953, alpha: 1) : NSColor(srgbRed: 0.11, green: 0.114, blue: 0.13, alpha: 1)

    let x0 = margin + labelWidth
    var top = size.height - margin
    for (index, (row, height)) in zip(rows, rowHeights).enumerated() {
        let bottom = top - height
        let frontFrame = CGRect(origin: CGPoint(x: x0 - row.front.side, y: bottom - row.front.bottom), size: row.front.image.size)
        let backFrame = CGRect(origin: CGPoint(x: x0 + peek.width - row.back.side, y: bottom + peek.height - row.back.bottom), size: row.back.image.size)
        // The menu bar strips are drawn without their baked-in captions, which are redrawn here in
        // the card's ink
        let stripZoom = row.front.side / (240 * 24 / 300)
        func strip(_ frame: CGRect) -> CGRect {
            CGRect(x: frame.minX, y: frame.maxY - (4 + 24 + 2) * stripZoom, width: frame.width, height: (4 + 24 + 2) * stripZoom)
        }
        for (image, frame) in [(row.back.image, backFrame), (row.front.image, frontFrame)] {
            NSGraphicsContext.saveGraphicsState()
            if row.name == "menubar" { NSBezierPath(rect: strip(frame)).setClip() }
            image.draw(in: frame)
            NSGraphicsContext.restoreGraphicsState()
        }
        if row.name == "menubar" {
            let captionTop = strip(frontFrame).minY - 6 * stripZoom
            for (i, caption) in ["Normal", "Low battery", "Muted"].enumerated() {
                let box = CGRect(x: x0 + windowWidth * CGFloat(i) / 3, y: captionTop - 20, width: windowWidth / 3, height: 20)
                draw(caption, size: 17, weight: .medium, color: ink, in: box, centered: true)
            }
        }
        // Each label is centered on its front item; the menu bar's on the whole group: both strips
        // and the captions
        let frontTop = bottom + height - peek.height
        let labelMidY = row.name == "menubar"
            ? (strip(backFrame).maxY - 4 * stripZoom + strip(frontFrame).minY - 6 * stripZoom - 20) / 2
            : (frontTop + bottom) / 2
        draw(labels[index], size: 20, weight: .semibold, color: ink,
             in: CGRect(x: margin, y: labelMidY - 15, width: labelWidth - 16, height: 30), centered: false)
        top -= height + rowGap
    }
    NSGraphicsContext.restoreGraphicsState()
    let out = "\(dir)/screenshots-\(front).png"
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    print("Wrote \(out), \(rep.pixelsWide) × \(rep.pixelsHigh)")
}
