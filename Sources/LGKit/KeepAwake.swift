import Foundation

public enum KeepAwakePreset: Int, CaseIterable, Sendable {
    case hour1 = 60, hour2 = 120, hour4 = 240, hour6 = 360, hour8 = 480, hour10 = 600

    public var label: String { "\(rawValue / 60)h" }

    public var duration: TimeInterval { TimeInterval(rawValue * 60) }
}

public struct KeepAwakeInputs: Equatable, Sendable {
    public var timerEnd: Date?
    public var now: Date
    public var awayFromMac: Bool
    public var awayRuleOn: Bool
    public var onBattery: Bool
    public var batteryPercent: Int?
    public var batteryThreshold: Int
    public var awaySince: Date?

    public init(timerEnd: Date?, now: Date, awayFromMac: Bool, awayRuleOn: Bool, onBattery: Bool,
                batteryPercent: Int?, batteryThreshold: Int, awaySince: Date?) {
        self.timerEnd = timerEnd
        self.now = now
        self.awayFromMac = awayFromMac
        self.awayRuleOn = awayRuleOn
        self.onBattery = onBattery
        self.batteryPercent = batteryPercent
        self.batteryThreshold = batteryThreshold
        self.awaySince = awaySince
    }
}

public enum KeepAwakeReason: Equatable, Sendable {
    case timer(remaining: TimeInterval), otherInput
}

public enum KeepAwakeStop: Equatable, Sendable {
    case timerFinished, lowBattery(threshold: Int)
}

public struct KeepAwakeDecision: Equatable, Sendable {
    public let hold: Bool
    public let reason: KeepAwakeReason?
    public let clearTimer: Bool
    public let stopped: KeepAwakeStop?

    public init(hold: Bool, reason: KeepAwakeReason?, clearTimer: Bool, stopped: KeepAwakeStop?) {
        self.hold = hold
        self.reason = reason
        self.clearTimer = clearTimer
        self.stopped = stopped
    }

    public static let idle = KeepAwakeDecision(hold: false, reason: nil, clearTimer: false, stopped: nil)
}

public enum KeepAwakePolicy {
    /// The LG answers DDC on every input, so a switch back made with the monitor's own
    /// buttons is invisible to the app. The cap stops the away rule keeping the Mac up forever.
    public static let awayCap: TimeInterval = 8 * 3600

    public static func evaluate(_ i: KeepAwakeInputs) -> KeepAwakeDecision {
        let awayWouldHold = awayHolds(i)

        // Strict "below": sitting exactly at the threshold keeps running.
        if i.onBattery, let percent = i.batteryPercent, percent < i.batteryThreshold {
            // An expired timer still counts as running: the stop is what ended it.
            let hadSomething = i.timerEnd != nil || awayWouldHold
            return KeepAwakeDecision(hold: false, reason: nil, clearTimer: i.timerEnd != nil,
                                     stopped: hadSomething ? .lowBattery(threshold: i.batteryThreshold) : nil)
        }

        var clearTimer = false
        var stopped: KeepAwakeStop?
        if let end = i.timerEnd {
            if end > i.now {
                return KeepAwakeDecision(hold: true, reason: .timer(remaining: end.timeIntervalSince(i.now)),
                                         clearTimer: false, stopped: nil)
            }
            clearTimer = true
            stopped = .timerFinished
        }

        if awayWouldHold {
            // The other input carries on seamlessly, so there's nothing to report as stopped.
            return KeepAwakeDecision(hold: true, reason: .otherInput, clearTimer: clearTimer, stopped: nil)
        }
        return KeepAwakeDecision(hold: false, reason: nil, clearTimer: clearTimer, stopped: stopped)
    }

    /// Without a start time the cap can't be enforced, so the rule fails safe and doesn't hold.
    private static func awayHolds(_ i: KeepAwakeInputs) -> Bool {
        guard i.awayRuleOn, i.awayFromMac, let since = i.awaySince else { return false }
        return i.now.timeIntervalSince(since) < awayCap
    }

    public static func shortText(_ remaining: TimeInterval) -> String {
        guard let (h, m) = split(remaining) else { return "<1m" }
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    public static func longText(_ remaining: TimeInterval) -> String {
        guard let (h, m) = split(remaining) else { return "Less than a minute left" }
        if h == 0 { return "\(m) min left" }
        return m == 0 ? "\(h) h left" : "\(h) h \(m) min left"
    }

    /// Rounds up so the countdown never reads "0 min" while time remains.
    private static func split(_ remaining: TimeInterval) -> (hours: Int, minutes: Int)? {
        guard remaining >= 60 else { return nil }
        let total = Int(ceil(remaining / 60))
        return total >= 60 ? (total / 60, total % 60) : (0, total)
    }

    /// Rounds up, like `split`, so the clock only reads "0:00" once the time is really up.
    public static func clockText(_ remaining: TimeInterval) -> String {
        let s = max(0, Int(ceil(remaining)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        let ss = sec < 10 ? "0\(sec)" : "\(sec)"
        if h > 0 { return "\(h):\(m < 10 ? "0\(m)" : "\(m)"):\(ss)" }
        return "\(m):\(ss)"
    }

    public static func ringProgress(remaining: TimeInterval, total: TimeInterval) -> Double {
        guard total > 0 else { return 0 }
        return min(max(remaining / total, 0), 1)
    }

    public static func clampThreshold(_ v: Int) -> Int {
        let bounded = min(max(v, 5), 50)
        return (bounded + 2) / 5 * 5
    }
}
