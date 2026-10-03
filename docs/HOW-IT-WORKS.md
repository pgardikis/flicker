# How Battery Notifier works

The technical side of the app: how it reads the battery, how `build.sh` assembles the app without Xcode, where it keeps its files, and its security model. For installing and using the app, see the [README](../README.md).

## Project structure

```
battery-notifier-macos/
├── Sources/
│   ├── BatteryNotifierApp.swift   App entry, menu bar icon, launch at login, notification setup
│   ├── BatteryMonitor.swift     Reads the battery and decides when to warn
│   ├── Notifier.swift           Shows notifications/alerts and plays sounds
│   ├── PanelView.swift          The menu bar panel: status, health and a settings summary
│   ├── SettingsView.swift       The Settings window
│   └── Settings.swift           Setting keys and defaults
├── docs/                        This file and the README's screenshots
├── Info.plist                   App metadata (menu bar only, no Dock icon)
├── make-icon.swift              Draws the app icon
├── build.sh                     Build, sign and install script
├── LICENSE                      MIT
└── .gitignore
```

## Components

- **Battery reading**: `BatteryMonitor` uses macOS's IOKit power source API (`IOPSCopyPowerSourcesInfo`) to get the charge level, whether it's on battery, and time remaining. `IOPSNotificationCreateRunLoopSource` delivers instant updates, and a 60-second timer backs it up.
- **Status line**: "Not charging" (macOS holding the charge, for example at 80%) only shows once it has lasted 3 seconds, since macOS reports that state for a moment on every plug and unplug. Until a time estimate exists, the panel says Calculating….
- **Faster time estimates**: macOS's own estimate takes about two minutes after unplugging or plugging in. Until then the time comes from the battery controller's `TimeRemaining` in the I/O Registry (`AppleSmartBattery`), which has one after about a minute and agrees with macOS.
- **Battery health**: the health rating, maximum capacity and cycle count come from `/usr/sbin/system_profiler SPPowerDataType -json`, read at launch and whenever the panel opens, so they match System Settings. IOKit only exposes raw mAh figures, and its own health rating can disagree (it may say Poor where System Settings says Normal).
- **Notifications**: sent with Apple's `UserNotifications` framework. Each warning reuses one identifier, so a reminder replaces the previous banner instead of stacking. If notification permission isn't granted, the app falls back to AppleScript's `display notification`. The code asks for a *time sensitive* interruption level, but macOS ignores that without an entitlement from a paid Apple Developer Program membership (see Known limits), so notifications are suppressed by Focus.
- **Alerts**: a standard `NSAlert` warning dialog. A critical warning uses the critical alert style.
- **Sound**: played with `/usr/bin/afplay` instead of the notification sound. Notification sounds are capped by the system *alert volume*. `afplay` follows your *output volume* and supports a boost multiplier.
- **Settings**: stored in `UserDefaults` (`~/Library/Preferences/local.batterynotify.plist`).
- **Launch at login**: registered with `SMAppService.mainApp`.
- **Single instance**: a second copy (say the one in `build/`) sees the running one by bundle ID and quits at launch, so there are never two icons or duplicate warnings. Run the app from `/Applications`.
- **Menu bar only**: `LSUIElement` in `Info.plist` hides the Dock icon and app menu.

## What `build.sh` does

A `.app` is a folder with a fixed layout. Without Xcode, the script builds it by hand:

1. Compiles `Sources/*.swift` with `swiftc` once per architecture, then merges them with `lipo` into a universal `Battery Notifier.app/Contents/MacOS/BatteryNotifier`
2. Draws the icon with `make-icon.swift`, then converts it to `AppIcon.icns` with `iconutil`
3. Copies `Info.plist` into the bundle
4. Signs the app with an ad-hoc signature and **hardened runtime** (`codesign --options runtime --sign -`). macOS requires a signature before an app can send notifications or launch at login.
5. With `--install`, it:
   - quits any running copy, and force-quits it after 5 seconds
   - replaces `/Applications/Battery Notifier.app`
   - launches the new copy, retrying up to 5 times in case macOS hasn't registered it yet (error -600)

## Where the app keeps things

| Location | What it is |
|---|---|
| Your clone of this repo | Source code. The app doesn't need it to run |
| `/Applications/Battery Notifier.app` | The installed app |
| `~/Library/Preferences/local.batterynotify.plist` | Saved settings |
| System Settings → General → Login Items | Launch-at-login entry |
| System Settings → Notifications → Battery Notifier | Notification permission |

## Security

The app is intentionally minimal:

- no network access, no root or admin privileges, no entitlements, no data collection
- only reads battery state, shows notifications and plays system sounds

Hardening in place:

- **Sound names are checked**: only names from `/System/Library/Sounds` are played, so a tampered setting can't point `afplay` at an arbitrary file.
- **No AppleScript injection**: the fallback notification passes the title and message to `osascript` as arguments (`on run argv`), never inserted into the script text.
- **Hardened runtime**: blocks code injection into the running app.

Known limits:

- **Ad-hoc signed, not notarized**: a copy built on one Mac and moved to another is blocked by Gatekeeper, so build it on each Mac. Distributing a ready-built app needs a paid Apple Developer Program membership, a Developer ID certificate and notarization.
- **No entitlements, so Focus wins**: `com.apple.developer.usernotifications.time-sensitive` would let low battery warnings pierce Focus, but it has to be authorised by a provisioning profile, which needs a paid Apple Developer Program membership. Embedding it in an ad-hoc signature anyway makes AMFI refuse to launch the app (`Launchd job spawn failed`, POSIX 163). Use **Style = Alert** instead.
- **Not sandboxed**: fine for a personal tool, since the sandbox would complicate launching `afplay`.
