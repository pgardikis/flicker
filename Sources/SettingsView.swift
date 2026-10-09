import ServiceManagement
import SwiftUI

/// The Settings window, opened from the panel's Settings… button.
struct SettingsView: View {
    @EnvironmentObject var monitor: BatteryMonitor

    @AppStorage(Settings.thresholdKey) private var threshold = Settings.defaultThreshold
    @AppStorage(Settings.criticalKey) private var critical = Settings.defaultCritical
    @AppStorage(Settings.remindEveryKey) private var remindEvery = Settings.defaultRemindEvery
    @AppStorage(Settings.styleKey) private var style = Settings.defaultStyle
    @AppStorage(Settings.soundKey) private var sound = Settings.defaultSound
    @AppStorage(Settings.criticalSoundKey) private var criticalSound = Settings.defaultCriticalSound
    @AppStorage(Settings.volumeKey) private var volume = Settings.defaultVolume
    @AppStorage(Settings.showPercentKey) private var showPercent = Settings.defaultShowPercent
    @AppStorage(Settings.showInDockKey) private var showInDock = Settings.defaultShowInDock

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        // In a Settings scene a TabView becomes toolbar tabs, and the window takes each tab's
        // name as its title and resizes to fit it
        TabView {
            page {
                Section {
                    LevelPreview(threshold: threshold, critical: critical < threshold ? critical : 0)
                        .padding(.vertical, 4)

                    LabeledContent("Warn below") {
                        HStack {
                            // Re-check on release rather than on every step, so dragging past the current
                            // level doesn't fire a warning mid-drag
                            // No step: 91 one-percent steps draw as a smudge of tick marks, so round instead
                            Slider(value: Binding(get: { Double(threshold) }, set: { threshold = Int($0.rounded()) }),
                                   in: 5...95) {
                                if !$0 { monitor.refresh() }
                            }
                            Text("\(threshold)%").monospacedDigit().bold().foregroundStyle(.primary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }

                    Picker(selection: Binding(get: { critical }, set: { critical = $0; monitor.refresh() })) {
                        Text("Off").tag(0)
                        ForEach(Settings.criticalOptions.filter { $0 < threshold }, id: \.self) { Text("\($0)%").tag($0) }
                    } label: {
                        titled("Critical level", note: "Always an alert, even in Focus")
                    }
                    // Keep the critical level below the threshold, so the picker always has a matching option
                    .onChange(of: threshold) { _, threshold in
                        if critical >= threshold {
                            critical = Settings.criticalOptions.last { $0 < threshold } ?? 0
                        }
                    }

                    Picker("Remind again every", selection: $remindEvery) {
                        Text("Never").tag(0)
                        ForEach([1, 2, 5, 10], id: \.self) { Text("\($0)% drop").tag($0) }
                    }
                    .onChange(of: remindEvery) { monitor.refresh() }
                }
            }
            .tabItem { Label("Warnings", systemImage: "battery.25percent") }

            page {
                Section("Alert") {
                    StylePicker(style: $style)

                    LabeledContent("Test warning") {
                        Menu("Send") {
                            Button("Low Battery") { monitor.sendTest() }
                            Button("Critical") { monitor.sendTest(critical: true) }
                                .disabled(critical == 0 || critical >= threshold)
                        } primaryAction: {
                            monitor.sendTest()
                        }
                        .fixedSize()
                    }
                    .help("Sends a warning with the current style and sound")
                }

                Section("Sound") {
                    LabeledContent("Sound") {
                        HStack {
                            SoundPreviewButton { Notifier.playSound(name: sound, volume: volume) }
                                .disabled(sound.isEmpty)
                            Picker("Sound", selection: $sound) {
                                Text("None").tag("")
                                ForEach(Notifier.availableSounds, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }

                    LabeledContent {
                        HStack {
                            SoundPreviewButton { Notifier.playSound(name: resolvedCriticalSound, volume: volume) }
                                .disabled(resolvedCriticalSound.isEmpty)
                            Picker("Critical sound", selection: $criticalSound) {
                                Text("Same as Sound").tag(Settings.sameSound)
                                Text("None").tag("")
                                ForEach(Notifier.availableSounds, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    } label: {
                        titled("Critical sound", note: "Plays instead below the critical level")
                    }
                    .disabled(critical == 0 || critical >= threshold)

                    // Stored as an afplay multiplier of the speaker volume; shown as a percentage of it
                    LabeledContent("Volume") {
                        HStack {
                            Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                            Slider(value: $volume, in: 0.5...4, step: 0.5)
                            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                            Text("\(Int(volume * 100))%").monospacedDigit().bold().foregroundStyle(.primary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                    .help("Relative to your speaker volume: 100% plays at the speaker volume")
                    .disabled(sound.isEmpty && resolvedCriticalSound.isEmpty)
                }
            }
            .tabItem { Label("Alert & Sound", systemImage: "bell") }

            VStack(spacing: 0) {
                header
                page {
                    Section {
                        Toggle("Show in Dock", isOn: $showInDock)
                            .onChange(of: showInDock) { _, visible in
                                DockIcon.show(visible)
                                // Hiding the Dock icon deactivates the app, which would drop this window
                                // behind others; bring it back to the front
                                NSApp.activate()
                                NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }.forEach { $0.makeKeyAndOrderFront(nil) }
                            }
                        Toggle("Show percentage in menu bar", isOn: $showPercent)
                        // An explicit binding, so re-reading the status in onAppear can't re-trigger a write
                        Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                        if let loginError {
                            Text(loginError).font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            }
            .tabItem { Label("General", systemImage: "gearshape") }
        }
        .onAppear {
            // System Settings can change this behind our back, so re-read every time the window opens
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    /// The app's icon, name and purpose, as System Settings panes open. The version is in About.
    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Flicker").font(.title3.bold())
                Text("Low battery warnings at the level you choose").font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    /// One tab's grouped form, sized to its content.
    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Form { content() }
            .formStyle(.grouped)
            .frame(width: 480)
            .fixedSize(horizontal: false, vertical: true)
    }


    /// A row title with a grey note under it, as System Settings explains a setting in place.
    private func titled(_ title: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// What a critical warning plays, with "Same as Sound" resolved.
    private var resolvedCriticalSound: String { criticalSound == Settings.sameSound ? sound : criticalSound }

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
