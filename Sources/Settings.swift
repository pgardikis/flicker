import Foundation

/// UserDefaults keys and default values shared by the UI and the battery monitor.
enum Settings {
    static let thresholdKey = "threshold"
    static let criticalKey = "critical"
    static let remindEveryKey = "remindEvery"
    static let styleKey = "style"
    static let soundKey = "sound"
    static let criticalSoundKey = "criticalSound"
    static let volumeKey = "volume"
    static let showPercentKey = "showPercent"
    static let showInDockKey = "showInDock"
    static let didSetupLoginItemKey = "didSetupLoginItem"

    static let defaultThreshold = 40
    static let defaultCritical = 10
    static let defaultRemindEvery = 5
    static let defaultStyle = "notification"
    static let defaultSound = "Sosumi"
    /// The critical sound's value for "use the Sound setting".
    static let sameSound = "same"
    static let defaultCriticalSound = sameSound
    static let defaultVolume = 3.0
    static let defaultShowPercent = true
    static let defaultShowInDock = false

    static let criticalOptions = [5, 10, 15, 20]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            thresholdKey: defaultThreshold,
            criticalKey: defaultCritical,
            remindEveryKey: defaultRemindEvery,
            styleKey: defaultStyle,
            soundKey: defaultSound,
            criticalSoundKey: defaultCriticalSound,
            volumeKey: defaultVolume,
            showPercentKey: defaultShowPercent,
            showInDockKey: defaultShowInDock,
        ])
    }

    /// Clamped like the volume, since `defaults write` can store anything.
    static var threshold: Int { min(max(UserDefaults.standard.integer(forKey: thresholdKey), 5), 95) }
    /// 0 when off, or when it isn't below the threshold and so can't apply.
    static var critical: Int {
        let critical = UserDefaults.standard.integer(forKey: criticalKey)
        return critical < threshold ? critical : 0
    }
    static var remindEvery: Int { UserDefaults.standard.integer(forKey: remindEveryKey) }
    static var style: String { UserDefaults.standard.string(forKey: styleKey) ?? defaultStyle }
    static var sound: String { UserDefaults.standard.string(forKey: soundKey) ?? "" }
    /// The sound for critical warnings, with "same" resolved to the Sound setting.
    static var criticalSound: String {
        let value = UserDefaults.standard.string(forKey: criticalSoundKey) ?? defaultCriticalSound
        return value == sameSound ? sound : value
    }
    static var volume: Double { min(max(UserDefaults.standard.double(forKey: volumeKey), 0.5), 4) }
    static var showInDock: Bool { UserDefaults.standard.bool(forKey: showInDockKey) }
}
