import Testing
import Foundation
import LGKit

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

// MARK: - Badge

@Test func badgeShowsShortTextForTimer() {
    let d = KeepAwakeDecision(hold: true, reason: .timer(remaining: 3600 + 15 * 60), clearTimer: false, stopped: nil)
    #expect(KeepAwakeState.badgeText(for: d) == "1h 15m")
}

@Test func badgeShowsPS5ForPS5Rule() {
    let d = KeepAwakeDecision(hold: true, reason: .ps5, clearTimer: false, stopped: nil)
    #expect(KeepAwakeState.badgeText(for: d) == "PS5")
}

@Test func badgeIsNilWhenNotHolding() {
    #expect(KeepAwakeState.badgeText(for: .idle) == nil)
    let stopped = KeepAwakeDecision(hold: false, reason: nil, clearTimer: true, stopped: .lowBattery(threshold: 20))
    #expect(KeepAwakeState.badgeText(for: stopped) == nil)
}

@Test func reasonLabelMatchesDesign() {
    #expect(KeepAwakeState.reasonLabel(.timer(remaining: 60)) == "Timer")
    #expect(KeepAwakeState.reasonLabel(.ps5) == "PS5")
    #expect(KeepAwakeState.reasonLabel(nil) == nil)
}

// MARK: - Tick

private func tick(timerEnd: Date? = nil, ps5RuleOn: Bool = true, ps5Showing: Bool = false,
                  ps5Since: Date? = t0, now: Date = t0) -> Bool {
    KeepAwakeState.needsTick(timerEnd: timerEnd, ps5RuleOn: ps5RuleOn, ps5Showing: ps5Showing,
                             ps5Since: ps5Since, now: now)
}

@Test func ticksWhileTimerRuns() {
    #expect(tick(timerEnd: t0, ps5RuleOn: false))
}

@Test func ticksWhilePS5RuleCouldHold() {
    #expect(tick(ps5Showing: true))
    #expect(tick(ps5Showing: true, now: t0 + KeepAwakePolicy.ps5Cap - 1))
}

@Test func idleWithoutTimerOrPS5() {
    #expect(!tick(ps5Showing: false))
    #expect(!tick(ps5RuleOn: false, ps5Showing: true))
}

@Test func stopsTickingOncePS5CapPasses() {
    #expect(!tick(ps5Showing: true, now: t0 + KeepAwakePolicy.ps5Cap))
}

// MARK: - PS5 start time

@Test func ps5SinceStartsWhenPS5Appears() {
    #expect(KeepAwakeState.nextPS5Since(current: nil, ps5Showing: true, now: t0) == t0)
}

@Test func ps5SinceKeepsOriginalStartWhilePS5Stays() {
    // Restarting the clock on every tick would defeat the 8-hour cap.
    #expect(KeepAwakeState.nextPS5Since(current: t0, ps5Showing: true, now: t0 + 3600) == t0)
}

@Test func ps5SinceClearsOnSwitchAway() {
    #expect(KeepAwakeState.nextPS5Since(current: t0, ps5Showing: false, now: t0 + 60) == nil)
    #expect(KeepAwakeState.nextPS5Since(current: nil, ps5Showing: false, now: t0) == nil)
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
    let d = KeepAwakeDecision(hold: true, reason: .ps5, clearTimer: false, stopped: nil)
    #expect(KeepAwakeState.nextLastStop(current: .lowBattery(threshold: 20), decision: d) == nil)
}

@Test func idleKeepsLastStopVisible() {
    #expect(KeepAwakeState.nextLastStop(current: .lowBattery(threshold: 20), decision: .idle) == .lowBattery(threshold: 20))
}
