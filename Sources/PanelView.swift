import SwiftUI

/// The menu bar panel: battery status at a glance. The settings live in their own window.
struct PanelView: View {
    @EnvironmentObject var monitor: BatteryMonitor
    @Environment(\.openSettings) private var openSettings

    @AppStorage(Settings.thresholdKey) private var threshold = Settings.defaultThreshold
    @AppStorage(Settings.criticalKey) private var critical = Settings.defaultCritical
    @AppStorage(Settings.remindEveryKey) private var remindEvery = Settings.defaultRemindEvery
    @AppStorage(Settings.soundKey) private var sound = Settings.defaultSound
    @AppStorage(Settings.criticalSoundKey) private var criticalSound = Settings.defaultCriticalSound

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let mutedText = monitor.mutedText {
                HStack {
                    Label(mutedText, systemImage: "bell.slash.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Unmute") { monitor.unmute() }
                        .controlSize(.small)
                }
            }
            if monitor.percent != nil, let healthLine {
                // The icon stands for the rating, so with no rating there's no icon, rather than a
                // red warning for a battery nothing is known to be wrong with
                if monitor.healthRating != nil {
                    Label {
                        healthLine.fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: monitor.healthIsNormal ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(monitor.healthIsNormal ? Self.statusGreen : .red)
                    }
                    .font(.caption)
                } else {
                    healthLine.fixedSize(horizontal: false, vertical: true).font(.caption)
                }
            }
            Divider()

            VStack(alignment: .leading, spacing: 2) {
                warningSummary
                criticalSummary
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            HStack {
                Button("Settings…") { showSettings() }
                Spacer()
                Button("About") { showAbout() }
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            monitor.refresh()
            monitor.refreshDetails()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: monitor.symbolName)
                .font(.system(size: 28))
                .foregroundStyle(monitor.isLow ? .red : .primary)
            VStack(alignment: .leading) {
                Text(monitor.percent.map { "\($0)%" } ?? "—").font(.title2.bold())
                Text(monitor.statusText).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            // Icon only, so the status text beside it isn't truncated. A bell while warnings are on;
            // while muted, the bell is slashed and tinted orange, so the two never look alike
            Menu {
                if monitor.isMuted {
                    Button("Unmute") { monitor.unmute() }
                    Divider()
                }
                Button("For 30 Minutes") { monitor.mute(for: 30 * 60) }
                Button("For 1 Hour") { monitor.mute(for: 60 * 60) }
                Button("Until Plugged In") { monitor.mute(for: nil) }
                    .disabled(!monitor.onBattery)
            } label: {
                Label { Text(monitor.isMuted ? "Muted" : "Mute") } icon: { muteIcon }
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(monitor.isMuted ? "Warnings are muted" : "Mute warnings")
        }
    }

    /// A menu's label is drawn as a template image, which drops SwiftUI colors, so the muted bell
    /// is an NSImage that carries its own orange.
    private var muteIcon: Image {
        guard monitor.isMuted,
              let image = NSImage(systemSymbolName: "bell.slash.fill", accessibilityDescription: "Muted")?
                .withSymbolConfiguration(.init(paletteColors: [.systemOrange]))
        else { return Image(systemName: "bell.fill") }
        image.isTemplate = false
        return Image(nsImage: image)
    }

    /// Health rating, maximum capacity and cycle count on one line. Only the rating is colored,
    /// as in System Settings: macOS decides when a battery needs service, so the capacity carries
    /// no color of its own that could contradict it.
    private var healthLine: Text? {
        var parts: [Text] = []
        if let rating = monitor.healthRating {
            parts.append(Text(rating).foregroundStyle(monitor.healthIsNormal ? Self.statusGreen : .red))
        }
        if let capacity = monitor.maximumCapacityPercent {
            parts.append(Text("Maximum capacity ").foregroundStyle(.secondary)
                + Text("\(capacity)%").bold().foregroundStyle(.primary))
        }
        if let cycles = monitor.details?.cycleCount {
            parts.append(Text("\(cycles.formatted()) cycles").foregroundStyle(.secondary))
        }
        guard let first = parts.first else { return nil }
        return parts.dropFirst().reduce(first) { $0 + Text(" · ").foregroundStyle(.secondary) + $1 }
    }

    /// System green is too pale for small text on the light panel (about 1.9:1 contrast), so
    /// light mode uses a darker green that reaches about 4.9:1. Dark mode keeps system green.
    private static let statusGreen = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .systemGreen
            : NSColor(srgbRed: 0x1A / 255, green: 0x75 / 255, blue: 0x31 / 255, alpha: 1)
    })

    private var warningSummary: Text {
        let below = Text("\(threshold)%").bold().foregroundStyle(.primary)
        guard remindEvery > 0 else { return Text("Warns once below ") + below }
        return Text("Warns below ") + below + Text(", again every ")
            + Text("\(remindEvery)%").bold().foregroundStyle(.primary) + Text(" drop")
    }

    private var criticalSummary: Text {
        let level = effectiveCritical > 0
            ? Text("Critical alert below ") + Text("\(effectiveCritical)%").bold().foregroundStyle(.primary)
            : Text("No critical level")
        let sounds = soundName(sound)
            + (effectiveCritical > 0 && criticalSound != Settings.sameSound && criticalSound != sound
                ? ", critical \(soundName(criticalSound))" : "")
        return level + Text(" · \(sounds)")
    }

    private func soundName(_ name: String) -> String {
        name.isEmpty ? "No sound" : name
    }

    /// Matches Settings.critical: a level at or above the threshold can't apply.
    private var effectiveCritical: Int { critical < threshold ? critical : 0 }

    /// The standard About window: icon, name, version and copyright from Info.plist.
    private func showAbout() {
        let panel = NSApp.keyWindow
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
        panel?.close()
    }

    private func showSettings() {
        // The panel is the key window while its button is being clicked. Closing it leaves the
        // Settings window on its own, rather than looking like a second pane of the panel
        let panel = NSApp.keyWindow
        // The screen whose menu bar was clicked, read before the panel closes
        let screen = panel?.screen ?? NSScreen.main
        // A menu bar app isn't frontmost, so without activating, the window opens behind others.
        // The click on Settings… is what lets macOS agree to it.
        NSApp.activate()
        openSettings()
        panel?.close()
        DispatchQueue.main.async {
            // The Settings window is the app's only window that can become main
            for window in NSApp.windows where window.isVisible && window.canBecomeMain {
                // Apple's convention is to reopen a window where it was left, so keep the saved
                // spot when it's on this screen. Otherwise (first open, another display, or one
                // that's gone) center it here rather than on a screen the user isn't looking at.
                if let visible = screen?.visibleFrame, !visible.contains(window.frame) {
                    window.setFrameOrigin(NSPoint(x: visible.midX - window.frame.width / 2,
                                                  y: visible.midY - window.frame.height / 2))
                }
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
