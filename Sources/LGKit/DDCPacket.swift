/// VCP feature codes (MCCS) used by LG Control.
public enum VCP {
    public static let brightness: UInt8 = 0x10
    public static let contrast: UInt8 = 0x12
    public static let inputSource: UInt8 = 0x60
    public static let volume: UInt8 = 0x62
    public static let mute: UInt8 = 0x8D
}

public struct VCPReading: Equatable, Sendable {
    public let current: UInt16
    public let maximum: UInt16

    public init(current: UInt16, maximum: UInt16) {
        self.current = current
        self.maximum = maximum
    }
}

/// Pure DDC/CI packet encoding and decoding; no I/O.
public enum DDCPacket {
    static let chipAddress: UInt32 = 0x37
    public static let dataAddress: UInt32 = 0x51

    // The checksum seeds with the destination (0x6E) and data-address bytes,
    // which the transport sends but the payload doesn't contain.
    private static func withChecksum(_ body: [UInt8], dataAddress: UInt32 = dataAddress) -> [UInt8] {
        body + [body.reduce(0x6E ^ UInt8(truncatingIfNeeded: dataAddress), ^)]
    }

    static func getRequest(_ code: UInt8) -> [UInt8] {
        withChecksum([0x82, 0x01, code])
    }

    static func setRequest(_ code: UInt8, value: UInt16, dataAddress: UInt32 = DDCPacket.dataAddress) -> [UInt8] {
        withChecksum([0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF)], dataAddress: dataAddress)
    }

    static func capabilitiesRequest(offset: UInt16) -> [UInt8] {
        withChecksum([0x83, 0xF3, UInt8(offset >> 8), UInt8(offset & 0xFF)])
    }

    static func parseGetReply(_ bytes: [UInt8], code: UInt8) -> VCPReading? {
        // [1] is only checked for the length flag: the exact length byte is unverified on hardware.
        guard bytes.count >= 11, bytes[1] & 0x80 != 0, bytes[2] == 0x02,
              bytes[3] == 0x00, bytes[4] == code else { return nil }
        return VCPReading(
            current: UInt16(bytes[8]) << 8 | UInt16(bytes[9]),
            maximum: UInt16(bytes[6]) << 8 | UInt16(bytes[7])
        )
    }

    static func parseCapabilitiesReply(_ bytes: [UInt8], offset: UInt16) -> [UInt8]? {
        guard bytes.count >= 5, bytes[1] & 0x80 != 0 else { return nil }
        let n = Int(bytes[1] & 0x7F)
        guard bytes[2] == 0xE3, n >= 3,
              UInt16(bytes[3]) << 8 | UInt16(bytes[4]) == offset,
              bytes.count >= 5 + (n - 3) else { return nil }
        return Array(bytes[5 ..< 5 + n - 3])
    }
}
