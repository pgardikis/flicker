import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var monitor: BatteryMonitor

    @AppStorage(Settings.thresholdKey) private var threshold = Settings.defaultThreshold
    @AppStorage(Settings.remindEveryKey) private var remindEvery = Settings.defaultRemindEvery
    @AppStorage(Settings.styleKey) private var style = Settings.defaultStyle
    @AppStorage(Settings.soundKey) private var sound = Settings.defaultSound
    @AppStorage(Settings.volumeKey) private var volume = Settings.defaultVolume

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if monitor.percent != nil, let healthText = monitor.healthText {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(healthText).foregroundStyle(monitor.healthIsNormal ? .green : .red)
                        if let capacityLine { capacityLine }
                    }
                } icon: {
                    Image(systemName: monitor.healthIsNormal ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(monitor.healthIsNormal ? .green : .red)
                }
                .font(.caption)
            }
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Warn below")
                    Spacer()
                    Text("\(threshold)%").monospacedDigit().bold()
                }
                Slider(value: Binding(get: { Double(threshold) }, set: { threshold = Int($0) }), in: 5...95, step: 1)
            }

            Picker("Remind again every", selection: $remindEvery) {
                Text("Never").tag(0)
                ForEach([1, 2, 5, 10], id: \.self) { Text("\($0)% drop").tag($0) }
            }

            Picker("Style", selection: $style) {
                Text("Notification").tag("notification")
                Text("Alert").tag("alert")
            }
            .pickerStyle(.segmented)

            HStack {
                Picker("Sound", selection: $sound) {
                    Text("None").tag("")
                    ForEach(Notifier.availableSounds, id: \.self) { Text($0).tag($0) }
                }
                Button {
                    Notifier.playSound(name: sound, volume: volume)
                } label: {
                    Image(systemName: "play.fill")
                }
                .help("Preview sound")
                .disabled(sound.isEmpty)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Volume")
                    Spacer()
                    Text(String(format: "%.1f×", volume)).monospacedDigit().bold()
                }
                Slider(value: $volume, in: 0.5...4, step: 0.5)
            }
            .disabled(sound.isEmpty)

            // An explicit binding, so re-reading the status in onAppear can't re-trigger a write
            Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }

            Divider()

            HStack {
                Button("Send Test Warning") { monitor.sendTest() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            monitor.refresh()
            monitor.refreshDetails()
            // System Settings can change this behind our back, so re-read on every open
            launchAtLogin = SMAppService.mainApp.status == .enabled
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
            }
        }
    }

    /// Maximum capacity colored by wear, followed by the cycle count. nil when neither is known.
    private var capacityLine: Text? {
        var parts: [Text] = []
        if let capacity = monitor.maximumCapacityPercent {
            parts.append(Text("Maximum capacity \(capacity)%").foregroundStyle(capacityColor(capacity)))
        }
        if let cycles = monitor.details?.cycleCount {
            parts.append(Text("\(cycles.formatted()) cycles").foregroundStyle(.secondary))
        }
        guard let first = parts.first else { return nil }
        return parts.dropFirst().reduce(first) { $0 + Text(" · ").foregroundStyle(.secondary) + $1 }
    }

    /// Apple designs batteries to keep about 80% capacity at their rated cycle count.
    /// Orange rather than yellow, which is hard to read on the light-mode panel.
    private func capacityColor(_ capacity: Int) -> Color {
        switch capacity {
        case 80...: return .green
        case 60..<80: return .orange
        default: return .red
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        // Show what macOS actually did, not what was asked for
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
