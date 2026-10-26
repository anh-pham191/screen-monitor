import Foundation

/// The bookkeeping the app's Keep Awake model does around `KeepAwakePolicy`, kept here so it's
/// tested: the app layer only wires these to IOKit, timers and SwiftUI.
public enum KeepAwakeState {
    public static func badgeText(for decision: KeepAwakeDecision, port: String?) -> String? {
        guard decision.hold else { return nil }
        switch decision.reason {
        case .timer(let remaining): return KeepAwakePolicy.shortText(remaining)
        case .otherInput: return port ?? "Input"
        case nil: return nil
        }
    }

    public static func reasonLabel(_ reason: KeepAwakeReason?) -> String? {
        switch reason {
        case .timer: return "Timer"
        case .otherInput: return "Other input"
        case nil: return nil
        }
    }

    /// Idle means no tick at all: nothing can change without an input switch or a setting
    /// change, and both re-evaluate on their own. Past the away cap the rule can't hold again
    /// until the input changes, so ticking on would only burn wake-ups.
    public static func needsTick(timerEnd: Date?, awayRuleOn: Bool, awayFromMac: Bool,
                                 awaySince: Date?, now: Date) -> Bool {
        if timerEnd != nil { return true }
        guard awayRuleOn, awayFromMac else { return false }
        guard let since = awaySince else { return true }
        return now.timeIntervalSince(since) < KeepAwakePolicy.awayCap
    }

    /// Keeps the first moment the screen was seen away from the Mac, so the 8-hour cap counts from there.
    public static func nextAwaySince(current: Date?, awayFromMac: Bool, now: Date) -> Date? {
        guard awayFromMac else { return nil }
        return current ?? now
    }

    /// Only a battery stop is worth telling the user about; a finished timer is what they asked for.
    public static func nextLastStop(current: KeepAwakeStop?, decision: KeepAwakeDecision) -> KeepAwakeStop? {
        if decision.hold { return nil }
        if case .lowBattery = decision.stopped { return decision.stopped }
        return current
    }
}
