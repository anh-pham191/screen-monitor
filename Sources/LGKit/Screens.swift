import Foundation

/// What CoreGraphics tells us about one screen (all four numbers come from `CGDisplay*`).
public struct ScreenInfo: Equatable, Sendable {
    public let displayID: UInt32
    public let isBuiltIn: Bool
    public let vendor: UInt32
    public let model: UInt32
    public let serial: UInt32

    public init(displayID: UInt32, isBuiltIn: Bool, vendor: UInt32, model: UInt32, serial: UInt32) {
        self.displayID = displayID
        self.isBuiltIn = isBuiltIn
        self.vendor = vendor
        self.model = model
        self.serial = serial
    }
}

public enum ScreenKind: Equatable, Sendable { case builtIn, hardware, software }

/// Which external screen has hardware control: the vendor and model from its EDID, in the same
/// numbering CoreGraphics uses. Small enough to remember across launches.
public struct HardwareScreenID: Codable, Equatable, Sendable {
    public let vendor: UInt32
    public let model: UInt32

    public init(vendor: UInt32, model: UInt32) {
        self.vendor = vendor
        self.model = model
    }

    /// Nil for a malformed manufacturer ID, which could never match a screen.
    public init?(edid: EDIDInfo) {
        guard edid.vendorNumber != 0 else { return nil }
        self.init(vendor: edid.vendorNumber, model: UInt32(edid.productCode))
    }
}

public enum ScreenClassifier {
    /// Built-in screens are `.builtIn`. The first external screen whose CoreGraphics vendor and
    /// model match the EDID read over DDC is `.hardware`; every other external screen is
    /// `.software`. Never "the first external screen": a DisplayLink screen can come first.
    public static func classify(_ screens: [ScreenInfo], hardwareEDID: EDIDInfo?) -> [UInt32: ScreenKind] {
        classify(screens, hardware: hardwareEDID.flatMap(HardwareScreenID.init(edid:)))
    }

    public static func classify(_ screens: [ScreenInfo], hardware: HardwareScreenID?) -> [UInt32: ScreenKind] {
        var kinds: [UInt32: ScreenKind] = [:]
        var foundHardware = false
        for screen in screens {
            if screen.isBuiltIn {
                kinds[screen.displayID] = .builtIn
            } else if !foundHardware, let id = hardware, id.vendor != 0,
                      screen.vendor == id.vendor, screen.model == id.model {
                kinds[screen.displayID] = .hardware
                foundHardware = true
            } else {
                kinds[screen.displayID] = .software
            }
        }
        return kinds
    }
}

public enum ScreenKey {
    /// Stable per screen: `"<vendor hex>-<model hex>-<serial>"`. Identical screens differ by serial;
    /// when the serial is 0 the screen's position among the external screens is appended.
    public static func key(for screen: ScreenInfo, among screens: [ScreenInfo]) -> String {
        let base = "\(String(screen.vendor, radix: 16))-\(String(screen.model, radix: 16))-\(screen.serial)"
        guard screen.serial == 0 else { return base }
        let external = screens.filter { !$0.isBuiltIn }
        let index = external.firstIndex { $0.displayID == screen.displayID } ?? 0
        return "\(base)#\(index)"
    }
}

public enum SoftwareDimming {
    /// Level 0 still lets 10% of the light through, so a screen can't go fully black by accident.
    public static let maximumOpacity = 0.9

    public static func clamp(_ level: Int) -> Int { min(max(level, 0), 100) }

    public static func opacity(level: Int) -> Double {
        maximumOpacity * (1 - Double(clamp(level)) / 100)
    }
}

/// Warmth as a colour temperature, applied by scaling a screen's colour tables (which removes
/// blue, like Night Shift) rather than tinting an overlay.
public enum ColorTemperature {
    /// Warmth 0 is 6500 K (neutral), 100 is 2700 K.
    public static func kelvin(warmth: Int) -> Double {
        6500 - 38 * Double(SoftwareDimming.clamp(warmth))
    }

    /// Per-channel factors 0…1, relative to 6500 K. Warmth 0 is exactly (1, 1, 1).
    public static func multipliers(warmth: Int) -> (red: Double, green: Double, blue: Double) {
        let clamped = SoftwareDimming.clamp(warmth)
        guard clamped > 0 else { return (1, 1, 1) }
        let target = blackBody(kelvin: kelvin(warmth: clamped)), neutral = blackBody(kelvin: 6500)
        func ratio(_ a: Double, _ b: Double) -> Double { b > 0 ? min(max(a / b, 0), 1) : 1 }
        return (ratio(target.red, neutral.red), ratio(target.green, neutral.green), ratio(target.blue, neutral.blue))
    }

    /// Every entry times `factor`.
    public static func scaled(_ table: [Float], by factor: Double) -> [Float] {
        table.map { Float(Double($0) * factor) }
    }

    /// Tanner Helland's black-body approximation, 0…255 per channel, for the warm side (≤ 6600 K).
    private static func blackBody(kelvin: Double) -> (red: Double, green: Double, blue: Double) {
        let t = kelvin / 100
        func clamp255(_ v: Double) -> Double { min(max(v, 0), 255) }
        let green = clamp255(99.4708025861 * log(t) - 161.1195681661)
        let blue = t <= 19 ? 0 : clamp255(138.5177312231 * log(t - 10) - 305.0447927307)
        return (255, green, blue)
    }
}

/// Remembered software brightness per screen key. Absent means 100 (no overlay).
public struct SoftwareLevels: Codable, Equatable, Sendable {
    private var levels: [String: Int] = [:]
    private var warmths: [String: Int] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey { case levels, warmths }

    /// Data saved before warmth existed has no `warmths`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        levels = try c.decodeIfPresent([String: Int].self, forKey: .levels) ?? [:]
        warmths = try c.decodeIfPresent([String: Int].self, forKey: .warmths) ?? [:]
    }

    public func warmth(for key: String) -> Int { warmths[key] ?? 0 }

    public mutating func setWarmth(_ warmth: Int, for key: String) {
        warmths[key] = SoftwareDimming.clamp(warmth)
    }

    public func level(for key: String) -> Int { levels[key] ?? 100 }

    public mutating func set(_ level: Int, for key: String) {
        levels[key] = SoftwareDimming.clamp(level)
    }

    /// Returns whether a level was stored.
    @discardableResult
    public mutating func forget(_ key: String) -> Bool {
        let hadWarmth = warmths.removeValue(forKey: key) != nil
        return levels.removeValue(forKey: key) != nil || hadWarmth
    }
}
