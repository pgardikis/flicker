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

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
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
        .onAppear { monitor.refresh() }
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
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
