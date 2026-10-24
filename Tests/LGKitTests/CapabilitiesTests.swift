import Testing
@testable import LGKit

@Test func parsesCapabilitiesString() {
    let caps = Capabilities.parse("(prot(monitor)type(LCD)model(ULTRAFINE)cmds(01 02 03 0C E3 F3)vcp(02 10 12 14(05 08 0B) 60(11 12 0F 1B) 62 8D(01 02) D6(01 04))mccs_ver(2.1))")
    #expect(caps.model == "ULTRAFINE")
    #expect(caps.mccsVersion == "2.1")
    #expect(caps.vcp[0x60] == [0x11, 0x12, 0x0F, 0x1B])
    #expect(caps.vcp[0x10] == [])
    #expect(caps.vcp.count == 8)
}

@Test func capabilitiesToleratesGarbage() {
    #expect(Capabilities.parse("") == Capabilities(model: nil, mccsVersion: nil, vcp: [:]))
    #expect(Capabilities.parse("(vcp(10 12").vcp.isEmpty == false)
}
