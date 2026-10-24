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

/// How inputs are switched. Standard VCP 0x60 makes this LG blank and bounce straight back to
/// HDMI 1; LG's own command (VCP 0xF4 at data address 0x50) holds the new input.
public enum InputCommand: String, Codable, CaseIterable, Sendable {
    case lg, standard

    public var vcp: UInt8 {
        switch self {
        case .lg: return 0xF4
        case .standard: return VCP.inputSource
        }
    }

    public var dataAddress: UInt32 {
        switch self {
        case .lg: return 0x50
        case .standard: return 0x51
        }
    }

    public var label: String {
        switch self {
        case .lg: return "LG (recommended)"
        case .standard: return "Standard (VCP 0x60)"
        }
    }
}

/// Input values for the chosen command. Windows/USB-C is a default only (0xD1 under LG's
/// command, 0x0F under standard): neither is verified, so Settings can change it.
public struct InputConfig: Codable, Equatable, Sendable {
    public var command: InputCommand = .lg
    public var mac: UInt16 = 0x90
    public var ps5: UInt16 = 0x91
    public var windows: UInt16 = 0xD1

    public init() {}

    public static func defaults(for command: InputCommand) -> InputConfig {
        var c = InputConfig()
        c.command = command
        switch command {
        case .lg: (c.mac, c.ps5, c.windows) = (0x90, 0x91, 0xD1)
        case .standard: (c.mac, c.ps5, c.windows) = (0x11, 0x12, 0x0F)
        }
        return c
    }

    /// Values only make sense for one command, so switching resets them to its defaults.
    public mutating func setCommand(_ command: InputCommand) {
        self = Self.defaults(for: command)
    }

    private enum CodingKeys: String, CodingKey { case command, mac, ps5, windows }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Configs saved before the command existed held standard VCP 0x60 values.
        let command = try container.decodeIfPresent(InputCommand.self, forKey: .command) ?? .standard
        self = Self.defaults(for: command)
        if let v = try container.decodeIfPresent(UInt16.self, forKey: .mac) { mac = v }
        if let v = try container.decodeIfPresent(UInt16.self, forKey: .ps5) { ps5 = v }
        if let v = try container.decodeIfPresent(UInt16.self, forKey: .windows) { windows = v }
    }

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
