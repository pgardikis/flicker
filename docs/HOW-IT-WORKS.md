# How Battery Notifier works

The technical side of the app: how it reads the battery, how it decides when to warn, how `build.sh` assembles the app without Xcode, where it keeps its files, and its security model. For installing and using the app, see the [README](../README.md).

## Project structure

```
battery-notifier-macos/
├── Sources/
│   ├── BatteryNotifierApp.swift   App entry, menu bar icon, launch at login, notification setup
│   ├── BatteryMonitor.swift       Reads the battery and decides when to warn
│   ├── Notifier.swift             Shows notifications and alerts, plays sounds
│   ├── PanelView.swift            The menu bar panel: status, health and a settings summary
│   ├── SettingsView.swift         The Settings window
│   └── Settings.swift             Setting keys and defaults
├── docs/                          This file and the README's screenshots
├── build/                         Created by build.sh, not stored in git
├── Info.plist                     App metadata (menu bar only, no Dock icon)
├── make-icon.swift                Draws the app icon
├── build.sh                       Build, sign and install script
├── README.md                      Install and usage
├── LICENSE                        MIT
└── .gitignore
```

## Deciding when to warn

`BatteryMonitor` re-evaluates every time it reads the battery: when macOS reports a power change, when a warning setting changes, and every 60 seconds as a backup.

- **It warns only on battery and below *Warn below*.** Otherwise it forgets the last warning, so the next drop below the threshold warns again. Plugging in or charging back above the threshold is what resets it.
- **It remembers one number between warnings**: the percentage at the last warning. A reminder is due once the battery has dropped another *Remind again every* below that number. With reminders set to Never, it warns once.
- **The critical level breaks through.** Dropping from above the critical level to below it always warns, even if no reminder is due or reminders are off, and that warning is always an alert. Below the critical level, further reminders are critical too.
- **Mute holds warnings back without losing them.** While muted, a non-critical warning is skipped before the remembered percentage is updated. When the mute ends, the app re-evaluates straight away, so a warning that came due meanwhile fires then. A mute ends when its timer runs out, when you click Unmute, or when you plug in, and it's kept in memory only, so quitting the app clears it.
- **One alert at a time.** An alert waits for you to click OK, so a warning that arrives while one is open doesn't stack a second dialog.

Test warnings from the panel ignore all of this and always fire.

## Implementation notes

- **Battery reading**: `BatteryMonitor` uses macOS's IOKit power source API (`IOPSCopyPowerSourcesInfo`) to get the charge level, whether it's on battery or charging, and the time remaining. `IOPSNotificationCreateRunLoopSource` delivers instant updates, and a 60-second timer backs it up.
- **Status line**: "Not charging" (macOS holding the charge, for example at 80%) only shows once it has lasted 3 seconds, since macOS reports that state for a moment on every plug and unplug. Until a time estimate exists, the panel says "Calculating…".
- **Faster time estimates**: macOS's own estimate takes about two minutes after unplugging or plugging in. Until then the time comes from the battery controller's `TimeRemaining` in the I/O Registry (`AppleSmartBattery`), which has one after about a minute and agrees with macOS.
- **Battery health**: the health rating, maximum capacity and cycle count come from `/usr/sbin/system_profiler SPPowerDataType -json`, read at launch and whenever the panel opens, so they match System Settings. IOKit only exposes raw mAh figures, and its own health rating can disagree (it may say Poor where System Settings says Normal).
- **Notifications**: sent with Apple's `UserNotifications` framework. Each warning reuses one identifier, so a reminder replaces the previous banner instead of stacking. Focus can hide them (see [Known limits](#known-limits)). If notification permission isn't granted, the app falls back to AppleScript's `display notification`; that banner normally appears under Script Editor's name, and only if Script Editor is allowed to send notifications.
- **Alerts**: a standard `NSAlert` warning dialog. A critical warning uses the critical alert style.
- **Sound**: played with `/usr/bin/afplay` instead of the notification sound. Notification sounds are capped by the system *alert volume*, while `afplay` follows your *output volume* and supports a boost multiplier.
- **Settings**: stored in `UserDefaults` (`~/Library/Preferences/local.batterynotify.plist`).
- **Settings window placement**: it reopens where you left it, as macOS windows do, but only if that spot is on the screen whose menu bar you clicked. Otherwise (the first time, another display, or one that's been disconnected) it opens centred on that screen.
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
   - quits any running copy, and force-quits it if it's still running after 5 seconds
   - replaces `/Applications/Battery Notifier.app`
   - launches the new copy, retrying up to 5 times in case macOS hasn't registered it yet (error -600)

## Where the app keeps things

| Location | What it is |
|---|---|
| Your clone of this repo | Source code. The app doesn't need it to run |
| `build/` in your clone | The freshly built app, before `--install` copies it |
| `/Applications/Battery Notifier.app` | The installed app |
| `~/Library/Preferences/local.batterynotify.plist` | Saved settings |
| System Settings → General → Login Items | Launch-at-login entry |
| System Settings → Notifications → Battery Notifier | Notification permission |

## Security

The app is intentionally minimal: no network access, no root or admin privileges, no entitlements, and no data collection.

What it does on your Mac:

- **Reads the battery** through IOKit and the I/O Registry (`AppleSmartBattery`), read-only.
- **Runs three Apple tools**, always by fixed path with fixed arguments: `/usr/sbin/system_profiler` for battery health, `/usr/bin/afplay` for the warning sound, and `/usr/bin/osascript` for the backup notification.
- **Shows notifications and alerts.**
- **Registers itself as a login item**, which you can turn off in Settings or System Settings.
- **Stores its settings** in its own preferences file.

### Hardening in place

- **Sound names are checked**: only names from `/System/Library/Sounds` are played, so a tampered setting can't point `afplay` at an arbitrary file.
- **No AppleScript injection**: the backup notification passes the title and message to `osascript` as arguments (`on run argv`), never inserted into the script text.
- **Hardened runtime**: blocks code injection into the running app.

### Known limits

- **Ad-hoc signed, not notarized**: a copy built on one Mac and moved to another is blocked by Gatekeeper, so build it on each Mac. Distributing a ready-built app needs a paid Apple Developer Program membership, a Developer ID certificate and notarization.
- **No entitlements, so Focus wins**: `com.apple.developer.usernotifications.time-sensitive` would let low battery warnings pierce Focus, but it has to be authorised by a provisioning profile, which needs a paid Apple Developer Program membership. Embedding it in an ad-hoc signature anyway makes AMFI (Apple Mobile File Integrity) refuse to launch the app (`Launchd job spawn failed`, POSIX 163). Use **Style = Alert** instead.
- **Not sandboxed**: the sandbox would complicate launching `afplay` and `system_profiler`, an acceptable trade-off for a tool you build from source.
