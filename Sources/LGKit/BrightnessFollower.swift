import Foundation

/// Decides when following the MacBook writes to the LG and when the offset moves.
///
/// Only manual changes (and turning on, and Reset) move the offset. A sync write never does:
/// if it did, every clamped write would wear the offset away (built-in 0.95 with +20 is clamped
/// to 100, which would turn the offset into +5).
public struct BrightnessFollower: Equatable, Sendable {
    public private(set) var offset: Int
    /// Built-in value behind the last LG value, so a slow auto-brightness ramp of sub-threshold
    /// steps still adds up to a write. Nil means the next usable poll writes.
    public private(set) var lastApplied: Double?

    public init(offset: Int = 0) {
        self.offset = offset
    }

    /// Turning sync on. Captures the offset that reproduces the LG's current value so it doesn't
    /// jump. Without a built-in reading or a known maximum the stored offset stays, and the first
    /// usable poll applies it. Returns the value to write, if any.
    public mutating func enable(lg: UInt16, builtIn: Double?, maximum: UInt16) -> UInt16? {
        lastApplied = nil
        guard maximum > 0, let builtIn = Self.usable(builtIn) else { return nil }
        offset = BrightnessSync.offset(lg: lg, builtIn: builtIn, maximum: maximum)
        lastApplied = builtIn
        return BrightnessSync.target(builtIn: builtIn, offset: offset, maximum: maximum)
    }

    /// A timer tick. Returns the LG value to write, or nil when nothing meaningful changed.
    public mutating func poll(builtIn: Double?, maximum: UInt16) -> UInt16? {
        guard maximum > 0, let builtIn = Self.usable(builtIn) else { return nil }
        if let lastApplied, !BrightnessSync.isMeaningfulChange(from: lastApplied, to: builtIn) { return nil }
        lastApplied = builtIn
        return BrightnessSync.target(builtIn: builtIn, offset: offset, maximum: maximum)
    }

    /// Slider, menu bar or keys moved the LG: the new difference becomes the offset.
    public mutating func manualChange(lg: UInt16, builtIn: Double?, maximum: UInt16) {
        guard maximum > 0, let builtIn = Self.usable(builtIn) else { return }
        offset = BrightnessSync.offset(lg: lg, builtIn: builtIn, maximum: maximum)
        lastApplied = builtIn
    }

    /// Offset back to 0, applied straight away when there is a reading to apply it to.
    public mutating func reset(builtIn: Double?, maximum: UInt16) -> UInt16? {
        offset = 0
        lastApplied = nil
        return poll(builtIn: builtIn, maximum: maximum)
    }

    private static func usable(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }
}
