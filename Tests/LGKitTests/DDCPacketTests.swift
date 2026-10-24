import Testing
@testable import LGKit

@Test func getRequestBrightness() { #expect(DDCPacket.getRequest(0x10) == [0x82, 0x01, 0x10, 0xAC]) }
@Test func setRequestHDMI2() { #expect(DDCPacket.setRequest(0x60, value: 0x12) == [0x84, 0x03, 0x60, 0x00, 0x12, 0xCA]) }
@Test func capabilitiesRequestOffset32() { #expect(DDCPacket.capabilitiesRequest(offset: 32) == [0x83, 0xF3, 0x00, 0x20, 0x6F]) }
@Test func parsesBrightnessReply() {
    let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x1A, 0x00]
    #expect(DDCPacket.parseGetReply(reply, code: 0x10) == VCPReading(current: 26, maximum: 100))
}
@Test func rejectsMismatchedReplies() {
    let ok: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x1A, 0x00]
    #expect(DDCPacket.parseGetReply(ok, code: 0x12) == nil)              // different VCP code
    var unsupported = ok; unsupported[3] = 0x01
    #expect(DDCPacket.parseGetReply(unsupported, code: 0x10) == nil)     // result byte says unsupported
    var wrongOpcode = ok; wrongOpcode[2] = 0x00
    #expect(DDCPacket.parseGetReply(wrongOpcode, code: 0x10) == nil)
    #expect(DDCPacket.parseGetReply(Array(ok.prefix(9)), code: 0x10) == nil)
    #expect(DDCPacket.parseGetReply([UInt8](repeating: 0, count: 11), code: 0x10) == nil)
}
@Test func parsesCapabilitiesChunk() {
    // [src, 0x80|len, 0xE3, offHi, offLo, data..., chk]; len counts opcode + offset + data
    let reply: [UInt8] = [0x6E, 0x86, 0xE3, 0x00, 0x20, 0x28, 0x70, 0x72, 0x00]
    #expect(DDCPacket.parseCapabilitiesReply(reply, offset: 32) == [0x28, 0x70, 0x72])
    #expect(DDCPacket.parseCapabilitiesReply(reply, offset: 0) == nil)   // offset mismatch
    #expect(DDCPacket.parseCapabilitiesReply([0x6E, 0x83, 0xE3, 0x00, 0x20, 0x00], offset: 32) == [])  // end marker
}
