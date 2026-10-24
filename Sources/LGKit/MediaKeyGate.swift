import Foundation

/// What the key tap does with one event.
public enum KeyAction: Equatable, Sendable {
    /// Give the event back to macOS unchanged.
    case passThrough
    /// Drop the event without acting on it (the rest of a press the LG owns).
    case swallow
    /// Drop the event and step the LG.
    case handle(fine: Bool)
}

/// Decides, per press, whether the LG or macOS owns a media key.
///
/// The owner is fixed by the first key-down of a press. Repeats and the key-up follow it even if
/// the pointer or sound output changes mid-press, so macOS never sees a key-up for a key-down it
/// didn't get, and one held key never drives two displays.
public struct MediaKeyGate: Sendable {
    private var owned: Set<MediaKey> = []

    public init() {}

    /// - Parameters:
    ///   - modifiers: the result of `KeyRouter.modifiersAllowHandling` for the event's flags.
    ///   - canHandle: false while the LG's maximum for this control is unknown.
    ///   - route: asked only for the first key-down of a press, because it may query CoreAudio.
    public mutating func decide(_ event: MediaKeyEvent, modifiers: (handle: Bool, fine: Bool),
                                canHandle: Bool, route: () -> KeyRoute) -> KeyAction {
        guard event.isDown else {
            return owned.remove(event.key) != nil ? .swallow : .passThrough
        }
        if event.isRepeat {
            guard owned.contains(event.key) else { return .passThrough }
            // Mute is a toggle, not a step: acting on each repeat would flick it on and off while held.
            if event.key == .mute { return .swallow }
            return modifiers.handle && canHandle ? .handle(fine: modifiers.fine) : .swallow
        }
        // A fresh press: forget any press whose key-up we never saw.
        owned.remove(event.key)
        guard modifiers.handle, canHandle, route() == .lg else { return .passThrough }
        owned.insert(event.key)
        return .handle(fine: modifiers.fine)
    }
}

extension MediaKey: Hashable {}

extension Stepper {
    /// Slider values are Doubles; DDC values are UInt16. Round, and clamp anything out of range.
    public static func wireValue(_ value: Double) -> UInt16 {
        guard value.isFinite else { return 0 }
        return UInt16(min(max(value.rounded(), 0), Double(UInt16.max)))
    }
}

/// Pure maths for the on-screen indicator.
public enum HUDLevel {
    public static func fraction(_ value: UInt16, maximum: UInt16) -> Double {
        maximum == 0 ? 0 : Double(value) / Double(maximum)
    }

    /// How full each segment is (0...1), so quarter steps show as part-filled segments like macOS.
    public static func segmentFills(level: Double, count: Int) -> [Double] {
        let filled = min(max(level, 0), 1) * Double(count)
        return (0..<count).map { min(max(filled - Double($0), 0), 1) }
    }
}
