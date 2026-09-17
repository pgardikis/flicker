# Battery Notify

A lightweight macOS menu bar app that warns you when your battery drops below a percentage you choose.

It lives in the menu bar as a ⛽ fuel pump icon, checks the battery level in the background, and shows a notification (or an alert that stays on screen) with a sound when it's time to plug in.

## Features

- **Custom threshold**: warn below any level from 5% to 95% (default 40%)
- **Reminders**: warn again after every further 1 / 2 / 5 / 10% drop, or only once
- **Two styles**: a notification banner, or an alert that stays until you click OK
- **Sound**: any macOS system sound, with a preview button and a volume boost up to 4×
- **Launch at login**
- **Live battery status**: percentage, charging state and time remaining in the panel
- **Send Test Warning** button to check your settings

The fuel pump becomes filled with a "!" while the battery is below your threshold.

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon Mac (the build targets `arm64`)
- Xcode Command Line Tools for the Swift compiler: `xcode-select --install`

You don't need the full Xcode app.

## Build and install

```bash
./build.sh            # build only → build/Battery Notify.app
./build.sh --install  # build, copy to /Applications, and launch
```

Run `./build.sh --install` again after any code change. It quits the running copy, replaces it and relaunches.

On first launch:
- macOS asks to **allow notifications** for Battery Notify. Click Allow.
- The app turns on **launch at login**, and macOS may show a "Background item added" notice.

Always run the app from `/Applications`. Opening the copy in `build/` as well starts a second instance, which means two icons and duplicate warnings.

## Settings

Click the fuel pump icon in the menu bar to open the panel. Changes save instantly.

| Setting | Default | Description |
|---|---|---|
| Warn below | 40% | Warns when on battery and below this level |
| Remind again every | 5% drop | Warns again after each further drop. `Never` warns once |
| Style | Notification | `Notification` shows a banner. `Alert` shows a dialog until dismissed |
| Sound | Sosumi | Any sound from `/System/Library/Sounds`, or None |
| Volume | 3.0× | 0.5–4×. Relative to your speaker volume |
| Launch at login | On | Starts the app when you log in |

### When it warns

- A warning fires only when the Mac is **on battery** and **below the threshold**.
- After the first warning, it reminds you again once the level drops another *Remind again every* amount (e.g. 39% → 34% → 29%).
- Plugging in, or charging back above the threshold, resets it, so the next drop warns again.
- The level is read immediately when macOS reports a power change, with a check every 60 seconds as a backup.

## How it works

### Project structure

```
battery-notify/
├── Sources/
│   ├── BatteryNotifyApp.swift   App entry, menu bar icon, launch at login, notification setup
│   ├── BatteryMonitor.swift     Reads the battery and decides when to warn
│   ├── Notifier.swift           Shows notifications/alerts and plays sounds
│   ├── SettingsView.swift       The settings panel (SwiftUI)
│   └── Settings.swift           Setting keys and defaults
├── Info.plist                   App metadata (menu bar only, no Dock icon)
├── make-icon.swift              Draws the app icon
├── build.sh                     Build, sign and install script
└── .gitignore
```

### Components

- **Battery reading**: `BatteryMonitor` uses macOS's IOKit power source API (`IOPSCopyPowerSourcesInfo`) to get the charge level, whether it's on battery, and time remaining. `IOPSNotificationCreateRunLoopSource` delivers instant updates, and a 60-second timer backs it up.
- **Notifications**: sent with Apple's `UserNotifications` framework. If notification permission isn't granted, the app falls back to AppleScript's `display notification`.
- **Alerts**: a standard `NSAlert` warning dialog.
- **Sound**: played with `/usr/bin/afplay` instead of the notification sound. Notification sounds are capped by the system *alert volume*. `afplay` follows your *output volume* and supports a boost multiplier.
- **Settings**: stored in `UserDefaults` (`~/Library/Preferences/local.batterynotify.plist`).
- **Launch at login**: registered with `SMAppService.mainApp`.
- **Menu bar only**: `LSUIElement` in `Info.plist` hides the Dock icon and app menu.

### What `build.sh` does

A `.app` is a folder with a fixed layout. Without Xcode, the script builds it by hand:

1. Compiles `Sources/*.swift` with `swiftc` into `Battery Notify.app/Contents/MacOS/BatteryNotify`
2. Draws the icon with `make-icon.swift`, then converts it to `AppIcon.icns` with `iconutil`
3. Copies `Info.plist` into the bundle
4. Signs the app with an ad-hoc signature and **hardened runtime** (`codesign --options runtime --sign -`). macOS requires a signature before an app can send notifications or launch at login.
5. With `--install`, it:
   - quits any running copy, and force-quits it after 5 seconds
   - replaces `/Applications/Battery Notify.app`
   - launches the new copy, retrying up to 5 times in case macOS hasn't registered it yet (error -600)

## Where the app keeps things

| Location | What it is |
|---|---|
| `~/workspace/battery-notify/` | Source code. The app doesn't need it to run |
| `/Applications/Battery Notify.app` | The installed app |
| `~/Library/Preferences/local.batterynotify.plist` | Saved settings |
| System Settings → General → Login Items | Launch-at-login entry |
| System Settings → Notifications → Battery Notify | Notification permission |

## Uninstall

1. Click the fuel pump icon and choose **Quit**
2. Remove **Battery Notify** in System Settings → General → Login Items
3. Delete `/Applications/Battery Notify.app`
4. Delete settings: `rm ~/Library/Preferences/local.batterynotify.plist`

## Security

The app is intentionally minimal:

- no network access, no root or admin privileges, no entitlements, no data collection
- only reads battery state, shows notifications and plays system sounds

Hardening in place:

- **Sound names are checked**: only names from `/System/Library/Sounds` are played, so a tampered setting can't point `afplay` at an arbitrary file.
- **No AppleScript injection**: the fallback notification passes the title and message to `osascript` as arguments (`on run argv`), never inserted into the script text.
- **Hardened runtime**: blocks code injection into the running app.

Known limits:

- **Ad-hoc signed**: the app works only on the Mac that built it. Sharing it with others needs a paid Apple Developer ID and notarization.
- **Not sandboxed**: fine for a personal tool, since the sandbox would complicate launching `afplay`.

## Troubleshooting

**No notification appears**
Allow notifications for Battery Notify in System Settings → Notifications. Turn off Focus / Do Not Disturb. Use **Send Test Warning** to check. Or switch Style to **Alert**, which doesn't need notification permission.

**Sound too quiet**
Increase Volume in the panel. It's relative to your speaker volume, so turn that up too. Values above about 4× tend to distort.

**Two fuel pump icons in the menu bar**
Two copies are running, usually one from `build/` and one from `/Applications`. Quit both, then open only `/Applications/Battery Notify.app`. Check with:
```bash
ps -axo pid,command | grep "[B]atteryNotify"
```

**Doesn't start at login**
Check System Settings → General → Login Items, or toggle **Launch at login** off and on in the panel.

**`open` fails with error -600 after installing**
`build.sh --install` retries automatically. If it still fails, open the app from Applications manually.
