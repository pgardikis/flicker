import SwiftUI

/// The menu bar panel: battery status at a glance. The settings live in their own window.
struct PanelView: View {
    @EnvironmentObject var monitor: BatteryMonitor
    @Environment(\.openSettings) private var openSettings

    @AppStorage(Settings.thresholdKey) private var threshold = Settings.defaultThreshold
    @AppStorage(Settings.criticalKey) private var critical = Settings.defaultCritical
    @AppStorage(Settings.remindEveryKey) private var remindEvery = Settings.defaultRemindEvery
    @AppStorage(Settings.soundKey) private var sound = Settings.defaultSound

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
                Label {
                    healthLine.fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: monitor.healthIsNormal ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(monitor.healthIsNormal ? Self.statusGreen : .red)
                }
                .font(.caption)
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
                Menu("Test") {
                    Button("Low Battery") { monitor.sendTest() }
                    Button("Critical") { monitor.sendTest(critical: true) }
                        .disabled(effectiveCritical == 0)
                } primaryAction: {
                    monitor.sendTest()
                }
                .fixedSize()
                .help("Send a test warning")
                Spacer()
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
            // Icon only, so the status text beside it isn't truncated
            Menu {
                Button("For 30 Minutes") { monitor.mute(for: 30 * 60) }
                Button("For 1 Hour") { monitor.mute(for: 60 * 60) }
                Button("Until Plugged In") { monitor.mute(for: nil) }
                    .disabled(!monitor.onBattery)
            } label: {
                Label("Mute", systemImage: monitor.isMuted ? "bell.slash.fill" : "bell.slash")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Mute warnings")
        }
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
        return level + Text(" · \(sound.isEmpty ? "No sound" : sound)")
    }

    /// Matches Settings.critical: a level at or above the threshold can't apply.
    private var effectiveCritical: Int { critical < threshold ? critical : 0 }

    private func showSettings() {
        // The panel is the key window while its button is being clicked. Closing it leaves the
        // Settings window on its own, rather than looking like a second pane of the panel
        let panel = NSApp.keyWindow
        // A menu bar app isn't frontmost, so without activating, the window opens behind others
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        panel?.close()
        DispatchQueue.main.async {
            NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }.forEach { $0.makeKeyAndOrderFront(nil) }
        }
    }
}
