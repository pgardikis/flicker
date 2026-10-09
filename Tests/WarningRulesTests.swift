// Checks WarningRules.decide without a battery: each scenario feeds levels in order, as the app
// would see them, and compares when it warns. Built and run by test.sh.

import Foundation

/// One battery reading, and what Flicker should do at it.
private struct Step {
    var percent: Int
    var onBattery = true
    var muted = false
    /// nil: no warning; false: a low warning; true: a critical warning.
    var expect: Bool?
}

private struct Scenario {
    let name: String
    var threshold = 40
    var critical = 10
    var remindEvery = 5
    let steps: [Step]
}

private let low = false, critical = true

private let scenarios: [Scenario] = [
    Scenario(name: "warns once the battery drops below the threshold", steps: [
        Step(percent: 41), Step(percent: 40), Step(percent: 39, expect: low),
    ]),
    Scenario(name: "never warns on the adapter, however low", steps: [
        Step(percent: 30, onBattery: false), Step(percent: 5, onBattery: false),
    ]),
    Scenario(name: "reminds after each further drop of the reminder step", steps: [
        Step(percent: 38, expect: low), Step(percent: 34), Step(percent: 33, expect: low),
        Step(percent: 29), Step(percent: 28, expect: low),
    ]),
    Scenario(name: "with reminders off, warns once until the critical level", remindEvery: 0, steps: [
        Step(percent: 38, expect: low), Step(percent: 25), Step(percent: 11),
        Step(percent: 9, expect: critical), Step(percent: 5),
    ]),
    Scenario(name: "entering the critical level warns even when no reminder is due", remindEvery: 10, steps: [
        Step(percent: 12, expect: low), Step(percent: 9, expect: critical),
    ]),
    Scenario(name: "below the critical level, reminders are critical warnings", steps: [
        Step(percent: 9, expect: critical), Step(percent: 5), Step(percent: 4, expect: critical),
    ]),
    Scenario(name: "with the critical level off, low warnings continue to the end", critical: 0, steps: [
        Step(percent: 9, expect: low), Step(percent: 4, expect: low),
    ]),
    Scenario(name: "a mute holds back low warnings and releases them when it ends", steps: [
        Step(percent: 39, muted: true), Step(percent: 30, muted: true), Step(percent: 30, expect: low),
    ]),
    Scenario(name: "a critical warning gets through a mute", steps: [
        Step(percent: 30, muted: true), Step(percent: 9, muted: true, expect: critical),
    ]),
    Scenario(name: "plugging in forgets the last warning, so the next drop warns again", steps: [
        Step(percent: 35, expect: low), Step(percent: 36, onBattery: false),
        Step(percent: 35, expect: low),
    ]),
    Scenario(name: "rising back to the threshold forgets the last warning", steps: [
        Step(percent: 35, expect: low), Step(percent: 40), Step(percent: 39, expect: low),
    ]),
    Scenario(name: "lowering the threshold below the level stops warnings", threshold: 20, steps: [
        Step(percent: 35), Step(percent: 25), Step(percent: 19, expect: low),
    ]),
]

@main
enum WarningRulesTests {
    static func main() {
        var failures = 0
        for scenario in scenarios {
            var lastWarned: Int?
            var problems: [String] = []
            for step in scenario.steps {
                let decision = WarningRules.decide(
                    percent: step.percent, onBattery: step.onBattery, threshold: scenario.threshold,
                    critical: scenario.critical, remindEvery: scenario.remindEvery,
                    lastWarned: lastWarned, muted: step.muted)
                lastWarned = decision.lastWarned
                let got: Bool? = decision.warn ? decision.critical : nil
                if got != step.expect {
                    problems.append("at \(step.percent)%: expected \(describe(step.expect)), got \(describe(got))")
                }
            }
            if problems.isEmpty {
                print("✓ \(scenario.name)")
            } else {
                failures += 1
                print("✗ \(scenario.name)")
                problems.forEach { print("    \($0)") }
            }
        }
        print("\(scenarios.count - failures) of \(scenarios.count) passed")
        if failures > 0 { exit(1) }
    }

    private static func describe(_ warning: Bool?) -> String {
        switch warning {
        case nil: "no warning"
        case false?: "a low warning"
        case true?: "a critical warning"
        }
    }
}
