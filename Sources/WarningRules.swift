/// When to warn, as plain arithmetic on the battery level and the settings. BatteryMonitor reads
/// the real values and acts on the result; Tests/WarningRulesTests.swift checks the rules directly.
enum WarningRules {
    struct Decision: Equatable {
        /// Whether to warn now.
        var warn: Bool
        /// Whether the battery is below the critical level.
        var critical: Bool
        /// The percentage to remember as the last warning; nil forgets it.
        var lastWarned: Int?
    }

    /// `critical` is 0 when off, as `Settings.critical` reads. `remindEvery` 0 means warn once.
    static func decide(percent: Int, onBattery: Bool, threshold: Int, critical: Int,
                       remindEvery: Int, lastWarned: Int?, muted: Bool) -> Decision {
        // Reset when charging or back above threshold, so the next drop warns again
        if !onBattery || percent >= threshold {
            return Decision(warn: false, critical: false, lastWarned: nil)
        }

        let isCritical = critical > 0 && percent < critical
        if let lastWarned {
            // Dropping into the critical level always warns, even with reminders off
            let enteredCritical = isCritical && lastWarned >= critical
            if !enteredCritical && (remindEvery <= 0 || percent > lastWarned - remindEvery) {
                return Decision(warn: false, critical: isCritical, lastWarned: lastWarned)
            }
        }

        // The critical level gets through a mute: that's where a missed warning costs unsaved
        // work. Keeping lastWarned unchanged means the held-back warning fires on unmute.
        if muted && !isCritical {
            return Decision(warn: false, critical: false, lastWarned: lastWarned)
        }

        return Decision(warn: true, critical: isCritical, lastWarned: percent)
    }
}
