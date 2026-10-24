public struct EDIDInfo: Equatable, Sendable {
    public let manufacturerID: String
    public let productCode: UInt16
    public let serialNumber: UInt32
    public let week: Int
    public let year: Int
    public let widthCm: Int
    public let heightCm: Int
    public let name: String?
    public let serialString: String?

    public init(manufacturerID: String, productCode: UInt16, serialNumber: UInt32, week: Int, year: Int,
                widthCm: Int, heightCm: Int, name: String?, serialString: String?) {
        self.manufacturerID = manufacturerID
        self.productCode = productCode
        self.serialNumber = serialNumber
        self.week = week
        self.year = year
        self.widthCm = widthCm
        self.heightCm = heightCm
        self.name = name
        self.serialString = serialString
    }

    private static let header: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]

    /// Parses the 128-byte EDID base block; extension blocks are ignored.
    public static func parse(_ bytes: [UInt8]) -> EDIDInfo? {
        guard bytes.count >= 128,
              Array(bytes[0..<8]) == header,
              bytes[0..<128].reduce(0, { $0 &+ $1 }) == 0 else { return nil }

        // Three 5-bit letters packed big-endian, where 1 means "A".
        let packed = UInt16(bytes[8]) << 8 | UInt16(bytes[9])
        let letters = [10, 5, 0].map { shift in
            Character(UnicodeScalar(UInt8((packed >> UInt16(shift)) & 0x1F) + 64))
        }

        var name: String?
        var serialString: String?
        for offset in [54, 72, 90, 108] {
            // A display descriptor starts with three zero bytes; anything else is a timing block.
            guard bytes[offset] == 0, bytes[offset + 1] == 0, bytes[offset + 2] == 0 else { continue }
            switch bytes[offset + 3] {
            case 0xFC: name = descriptorText(bytes, at: offset)
            case 0xFF: serialString = descriptorText(bytes, at: offset)
            default: break
            }
        }

        return EDIDInfo(
            manufacturerID: String(letters),
            productCode: UInt16(bytes[10]) | UInt16(bytes[11]) << 8,
            serialNumber: (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[12 + $1]) << UInt32(8 * $1) },
            week: Int(bytes[16]),
            year: 1990 + Int(bytes[17]),
            widthCm: Int(bytes[21]),
            heightCm: Int(bytes[22]),
            name: name,
            serialString: serialString
        )
    }

    private static func descriptorText(_ bytes: [UInt8], at offset: Int) -> String {
        let raw = bytes[(offset + 5)..<(offset + 18)].prefix { $0 != 0x0A }
        var text = String(decoding: raw, as: UTF8.self)
        while text.last == " " { text.removeLast() }
        return text
    }
}
