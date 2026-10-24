import Testing
import Foundation
import LGKit

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func inputs(timerEnd: Date? = nil, ps5Showing: Bool = false, ps5RuleOn: Bool = true,
                    onBattery: Bool = false, batteryPercent: Int? = nil, batteryThreshold: Int = 20,
                    ps5Since: Date? = t0) -> KeepAwakeInputs {
    KeepAwakeInputs(timerEnd: timerEnd, now: t0, ps5Showing: ps5Showing, ps5RuleOn: ps5RuleOn,
                    onBattery: onBattery, batteryPercent: batteryPercent,
                    batteryThreshold: batteryThreshold, ps5Since: ps5Since)
}

private func decision(_ hold: Bool, _ reason: KeepAwakeReason?, clear: Bool = false,
                      stopped: KeepAwakeStop? = nil) -> KeepAwakeDecision {
    KeepAwakeDecision(hold: hold, reason: reason, clearTimer: clear, stopped: stopped)
}

// MARK: - Rules

@Test func idleWithNothingRunning() {
    #expect(KeepAwakePolicy.evaluate(inputs()) == .idle)
    #expect(KeepAwakeDecision.idle == decision(false, nil))
}

@Test func runningTimerHoldsWithRemaining() {
    let d = KeepAwakePolicy.evaluate(inputs(timerEnd: t0 + 900))
    #expect(d == decision(true, .timer(remaining: 900)))
}

@Test func runningTimerBeatsPS5Reason() {
    let d = KeepAwakePolicy.evaluate(inputs(timerEnd: t0 + 60, ps5Showing: true))
    #expect(d == decision(true, .timer(remaining: 60)))
}

@Test func expiredTimerStopsWhenNothingElseHolds() {
    #expect(KeepAwakePolicy.evaluate(inputs(timerEnd: t0)) == decision(false, nil, clear: true, stopped: .timerFinished))
    #expect(KeepAwakePolicy.evaluate(inputs(timerEnd: t0 - 5)) == decision(false, nil, clear: true, stopped: .timerFinished))
}

@Test func expiredTimerFallsThroughToPS5() {
    let d = KeepAwakePolicy.evaluate(inputs(timerEnd: t0 - 1, ps5Showing: true))
    #expect(d == decision(true, .ps5, clear: true, stopped: nil))
}

@Test func ps5HoldsOnlyWhenRuleOnAndShowing() {
    #expect(KeepAwakePolicy.evaluate(inputs(ps5Showing: true)) == decision(true, .ps5))
    #expect(KeepAwakePolicy.evaluate(inputs(ps5Showing: true, ps5RuleOn: false)) == .idle)
    #expect(KeepAwakePolicy.evaluate(inputs(ps5Showing: false, ps5RuleOn: true)) == .idle)
}

@Test func ps5CapIsEightHours() {
    let cap: TimeInterval = 8 * 3600
    #expect(KeepAwakePolicy.evaluate(inputs(ps5Showing: true, ps5Since: t0 - (cap - 1))) == decision(true, .ps5))
    #expect(KeepAwakePolicy.evaluate(inputs(ps5Showing: true, ps5Since: t0 - cap)) == .idle)
    #expect(KeepAwakePolicy.evaluate(inputs(ps5Showing: true, ps5Since: t0 - (cap + 60))) == .idle)
}

@Test func ps5WithoutStartTimeDoesNotHold() {
    // No start time means the cap can't be enforced, so fail safe.
    #expect(KeepAwakePolicy.evaluate(inputs(ps5Showing: true, ps5Since: nil)) == .idle)
}

@Test func lowBatteryBeatsTimer() {
    let d = KeepAwakePolicy.evaluate(inputs(timerEnd: t0 + 600, onBattery: true, batteryPercent: 10))
    #expect(d == decision(false, nil, clear: true, stopped: .lowBattery(threshold: 20)))
}

@Test func lowBatteryBeatsPS5() {
    let d = KeepAwakePolicy.evaluate(inputs(ps5Showing: true, onBattery: true, batteryPercent: 10, batteryThreshold: 25))
    #expect(d == decision(false, nil, clear: false, stopped: .lowBattery(threshold: 25)))
}

@Test func lowBatteryWithExpiredTimerCountsAsRunning() {
    let d = KeepAwakePolicy.evaluate(inputs(timerEnd: t0 - 30, onBattery: true, batteryPercent: 5))
    #expect(d == decision(false, nil, clear: true, stopped: .lowBattery(threshold: 20)))
}

@Test func lowBatteryWithNothingToStopReportsNothing() {
    #expect(KeepAwakePolicy.evaluate(inputs(onBattery: true, batteryPercent: 5)) == .idle)
    // PS5 showing but the rule is off, or past its cap: nothing would have held.
    #expect(KeepAwakePolicy.evaluate(inputs(ps5Showing: true, ps5RuleOn: false, onBattery: true, batteryPercent: 5)) == .idle)
    #expect(KeepAwakePolicy.evaluate(inputs(ps5Showing: true, onBattery: true, batteryPercent: 5, ps5Since: t0 - 9 * 3600)) == .idle)
}

@Test func unknownBatteryLevelNeverStops() {
    let d = KeepAwakePolicy.evaluate(inputs(timerEnd: t0 + 60, onBattery: true, batteryPercent: nil))
    #expect(d == decision(true, .timer(remaining: 60)))
}

@Test func pluggedInNeverStopsEvenWhenLow() {
    let d = KeepAwakePolicy.evaluate(inputs(timerEnd: t0 + 60, onBattery: false, batteryPercent: 3))
    #expect(d == decision(true, .timer(remaining: 60)))
}

@Test func batteryThresholdIsStrict() {
    let atThreshold = KeepAwakePolicy.evaluate(inputs(timerEnd: t0 + 60, onBattery: true, batteryPercent: 20))
    #expect(atThreshold == decision(true, .timer(remaining: 60)))
    let below = KeepAwakePolicy.evaluate(inputs(timerEnd: t0 + 60, onBattery: true, batteryPercent: 19))
    #expect(below == decision(false, nil, clear: true, stopped: .lowBattery(threshold: 20)))
}

// MARK: - Presets

@Test func presetMinutesAndLabels() {
    #expect(KeepAwakePreset.allCases.map(\.rawValue) == [60, 120, 240, 360, 480, 600])
    #expect(KeepAwakePreset.allCases.map(\.label) == ["1h", "2h", "4h", "6h", "8h", "10h"])
    #expect(KeepAwakePreset.allCases.map(\.duration) == [3600, 7200, 14400, 21600, 28800, 36000])
}

// MARK: - Clock and ring

@Test(arguments: [
    (3582.0, "59:42"), (7182.0, "1:59:42"), (36000.0, "10:00:00"), (59.2, "1:00"),
    (0.0, "0:00"), (-5.0, "0:00"), (600.0, "10:00"),
])
func clockText(remaining: TimeInterval, expected: String) {
    #expect(KeepAwakePolicy.clockText(remaining) == expected)
}

@Test(arguments: [
    (1800.0, 3600.0, 0.5), (4000.0, 3600.0, 1.0), (-1.0, 3600.0, 0.0), (5.0, 0.0, 0.0),
])
func ringProgress(remaining: TimeInterval, total: TimeInterval, expected: Double) {
    #expect(KeepAwakePolicy.ringProgress(remaining: remaining, total: total) == expected)
}

// MARK: - Text

@Test(arguments: [
    (3900.0, "1h 5m", "1 h 5 min left"),
    (7200.0, "2h", "2 h left"),
    (2700.0, "45m", "45 min left"),
    (3570.0, "1h", "1 h left"),
    (30.0, "<1m", "Less than a minute left"),
    (3599.0, "1h", "1 h left"),
    (3601.0, "1h 1m", "1 h 1 min left"),
    (60.0, "1m", "1 min left"),
    (61.0, "2m", "2 min left"),
    (59.0, "<1m", "Less than a minute left"),
    (899.99, "15m", "15 min left"),
    (36000.0, "10h", "10 h left"),
])
func remainingText(_ remaining: Double, _ short: String, _ long: String) {
    #expect(KeepAwakePolicy.shortText(remaining) == short)
    #expect(KeepAwakePolicy.longText(remaining) == long)
}

// MARK: - Threshold

@Test(arguments: [(3, 5), (22, 20), (23, 25), (99, 50), (7, 5), (8, 10), (5, 5), (50, 50), (-10, 5)])
func clampThreshold(_ input: Int, _ expected: Int) {
    #expect(KeepAwakePolicy.clampThreshold(input) == expected)
}
