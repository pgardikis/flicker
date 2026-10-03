# Battery Notifier

A lightweight macOS menu bar app that warns you, with a notification or an alert and a sound, when your MacBook's battery runs low.

macOS only warns once, at a level it picks. Battery Notifier warns at the level you choose, reminds you as the battery keeps dropping, plays a sound loud enough to notice, and can show alerts that get through Focus.

## Screenshots

| Light | Dark |
|---|---|
| <img src="docs/images/panel-light.png" width="340" alt="Battery Notifier panel in light mode"> | <img src="docs/images/panel-dark.png" width="340" alt="Battery Notifier panel in dark mode"> |
| <img src="docs/images/settings-light.png" width="340" alt="Settings window in light mode"> | <img src="docs/images/settings-dark.png" width="340" alt="Settings window in dark mode"> |

## Features

- **Low battery warnings** below a level you choose, from 5% to 95%
- **Reminders** after every further 1, 2, 5 or 10% drop, or just once
- **Critical level**: below it, the warning is always an alert that Focus can't hide
- **Notification or alert**, with any macOS system sound at up to 400% volume
- **Mute** for 30 minutes, 1 hour or until you plug in
- **Battery status**: time remaining, charging, fully charged or not charging
- **Battery health**, maximum capacity and cycle count, as System Settings shows them
- **Percentage in the menu bar** (optional) and **launch at login**
- **Private**: no network access and no data collection

## Install

You need a MacBook (Intel or Apple Silicon) with macOS 14 (Sonoma) or later, plus the Xcode Command Line Tools (`xcode-select --install`). The full Xcode app isn't needed.

```bash
git clone https://github.com/pgardikis/battery-notifier-macos.git
cd battery-notifier-macos
./build.sh --install    # builds, copies to /Applications and launches
```

On first launch, click **Allow** when macOS asks about notifications. The app turns on launch at login, so macOS may show a "Background item added" notice.

The app isn't notarized, so build it on each Mac you want to use it on. Run `./build.sh --install` again after pulling changes.

## Usage

Click the fuel pump to open the panel. It shows the battery, its health and a summary of your warnings. **Test** sends a test warning, and the bell mutes warnings. **Settings…** opens the Settings window, where changes apply straight away.

| Setting | Default | Options | What it does |
|---|---|---|---|
| Warn below | 40% | 5–95% | Warns when on battery and below this level |
| Critical level | 10% | Off, 5, 10, 15, 20% | Below this, always warns with an alert |
| Remind again every | 5% drop | Never, 1, 2, 5, 10% | Warns again after each further drop |
| Style | Notification | Notification, Alert | A banner, or a dialog that stays until you click OK |
| Sound | Sosumi | Any system sound, None | Played with every warning |
| Volume | 300% | 50–400% | Relative to your speaker volume (see below) |
| Show percentage in menu bar | On | On, Off | Shows the level next to the fuel pump |
| Launch at login | On | On, Off | Starts the app when you log in |

The critical level always stays below *Warn below*: Settings only offers lower values, and moves it down if you drag *Warn below* under it.

Volume is relative to your speaker volume: 100% plays the sound at that volume, and higher values amplify the sound itself. Your Mac's volume setting is never changed, and if your Mac is muted, the warning sound is silent too.

### When it warns

- Only when the Mac is on battery and below *Warn below*.
- Again after each *Remind again every* drop, for example 39% → 34% → 29%.
- Always when the battery drops below the *Critical level*, as an alert.
- While muted, only critical warnings get through.
- Plugging in resets the reminders and ends any mute.

The menu bar icon fills with a "!" while the battery is low, and is crossed out while muted.

## Troubleshooting

**No notification appears.** Allow notifications for Battery Notifier in System Settings → Notifications, then try the panel's **Test** button.

**Nothing appears during Focus or Do Not Disturb.** Letting notifications through Focus needs an entitlement that only a paid Apple Developer Program membership can provide. Set **Style** to **Alert** instead: alerts aren't affected by Focus. Critical warnings are always alerts.

**The sound is too quiet.** Raise **Volume** in Settings, and your speaker volume, since it's relative to that.

**It doesn't start at login.** Check System Settings → General → Login Items, or turn **Launch at login** off and on in Settings.

## Uninstall

1. Click the fuel pump and choose **Quit**
2. Remove **Battery Notifier** in System Settings → General → Login Items
3. Delete `/Applications/Battery Notifier.app`
4. Delete its settings: `defaults delete local.batterynotify`
5. Delete the folder you cloned

## Technical details

How the app reads the battery, how `build.sh` builds it without Xcode, where it keeps files, and its security model are covered in [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

## License

[MIT](LICENSE)
