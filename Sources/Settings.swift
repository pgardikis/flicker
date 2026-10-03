import Foundation

/// UserDefaults keys and default values shared by the UI and the battery monitor.
enum Settings {
    static let thresholdKey = "threshold"
    static let criticalKey = "critical"
    static let remindEveryKey = "remindEvery"
    static let styleKey = "style"
    static let soundKey = "sound"
    static let volumeKey = "volume"
    static let showPercentKey = "showPercent"
    static let didSetupLoginItemKey = "didSetupLoginItem"

    static let defaultThreshold = 40
    static let defaultCritical = 10
    static let defaultRemindEvery = 5
    static let defaultStyle = "notification"
    static let defaultSound = "Sosumi"
    static let defaultVolume = 3.0
    static let defaultShowPercent = true

    static let criticalOptions = [5, 10, 15, 20]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            thresholdKey: defaultThreshold,
            criticalKey: defaultCritical,
            remindEveryKey: defaultRemindEvery,
            styleKey: defaultStyle,
            soundKey: defaultSound,
            volumeKey: defaultVolume,
            showPercentKey: defaultShowPercent,
        ])
    }

    static var threshold: Int { UserDefaults.standard.integer(forKey: thresholdKey) }
    /// 0 when off, or when it isn't below the threshold and so can't apply.
    static var critical: Int {
        let critical = UserDefaults.standard.integer(forKey: criticalKey)
        return critical < threshold ? critical : 0
    }
    static var remindEvery: Int { UserDefaults.standard.integer(forKey: remindEveryKey) }
    static var style: String { UserDefaults.standard.string(forKey: styleKey) ?? defaultStyle }
    static var sound: String { UserDefaults.standard.string(forKey: soundKey) ?? "" }
    static var volume: Double { UserDefaults.standard.double(forKey: volumeKey) }
}
