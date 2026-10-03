# AGENTS.md

## Overview

A macOS 14+ menu bar app (SwiftUI `MenuBarExtra`, no Dock icon via `LSUIElement`) that warns when the battery drops below a user-set threshold. There is no Xcode project or Swift package: the `.app` bundle is assembled by hand in `build.sh` using only the Command Line Tools.

## Commands

```bash
./build.sh            # build universal app → build/Battery Notify.app
./build.sh --install  # build, quit running copy, replace /Applications/Battery Notify.app, relaunch
```

- The compiler runs in **Swift 6 language mode** (`-swift-version 6`) with `-parse-as-library`, once per arch (arm64, x86_64), then merged with `lipo`. Strict concurrency errors will fail the build.
- There are no tests and no linter. Verify changes by building, installing, and using the panel's **Test** button.
- Run the app from `/Applications`. A second running copy (for example the one in `build/`) detects the first by bundle ID and quits itself at launch.

## Architecture

- `BatteryNotifyApp.swift`: `@main` app plus `AppDelegate`. The delegate enforces a single instance, registers defaults, requests notification permission, turns on launch at login the first time (`SMAppService`, guarded by `didSetupLoginItem`), and starts the monitor.
- `BatteryMonitor` (`@MainActor` singleton, `ObservableObject`): reads the internal battery through IOKit (`IOPSCopyPowerSourcesInfo`) and holds all the warning logic. Updates arrive from an `IOPSNotificationCreateRunLoopSource` callback plus a 60 s `Timer`. Both are added in **common run loop modes** so they keep firing while a modal `NSAlert` or the menu is open. The C callback gets back to the instance with `Unmanaged` and `MainActor.assumeIsolated`. The health rating, maximum capacity and cycle count (`BatteryDetails`) come from `system_profiler SPPowerDataType -json` on a detached task, read at launch and when the panel opens. Don't switch them to IOKit: its mAh figures and its health rating don't match System Settings. Missing time estimates (IOKit reports -1 for about two minutes after a power change) fall back to `AppleSmartBattery`'s `TimeRemaining` (65535 means none), re-read every 10 s until one exists. The JSON's `Good` is shown as "Normal", as System Settings does. Only the rating is colored (green Normal, red otherwise), never the capacity, so nothing can contradict macOS; light mode uses a darker green, since system green is too pale for small text there.
- Warning logic in `evaluate()`: warn only when on battery and below threshold. `lastWarned` stores the percentage at the last warning. A reminder fires after each further `remindEvery` drop (`0` means warn once). Dropping below the critical level always warns, whatever the reminder state. While muted (`mutedUntil`, `.distantFuture` meaning until plugged in), non-critical warnings return before `lastWarned` is set, so the held-back warning fires when `unmute()` re-evaluates. Plugging in ends a mute, and the mute is in memory only. `Settings.critical` reads as 0 unless it's below the threshold, and `SettingsView` clamps it when the threshold moves. Charging or going back above the threshold resets `lastWarned` to nil. If no battery is found, every published field is cleared. `statusText` only says "Not charging" once that has lasted `notChargingDelay`, because IOKit reports adapter-connected-but-not-charging for a moment on every plug and unplug.
- `Notifier`: plays the sound itself through `/usr/bin/afplay`, so volume follows the output volume and can be boosted. It then shows either an `NSAlert` (guarded by `alertShowing`, since `runModal` blocks; always used for critical warnings, since Focus can't hide it) or a `UNUserNotification` with the fixed identifier `low-battery`, so each reminder replaces the last banner. If notification permission is missing, it falls back to `osascript`.
- `PanelView` is the menu bar panel: status, health line, a summary of the warning settings, and the mute and test menus. Menu labels render as template images that drop SwiftUI colors, so the orange muted bell is a non-template `NSImage`.
- `SettingsView` is the window of a SwiftUI `Settings` scene, written `SwiftUI.Settings` because our `Settings` enum shadows it. The panel's Settings… button activates the app first (a menu bar app's window otherwise opens behind others), calls `openSettings`, and closes the panel. Settings apply immediately, with no Done button, as Apple's guidelines expect.
- `Settings`: the `UserDefaults` keys and defaults. `SettingsView` binds to the same keys with `@AppStorage`, and the monitor reads them through `Settings.*`. Add any new setting in both places. `SettingsView` calls `monitor.refresh()` when a warning setting changes (the threshold slider only on release), and the 60 s timer catches anything else, such as `defaults write`.

## Constraints to preserve

- **Ad-hoc signing with hardened runtime** (`codesign --options runtime --sign -`) is required for notifications and launch at login. Do **not** add entitlements such as `com.apple.developer.usernotifications.time-sensitive`. They need a paid Developer ID provisioning profile, and in an ad-hoc signature they make AMFI refuse to launch the app (POSIX 163). `interruptionLevel = .timeSensitive` is deliberately left in the code even though it has no effect on this build.
- **Security hardening**: `playSound` only plays names listed in `Notifier.availableSounds` (from `/System/Library/Sounds`). The `osascript` fallback passes the title and message as `argv` and never interpolates them into the script text. Keep both.
- The app has no network access, no sandbox and no privileges. Keep it that way.
- `README.md` documents the settings, behavior and build steps in detail. Update it when behavior changes.

## Commit messages

- Subject: [Conventional Commits](https://www.conventionalcommits.org) style, `<type>: <description>`. The description is a lowercase imperative sentence with no trailing period, such as `feat: show the battery health rating in the panel`.
- Types: `feat` (new behavior), `fix` (bug fix), `docs` (README, AGENTS.md, comments), `refactor` (no behavior change), `perf`, `build` (`build.sh`, `Info.plist`, compiler flags, icon), `chore` (anything else).
- Add a body whenever the change isn't self-explanatory from the subject. Leave a blank line after the subject and wrap at about 72 columns. Explain what was wrong or missing and why this fix was chosen, including side effects or alternatives ruled out. Don't restate the diff. Older commits predate the type prefix but show the kind of body to write.
