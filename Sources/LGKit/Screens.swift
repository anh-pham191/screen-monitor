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

public enum ScreenClassifier {
    /// Built-in screens are `.builtIn`. The first external screen whose CoreGraphics vendor and
    /// model match the EDID read over DDC is `.hardware`; every other external screen is
    /// `.software`. Never "the first external screen": a DisplayLink screen can come first.
    public static func classify(_ screens: [ScreenInfo], hardwareEDID: EDIDInfo?) -> [UInt32: ScreenKind] {
        var kinds: [UInt32: ScreenKind] = [:]
        var foundHardware = false
        for screen in screens {
            if screen.isBuiltIn {
                kinds[screen.displayID] = .builtIn
            } else if !foundHardware, let edid = hardwareEDID, edid.vendorNumber != 0,
                      screen.vendor == edid.vendorNumber, screen.model == UInt32(edid.productCode) {
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

/// Remembered software brightness per screen key. Absent means 100 (no overlay).
public struct SoftwareLevels: Codable, Equatable, Sendable {
    private var levels: [String: Int] = [:]

    public init() {}

    public func level(for key: String) -> Int { levels[key] ?? 100 }

    public mutating func set(_ level: Int, for key: String) {
        levels[key] = SoftwareDimming.clamp(level)
    }
}
