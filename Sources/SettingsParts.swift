import SwiftUI

/// The warning and critical levels drawn on a battery, updating as the settings change. It only
/// shows the settings; the slider and picker below it change them.
struct LevelPreview: View {
    let threshold: Int
    /// 0 when off.
    let critical: Int

    var body: some View {
        Canvas { context, size in
            let body = CGRect(x: 0.75, y: 0.75, width: size.width - 7.5, height: 26)
            context.stroke(Path(roundedRect: body, cornerRadius: 7), with: .color(.secondary), lineWidth: 1.5)
            context.fill(Path(roundedRect: CGRect(x: body.maxX + 2, y: 8.75, width: 4, height: 10), cornerRadius: 2),
                         with: .color(.secondary))

            let inside = body.insetBy(dx: 3.25, dy: 3.25)
            func x(_ percent: Int) -> CGFloat { inside.minX + inside.width * CGFloat(percent) / 100 }
            context.drawLayer { zones in
                zones.clip(to: Path(roundedRect: inside, cornerRadius: 4))
                zones.fill(Path(CGRect(x: x(critical), y: inside.minY, width: x(threshold) - x(critical), height: inside.height)),
                           with: .color(.orange.opacity(0.55)))
                if critical > 0 {
                    zones.fill(Path(CGRect(x: inside.minX, y: inside.minY, width: x(critical) - inside.minX, height: inside.height)),
                               with: .color(.red.opacity(0.85)))
                }
            }

            // Ticks, then labels centered under them, pushed apart when they'd overlap
            var marks = [(x: x(threshold), tick: Self.warnTick, label: context.resolve(
                Text("Warn \(threshold)%").font(.caption.weight(.semibold)).foregroundStyle(Self.warnText)))]
            if critical > 0 {
                marks.insert((x(critical), Self.criticalTick, context.resolve(
                    Text("Critical \(critical)%").font(.caption.weight(.semibold)).foregroundStyle(Self.criticalText))), at: 0)
            }
            for mark in marks {
                context.fill(Path(roundedRect: CGRect(x: mark.x - 1, y: 0, width: 2, height: 28), cornerRadius: 1),
                             with: .color(mark.tick))
            }
            let widths = marks.map { $0.label.measure(in: size).width }
            var centers = marks.map(\.x)
            if centers.count == 2 {
                let overlap = (widths[0] + widths[1]) / 2 + 8 - (centers[1] - centers[0])
                if overlap > 0 { centers[0] -= overlap / 2; centers[1] += overlap / 2 }
            }
            for i in centers.indices {
                centers[i] = min(max(centers[i], widths[i] / 2), size.width - widths[i] / 2)
            }
            if centers.count == 2, centers[1] - centers[0] < (widths[0] + widths[1]) / 2 + 8 {
                centers[1] = centers[0] + (widths[0] + widths[1]) / 2 + 8
            }
            for (mark, center) in zip(marks, centers) {
                context.draw(mark.label, at: CGPoint(x: center, y: 38))
            }
        }
        .frame(height: 46)
        .accessibilityElement()
        .accessibilityLabel(critical > 0 ? "Critical below \(critical)%, warning below \(threshold)%"
                                         : "Warning below \(threshold)%")
    }

    // System red and orange are too pale for small text and thin lines on a light background
    private static let criticalText = dynamic(light: NSColor(srgbRed: 0.84, green: 0, blue: 0.08, alpha: 1), dark: .systemRed)
    private static let warnText = dynamic(light: NSColor(srgbRed: 0.64, green: 0.32, blue: 0, alpha: 1), dark: .systemOrange)
    private static let criticalTick = Color(nsColor: .systemRed)
    private static let warnTick = dynamic(light: NSColor(srgbRed: 0.76, green: 0.42, blue: 0, alpha: 1), dark: .systemOrange)

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
}

/// Style as two pictures, as System Settings shows notification styles. Assistive technologies get
/// an ordinary picker in its place.
struct StylePicker: View {
    @Binding var style: String

    var body: some View {
        HStack(spacing: 12) {
            card(tag: Settings.bannerStyle, title: "Banner")
            card(tag: Settings.alertStyle, title: "Alert")
        }
        .padding(.vertical, 4)
        .accessibilityRepresentation {
            Picker("Style", selection: $style) {
                Text("Banner").tag(Settings.bannerStyle)
                Text("Alert").tag(Settings.alertStyle)
            }
        }
    }

    private func card(tag: String, title: String) -> some View {
        let selected = style == tag
        return Button {
            style = tag
        } label: {
            VStack(spacing: 8) {
                StyleThumbnail(banner: tag == Settings.bannerStyle)
                    .frame(height: 96)
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .inset(by: -4)
                                .strokeBorder(Color.accentColor, lineWidth: 3)
                        }
                    }
                Text(title).fontWeight(selected ? .semibold : .regular)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A tiny desktop with a banner in the corner or an alert in the middle.
private struct StyleThumbnail: View {
    let banner: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let window = dark ? Color(white: 0.23) : Color(white: 0.97)
        let line = dark ? Color(white: 0.4) : Color(white: 0.78)
        ZStack(alignment: .top) {
            (dark ? Color(red: 0.18, green: 0.23, blue: 0.28) : Color(red: 0.78, green: 0.82, blue: 0.87))
            Rectangle().fill(dark ? Color.black.opacity(0.35) : Color.white.opacity(0.6)).frame(height: 9)
            if banner {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).fill(.orange).frame(width: 14, height: 14)
                    VStack(alignment: .leading, spacing: 3) {
                        Capsule().fill(line).frame(width: 40, height: 4)
                        Capsule().fill(line).frame(width: 64, height: 4)
                    }
                }
                .padding(.horizontal, 6)
                .frame(width: 100, height: 28, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7).fill(window).shadow(color: .black.opacity(0.25), radius: 3, y: 1))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 16)
                .padding(.trailing, 10)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    RoundedRectangle(cornerRadius: 4).fill(.orange).frame(width: 14, height: 14)
                        .padding(.bottom, 3)
                    Capsule().fill(line).frame(width: 44, height: 4)
                    Capsule().fill(line).frame(width: 56, height: 4)
                    Spacer(minLength: 0)
                    Capsule().fill(Color.accentColor).frame(height: 9)
                }
                .padding(7)
                .frame(width: 76, height: 62)
                .background(RoundedRectangle(cornerRadius: 9).fill(window).shadow(color: .black.opacity(0.25), radius: 3, y: 1))
                .padding(.top, 22)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A round speaker button that plays a sound once, shown before its picker.
struct SoundPreviewButton: View {
    /// What VoiceOver and the tooltip call it, so the two buttons can be told apart.
    var label = "Preview sound"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 11))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.quaternary))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
