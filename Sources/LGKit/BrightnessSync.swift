import Foundation

public enum BrightnessSync {
    /// LG target for a built-in brightness (0...1) plus an offset in the LG's own units.
    public static func target(builtIn: Double, offset: Int, maximum: UInt16) -> UInt16 {
        let base = Int((builtIn * Double(maximum)).rounded())
        return UInt16(min(max(base + offset, 0), Int(maximum)))
    }

    /// Offset that makes `target` reproduce the LG's current value.
    public static func offset(lg: UInt16, builtIn: Double, maximum: UInt16) -> Int {
        Int(lg) - Int((builtIn * Double(maximum)).rounded())
    }

    public static func isMeaningfulChange(from old: Double, to new: Double) -> Bool {
        abs(new - old) >= 0.01
    }
}
