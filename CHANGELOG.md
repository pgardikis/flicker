# Changelog

What changed in each version of Flicker. Versions are tagged in git; `vX.Y` adds features and `vX.Y.Z` only fixes.

## [1.2] - 2026-11-18

### Added

- Warnings show as an alert when notifications are off for Flicker, so they're never lost.

### Changed

- Requires macOS 15 or later.
- The alert's mute button reads "Mute for 1 Hour", like the banner's.
- VoiceOver reads the menu bar icon as Flicker with the battery level, instead of the symbol's name.
- The battery checks allow macOS a little timing slack, which saves energy.

### Fixed

- Clicking the Dock icon or a warning banner opens the panel again on macOS 27.
- Raising or turning on the critical level while the battery is already below it warns straight away, instead of at the next reminder.
- The Launch at login toggle no longer switches itself off while macOS waits for approval. Settings now says so and opens Login Items.

### Removed

- The Script Editor notification used when notifications were off, replaced by the alert.

## [1.1.3] - 2026-10-13

### Fixed

- Flicker no longer crashes at launch on macOS 14 and 15.

## [1.1.2] - 2026-10-13

### Fixed

- Builds with the macOS 27 Command Line Tools.

## [1.1.1] - 2026-10-09

### Changed

- Builds about twice as fast.

### Fixed

- A warning that arrives while an alert is open replaces it, so a critical warning is never stuck behind an older one.
- Mutes end on time after the Mac sleeps.
- Choosing Mute Until Plugged In on the adapter no longer cancels a timed mute that's running.
- Settings written with `defaults write` are kept within their allowed ranges, and sound previews within the volume range.
- The health line no longer shows a red warning icon when macOS gives no health rating.
- VoiceOver tells the two sound preview buttons apart.
- `./build.sh --install` quits any running copy before replacing it.

## [1.1] - 2026-10-09

### Added

- A Settings window with Warnings, Alert & Sound and General tabs, a battery picture of the warning and critical levels, pictures of the Banner and Alert styles, and buttons that preview the sounds.
- An About window with the version, opened from the panel.

## [1.0] - 2026-10-07

First release, for macOS 14 or later.

- Low battery warnings below a level you choose, from 5% to 95%
- Reminders after every further 1, 2, 5 or 10% drop, or just once
- A critical level, below which the warning is always an alert that Focus can't hide
- Notification or alert, with any classic macOS alert sound at up to 400% volume
- Mute for 30 minutes, 1 hour or until you plug in, from the panel or straight from the warning
- Battery status: time remaining, charging, fully charged or not charging
- Battery health, maximum capacity and cycle count, as System Settings shows them
- Percentage in the menu bar, an optional Dock icon, and launch at login

[1.2]: https://github.com/pgardikis/flicker/compare/v1.1.3...v1.2
[1.1.3]: https://github.com/pgardikis/flicker/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/pgardikis/flicker/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/pgardikis/flicker/compare/v1.1...v1.1.1
[1.1]: https://github.com/pgardikis/flicker/compare/v1.0...v1.1
[1.0]: https://github.com/pgardikis/flicker/tree/v1.0
