/// When to warn, as plain arithmetic on the battery level and the settings. BatteryMonitor reads
/// the real values and acts on the result; Tests/WarningRulesTests.swift checks the rules directly.
enum WarningRules {
    /// What's remembered about the last warning between readings.
    struct LastWarning: Equatable {
        /// The percentage it was given at.
        var percent: Int
        /// Whether it was a critical warning.
        var critical: Bool
    }

    struct Decision: Equatable {
        /// Whether to warn now.
        var warn: Bool
        /// Whether the battery is below the critical level.
        var critical: Bool
        /// The warning to remember as the last one; nil forgets it.
        var lastWarning: LastWarning?
    }

    /// The critical level that applies: 0 when it's off, or when it isn't below the threshold.
    static func effectiveCritical(_ critical: Int, threshold: Int) -> Int {
        critical > 0 && critical < threshold ? critical : 0
    }

    /// `critical` is 0 when off, as `effectiveCritical` returns. `remindEvery` 0 means warn once.
    static func decide(percent: Int, onBattery: Bool, threshold: Int, critical: Int,
                       remindEvery: Int, lastWarning: LastWarning?, muted: Bool) -> Decision {
        // Reset when charging or back above threshold, so the next drop warns again
        if !onBattery || percent >= threshold {
            return Decision(warn: false, critical: false, lastWarning: nil)
        }

        let isCritical = critical > 0 && percent < critical
        if let lastWarning {
            // Being below the critical level always warns once, even with reminders off. The last
            // warning's own kind counts, not only its level: the critical level may have been
            // raised or turned on since, putting a battery that was warned normally below it.
            let enteredCritical = isCritical && (!lastWarning.critical || lastWarning.percent >= critical)
            if !enteredCritical && (remindEvery <= 0 || percent > lastWarning.percent - remindEvery) {
                return Decision(warn: false, critical: isCritical, lastWarning: lastWarning)
            }
        }

        // The critical level gets through a mute: that's where a missed warning costs unsaved
        // work. Keeping lastWarning unchanged means the held-back warning fires on unmute.
        if muted && !isCritical {
            return Decision(warn: false, critical: false, lastWarning: lastWarning)
        }

        return Decision(warn: true, critical: isCritical, lastWarning: LastWarning(percent: percent, critical: isCritical))
    }
}
