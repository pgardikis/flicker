# How Flicker works

The technical side of the app: how it reads the battery, how it decides when to warn, how `build.sh` assembles the app without Xcode, where it keeps its files, and its security model. For installing and using the app, see the [README](../README.md).

## Project structure

```
flicker/
├── Sources/
│   ├── FlickerApp.swift           App entry, launch at login, notification setup
│   ├── MenuBarLabel.swift         The menu bar icon and its states
│   ├── DockIcon.swift             The optional Dock icon and opening the panel from it
│   ├── BatteryMonitor.swift       Reads the battery and acts on the warning rules
│   ├── WarningRules.swift         The warning rules, as a pure function
│   ├── Notifier.swift             Shows notifications and alerts, plays sounds
│   ├── PanelView.swift            The menu bar panel: status, health and a settings summary
│   ├── SettingsParts.swift        Settings' battery preview, style pictures and sound buttons
│   ├── SettingsView.swift         The Settings window and its tabs
│   └── Settings.swift             Setting keys and defaults
├── Tests/
│   └── WarningRulesTests.swift    Scenarios that check the warning rules
├── docs/                          This file, the screenshots and the scripts that make them
├── build/                         Created by build.sh, not stored in git
├── Info.plist                     App metadata and version (menu bar only by default)
├── make-icon.swift                Draws the app icon
├── build.sh                       Build, sign and install script
├── test.sh                        Builds and runs the tests
├── README.md                      Install and usage
├── AGENTS.md                      Instructions for AI coding agents
├── LICENSE                        MIT
└── .gitignore
```

## Deciding when to warn

`BatteryMonitor` re-evaluates every time it reads the battery: when macOS reports a power change, when a warning setting changes, and every 60 seconds as a backup.

- **It warns only on battery and below *Warn below*.** Otherwise it forgets the last warning, so the next drop below the threshold warns again. That happens when you plug in, or when you lower *Warn below* under the current level while on battery.
- **It remembers one number between warnings**: the percentage at the last warning. A reminder is due once the battery has dropped another *Remind again every* below that number. With reminders set to Never, it warns once.
- **The critical level breaks through.** Any warning while the battery is below the critical level is a critical alert, including the first one when you unplug or start the app already below it. Dropping into the critical level also always warns, even if no reminder is due or reminders are off.
- **Mute holds warnings back without losing them.** While muted, a non-critical warning is skipped before the remembered percentage is updated. When the mute ends, the app re-evaluates straight away, so a warning that came due meanwhile fires then. A mute ends when its timer runs out, when you click Unmute, or when you plug in, and it's kept in memory only, so quitting the app clears it. A timed mute ends by the clock: every refresh, and every wake from sleep, checks its end time, since timers don't count time the Mac spends asleep.
- **Plugging in clears the warning.** The banner is removed from Notification Center and an open alert closes, since the warning has been answered.
- **One alert at a time.** An alert waits for you to click OK. A warning that arrives while one is open still plays its sound, and closes the open alert to take its place, so dialogs never stack and the one on screen always shows the latest figures. That matters most for a critical warning, which would otherwise wait behind an older one.

Test warnings from Settings ignore all of this and always fire.

The rules live in `WarningRules.decide`, which takes only numbers and flags, so `test.sh` can check them without a battery. Each scenario in `Tests/WarningRulesTests.swift` steps through battery levels in order and states when Flicker should warn.

## Implementation notes

- **Battery reading**: `BatteryMonitor` uses macOS's IOKit power source API (`IOPSCopyPowerSourcesInfo`) to get the charge level, whether it's on battery or charging, and the time remaining. `IOPSNotificationCreateRunLoopSource` delivers instant updates.
- **Status line**: "Not charging" (macOS holding the charge, for example at 80%) only shows once it has lasted 3 seconds, since macOS reports that state for a moment on every plug and unplug. Until a time estimate exists, the panel says "Calculating…".
- **Faster time estimates**: macOS's own estimate takes about two minutes after unplugging or plugging in. Until then the time comes from the battery controller's `TimeRemaining` in the I/O Registry (`AppleSmartBattery`), which produces an estimate after about a minute, matching the one macOS shows later.
- **Battery health**: the health rating, maximum capacity and cycle count come from `/usr/sbin/system_profiler SPPowerDataType -json`, read at launch and whenever the panel opens, so they match System Settings. IOKit only exposes raw mAh figures, and its own health rating can disagree (it may say Poor where System Settings says Normal).
- **Warning text**: a low warning reads "Time to Charge" with "18% · about 1 hr 5 min left", a critical one "Critical Battery: 8%" with "About 12 min left. Plug in now." The time is written with units, since "1:05" on its own could pass for a clock time. Without a time estimate, that part is left out.
- **Notifications**: sent with Apple's `UserNotifications` framework. Each warning reuses one identifier, so a reminder replaces the previous banner instead of stacking. The banner's Options menu offers *Mute for 1 Hour* and *Mute Until Plugged In*. Focus can hide them (see [Known limits](#known-limits)). If notification permission isn't granted, the app falls back to AppleScript's `display notification`; macOS delivers that banner as Script Editor's, with its name and icon, so it follows Script Editor's notification setting rather than Flicker's.
- **Alerts**: a standard `NSAlert` warning dialog with the battery level drawn as a battery, a labelled tick at the warning level, and a *Mute 1 Hour* button. A critical warning uses the critical alert style, ticks the critical level and has no mute button, since a mute doesn't hold back critical warnings.
- **Sound**: played with `/usr/bin/afplay` instead of the notification sound. Notification sounds are capped by the system *alert volume*, while `afplay` follows your *output volume* and supports a boost multiplier.
- **Settings**: stored in `UserDefaults` (`~/Library/Preferences/io.github.pgardikis.flicker.plist`).
- **Settings window placement**: it reopens where you left it, as macOS windows do, but only if that spot is on the screen whose menu bar you clicked. Otherwise (the first time, another display, or one that's been disconnected) it opens centred on that screen.
- **Launch at login**: registered with `SMAppService.mainApp`.
- **Single instance**: a second copy (say the one in `build/`) sees the running one by bundle ID and quits at launch, so there are never two icons or duplicate warnings.
- **Menu bar only by default**: `LSUIElement` in `Info.plist` hides the Dock icon and app menu.
- **Version**: `CFBundleShortVersionString` in `Info.plist`, shown in the standard About window that the panel's **About** button opens, along with the copyright from `NSHumanReadableCopyright`. Each version has a matching annotated git tag, such as `v1.0`.
- **Settings tabs**: Warnings, Alert & Sound, and General, as toolbar tabs. The window takes the tab's name as its title and resizes to each tab, so even the tallest stays well within a small MacBook screen. The battery preview in Warnings redraws as the levels change, and VoiceOver reads it as text. The Banner and Alert pictures act as one picker for keyboard and VoiceOver users.
- **Optional Dock icon**: *Show in Dock* switches the app's activation policy between regular and accessory, so the icon appears or disappears without a relaunch, along with the ⌘Tab entry and the app menu. SwiftUI's menu bar item has no API to open its panel, so a click on the Dock icon finds the app's own menu bar icon and clicks it. That relies on AppKit's private `NSStatusBarWindow` class name; if the icon can't be found, the click opens Settings instead, through the app menu's Settings… item.

## What `build.sh` does

A `.app` is a folder with a fixed layout. Without Xcode, the script builds it by hand:

1. Compiles `Sources/*.swift` with `swiftc` once per architecture, then merges them with `lipo` into a universal `Flicker.app/Contents/MacOS/Flicker`
2. Draws the icon with `make-icon.swift`, then converts it to `AppIcon.icns` with `iconutil`
3. Copies `Info.plist` into the bundle
4. Signs the app with an ad-hoc signature and **hardened runtime** (`codesign --options runtime --sign -`). macOS requires a signature before an app can send notifications or launch at login.
5. With `--install`, it:
   - quits any running copy, and force-quits it if it's still running after 5 seconds
   - replaces `/Applications/Flicker.app`
   - launches the new copy, retrying up to 5 times in case macOS hasn't registered it yet (error -600)

## Screenshots

`docs/images/update-screenshots.sh` re-renders the panel images straight from `PanelView` at 4x, drawn on the sharpest connected screen since a window renders at its screen's pixel density, and draws the menu bar icon's states from `MenuBarLabel`. `compose.swift` then builds `screenshots-light.png` and `screenshots-dark.png`: each item enlarged to the Settings window's width and labelled, in one appearance with the other peeking out behind it. The README picks the one matching the visitor's GitHub theme with a `<picture>` element and `prefers-color-scheme`. The Settings window images are real Retina (2x) captures, with the window shadow, since a window drawn by a background process renders its controls as inactive.

## Where the app keeps things

| Location | What it is |
|---|---|
| Your clone of this repo | Source code. The app doesn't need it to run |
| `build/` in your clone | The freshly built app, before `--install` copies it |
| `/Applications/Flicker.app` | The installed app |
| `~/Library/Preferences/io.github.pgardikis.flicker.plist` | Saved settings |
| System Settings → General → Login Items | Launch-at-login entry |
| System Settings → Notifications → Flicker | Notification permission |

## Security

The app is intentionally minimal: no network access, no root or admin privileges, no entitlements, and no data collection.

What it does on your Mac:

- **Reads the battery** through IOKit and the I/O Registry (`AppleSmartBattery`), read-only.
- **Runs three Apple tools**, always by fixed path: `/usr/sbin/system_profiler` for battery health, `/usr/bin/afplay` for the warning sound, and `/usr/bin/osascript` for the backup notification. The only inputs that vary are the checked sound name, the volume and the notification text.
- **Shows notifications and alerts.**
- **Registers itself as a login item**, which you can turn off in Settings or System Settings.
- **Stores its settings** in its own preferences file.

### Hardening in place

- **Sound names are checked**: only names from `/System/Library/Sounds` are played, so a tampered setting can't point `afplay` at an arbitrary file.
- **No AppleScript injection**: the backup notification passes the title and message to `osascript` as arguments (`on run argv`), never inserted into the script text.
- **Hardened runtime**: blocks code injection into the running app.

### Known limits

- **Ad-hoc signed, not notarized**: a copy built on one Mac and moved to another is usually blocked by Gatekeeper, which checks apps that arrive with macOS's download flag (downloaded, AirDropped or emailed), so the app is built on each Mac that runs it. Distributing a ready-built app needs a paid Apple Developer Program membership, a Developer ID certificate and notarization.
- **No entitlements, so Focus wins**: `com.apple.developer.usernotifications.time-sensitive` would let low battery warnings pierce Focus, but it has to be authorised by a provisioning profile, which needs a paid Apple Developer Program membership. Embedding it in an ad-hoc signature anyway makes AMFI (Apple Mobile File Integrity) refuse to launch the app (`Launchd job spawn failed`, POSIX 163). Alerts aren't affected by Focus, so **Style = Alert** works around it.
- **Not sandboxed**: the sandbox would complicate launching `afplay` and `system_profiler`, an acceptable trade-off for a tool you build from source.
