import Foundation

public enum Input: String, CaseIterable, Codable, Sendable {
    case mac, ps5, windows

    public var label: String {
        switch self {
        case .mac: return "Mac (HDMI 1)"
        case .ps5: return "PS5 (HDMI 2)"
        case .windows: return "Windows (USB-C)"
        }
    }
}

/// VCP 0x60 values per input. Windows/USB-C is a default only: the LG advertises 0x0F but
/// it is unverified, so Settings can change it.
public struct InputConfig: Codable, Equatable, Sendable {
    public var mac: UInt16 = 0x11
    public var ps5: UInt16 = 0x12
    public var windows: UInt16 = 0x0F

    public init() {}

    public func value(for input: Input) -> UInt16 {
        switch input {
        case .mac: return mac
        case .ps5: return ps5
        case .windows: return windows
        }
    }

    public mutating func set(_ value: UInt16, for input: Input) {
        switch input {
        case .mac: mac = value
        case .ps5: ps5 = value
        case .windows: windows = value
        }
    }

    public static func parseHex(_ text: String) -> UInt16? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("0x") || s.hasPrefix("0X") { s.removeFirst(2) }
        // UInt16(_:radix:) alone would accept a leading "+".
        guard !s.isEmpty, s.allSatisfy(\.isHexDigit) else { return nil }
        return UInt16(s, radix: 16)
    }

    public static func formatHex(_ value: UInt16) -> String {
        let digits = String(value, radix: 16, uppercase: true)
        return "0x" + String(repeating: "0", count: max(0, 2 - digits.count)) + digits
    }
}
