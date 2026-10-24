import Testing
@testable import LGKit

let lgEDID = "00ffffffffffff001e6dbb5c0100000001240103803c2278ea1c95af5047aa260f5054210800d1c0614045400101010101010101010108e80030f2705a80b0588a0058542100001e000000fd00283c1e873c000a202020202020000000fc004c4720554c54524146494e450a000000ff0044454d4f31323334353637380a017b"

func bytes(_ hex: String) -> [UInt8] {
    var out: [UInt8] = []
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        out.append(UInt8(hex[index..<next], radix: 16)!)
        index = next
    }
    return out
}

@Test func parsesLGEDID() {
    #expect(EDIDInfo.parse(bytes(lgEDID)) == EDIDInfo(manufacturerID: "GSM", productCode: 23739, serialNumber: 1,
        week: 1, year: 2026, widthCm: 60, heightCm: 34, name: "LG ULTRAFINE", serialString: "DEMO12345678"))
}

@Test func rejectsBadEDID() {
    #expect(EDIDInfo.parse(Array(bytes(lgEDID).prefix(127))) == nil)
    var badSum = bytes(lgEDID); badSum[127] &+= 1
    #expect(EDIDInfo.parse(badSum) == nil)
    var badHeader = bytes(lgEDID); badHeader[0] = 0xFF
    #expect(EDIDInfo.parse(badHeader) == nil)
}
