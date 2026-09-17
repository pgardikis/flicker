import Foundation

/// UserDefaults keys and default values shared by the UI and the battery monitor.
enum Settings {
    static let thresholdKey = "threshold"
    static let remindEveryKey = "remindEvery"
    static let styleKey = "style"
    static let soundKey = "sound"
    static let volumeKey = "volume"
    static let didSetupLoginItemKey = "didSetupLoginItem"

    static let defaultThreshold = 40
    static let defaultRemindEvery = 5
    static let defaultStyle = "notification"
    static let defaultSound = "Sosumi"
    static let defaultVolume = 3.0

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            thresholdKey: defaultThreshold,
            remindEveryKey: defaultRemindEvery,
            styleKey: defaultStyle,
            soundKey: defaultSound,
            volumeKey: defaultVolume,
        ])
    }

    static var threshold: Int { UserDefaults.standard.integer(forKey: thresholdKey) }
    static var remindEvery: Int { UserDefaults.standard.integer(forKey: remindEveryKey) }
    static var style: String { UserDefaults.standard.string(forKey: styleKey) ?? defaultStyle }
    static var sound: String { UserDefaults.standard.string(forKey: soundKey) ?? "" }
    static var volume: Double { UserDefaults.standard.double(forKey: volumeKey) }
}
