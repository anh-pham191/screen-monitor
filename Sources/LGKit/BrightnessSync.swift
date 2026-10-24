import Foundation

public enum BrightnessSync {
    /// LG target for a built-in brightness (0...1) plus an offset in the LG's own units.
    public static func target(builtIn: Double, offset: Int, maximum: UInt16) -> UInt16 {
        let base = scaled(builtIn, maximum)
        return UInt16(min(max(base + offset, 0), Int(maximum)))
    }

    /// Offset that makes `target` reproduce the LG's current value.
    public static func offset(lg: UInt16, builtIn: Double, maximum: UInt16) -> Int {
        Int(lg) - scaled(builtIn, maximum)
    }

    public static func isMeaningfulChange(from old: Double, to new: Double) -> Bool {
        abs(new - old) >= 0.01
    }

    /// A private API can hand back anything, and `Int(_:)` traps on NaN or infinity.
    /// NaN counts as 0; everything else is clamped to 0...1.
    private static func scaled(_ builtIn: Double, _ maximum: UInt16) -> Int {
        let fraction = builtIn.isNaN ? 0 : min(max(builtIn, 0), 1)
        return Int((fraction * Double(maximum)).rounded())
    }
}
