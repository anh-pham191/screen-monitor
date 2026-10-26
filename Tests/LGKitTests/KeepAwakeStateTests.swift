import Testing
import Foundation
import LGKit

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

// MARK: - Badge

@Test func badgeShowsShortTextForTimer() {
    let d = KeepAwakeDecision(hold: true, reason: .timer(remaining: 3600 + 15 * 60), clearTimer: false, stopped: nil)
    #expect(KeepAwakeState.badgeText(for: d, port: nil) == "1h 15m")
}

@Test func awayBadgeShowsThePort() {
    let d = KeepAwakeDecision(hold: true, reason: .otherInput, clearTimer: false, stopped: nil)
    #expect(KeepAwakeState.badgeText(for: d, port: "HDMI 2") == "HDMI 2")
    #expect(KeepAwakeState.badgeText(for: d, port: nil) == "Input")
    #expect(KeepAwakeState.reasonLabel(.otherInput) == "Other input")
}

@Test func badgeIsNilWhenNotHolding() {
    #expect(KeepAwakeState.badgeText(for: .idle, port: nil) == nil)
    let stopped = KeepAwakeDecision(hold: false, reason: nil, clearTimer: true, stopped: .lowBattery(threshold: 20))
    #expect(KeepAwakeState.badgeText(for: stopped, port: nil) == nil)
}

@Test func reasonLabelMatchesDesign() {
    #expect(KeepAwakeState.reasonLabel(.timer(remaining: 60)) == "Timer")
    #expect(KeepAwakeState.reasonLabel(.otherInput) == "Other input")
    #expect(KeepAwakeState.reasonLabel(nil) == nil)
}

// MARK: - Tick

private func tick(timerEnd: Date? = nil, awayRuleOn: Bool = true, awayFromMac: Bool = false,
                  awaySince: Date? = t0, now: Date = t0) -> Bool {
    KeepAwakeState.needsTick(timerEnd: timerEnd, awayRuleOn: awayRuleOn, awayFromMac: awayFromMac,
                             awaySince: awaySince, now: now)
}

@Test func ticksWhileTimerRuns() {
    #expect(tick(timerEnd: t0, awayRuleOn: false))
}

@Test func ticksWhileAwayRuleCouldHold() {
    #expect(tick(awayFromMac: true))
    #expect(tick(awayFromMac: true, now: t0 + KeepAwakePolicy.awayCap - 1))
}

@Test func idleWithoutTimerOrAway() {
    #expect(!tick(awayFromMac: false))
    #expect(!tick(awayRuleOn: false, awayFromMac: true))
}

@Test func stopsTickingOnceAwayCapPasses() {
    #expect(!tick(awayFromMac: true, now: t0 + KeepAwakePolicy.awayCap))
}

// MARK: - Away start time

@Test func awaySinceStartsWhenAwayBegins() {
    #expect(KeepAwakeState.nextAwaySince(current: nil, awayFromMac: true, now: t0) == t0)
}

@Test func awaySinceKeepsOriginalStartWhileAwayStays() {
    // Restarting the clock on every tick would defeat the 8-hour cap.
    #expect(KeepAwakeState.nextAwaySince(current: t0, awayFromMac: true, now: t0 + 3600) == t0)
}

@Test func awaySinceClearsOnSwitchAway() {
    #expect(KeepAwakeState.nextAwaySince(current: t0, awayFromMac: false, now: t0 + 60) == nil)
    #expect(KeepAwakeState.nextAwaySince(current: nil, awayFromMac: false, now: t0) == nil)
}

// MARK: - Last stop

@Test func lowBatterySetsLastStop() {
    let d = KeepAwakeDecision(hold: false, reason: nil, clearTimer: true, stopped: .lowBattery(threshold: 25))
    #expect(KeepAwakeState.nextLastStop(current: nil, decision: d) == .lowBattery(threshold: 25))
}

@Test func timerFinishedIsNeverShown() {
    let d = KeepAwakeDecision(hold: false, reason: nil, clearTimer: true, stopped: .timerFinished)
    #expect(KeepAwakeState.nextLastStop(current: nil, decision: d) == nil)
    #expect(KeepAwakeState.nextLastStop(current: .lowBattery(threshold: 20), decision: d) == .lowBattery(threshold: 20))
}

@Test func holdingClearsLastStop() {
    let d = KeepAwakeDecision(hold: true, reason: .otherInput, clearTimer: false, stopped: nil)
    #expect(KeepAwakeState.nextLastStop(current: .lowBattery(threshold: 20), decision: d) == nil)
}

@Test func idleKeepsLastStopVisible() {
    #expect(KeepAwakeState.nextLastStop(current: .lowBattery(threshold: 20), decision: .idle) == .lowBattery(threshold: 20))
}
