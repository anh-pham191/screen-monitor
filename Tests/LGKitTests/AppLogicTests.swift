import Testing
import Foundation
@testable import LGKit

@Test func defaultInputValues() {
    let c = InputConfig()
    #expect(c.command == .lg)
    #expect([c.value(for: .hdmi1), c.value(for: .hdmi2), c.value(for: .usbC)] == [0x90, 0x91, 0xD1])
    let s = InputConfig.defaults(for: .standard)
    #expect(s.command == .standard)
    #expect([s.value(for: .hdmi1), s.value(for: .hdmi2), s.value(for: .usbC)] == [0x11, 0x12, 0x0F])
    #expect(InputConfig.defaults(for: .lg) == c)
    #expect(Input.allCases.map(\.label) == ["HDMI 1", "HDMI 2", "USB-C"])
}
@Test func parseHexAcceptsCommonForms() {
    #expect(InputConfig.parseHex("1B") == 0x1B)
    #expect(InputConfig.parseHex(" 0x0f ") == 0x0F)
    #expect(InputConfig.parseHex("0XD1") == 0xD1)
    #expect(InputConfig.formatHex(0x1B) == "0x1B")
}
@Test func parseHexRejectsBadInput() {
    for bad in ["", "  ", "zz", "0x", "10000", "-1", "1 2"] { #expect(InputConfig.parseHex(bad) == nil, "\(bad)") }
}
@Test func inputConfigRoundTripsJSON() throws {
    var c = InputConfig(); c.set(0x1B, for: .usbC)
    #expect(try JSONDecoder().decode(InputConfig.self, from: JSONEncoder().encode(c)) == c)
}
@Test func inputCommandWireValues() {
    #expect(InputCommand.allCases == [.lg, .standard])
    #expect(InputCommand.lg.vcp == 0xF4 && InputCommand.lg.dataAddress == 0x50)
    #expect(InputCommand.standard.vcp == 0x60 && InputCommand.standard.dataAddress == 0x51)
    #expect(InputCommand.allCases.map(\.label) == ["LG monitors (VCP 0xF4)", "Standard (VCP 0x60)"])
}
@Test func setCommandResetsValuesToThatCommandsDefaults() {
    var c = InputConfig(); c.set(0x1B, for: .usbC)
    c.setCommand(.standard)
    #expect(c == InputConfig.defaults(for: .standard))
    c.set(0x13, for: .hdmi2)
    c.setCommand(.lg)
    #expect(c == InputConfig())
}
@Test func legacyInputConfigDecodesAsStandard() throws {
    // Configs saved before the LG command existed hold standard VCP 0x60 values.
    let c = try JSONDecoder().decode(InputConfig.self, from: Data(#"{"mac":17,"ps5":18,"windows":15}"#.utf8))
    #expect(c.command == .standard)
    #expect([c.hdmi1, c.hdmi2, c.usbC] == [17, 18, 15])
}
@Test func partialInputConfigFallsBackPerKey() throws {
    let lg = try JSONDecoder().decode(InputConfig.self, from: Data(#"{"command":"lg","hdmi2":146}"#.utf8))
    #expect(lg.command == .lg && [lg.hdmi1, lg.hdmi2, lg.usbC] == [0x90, 146, 0xD1])
    let std = try JSONDecoder().decode(InputConfig.self, from: Data(#"{"usbC":27}"#.utf8))
    #expect(std.command == .standard && [std.hdmi1, std.hdmi2, std.usbC] == [0x11, 0x12, 27])
}
@Test func standardInputConfigRoundTripsJSON() throws {
    var c = InputConfig.defaults(for: .standard); c.set(0x1B, for: .usbC)
    #expect(try JSONDecoder().decode(InputConfig.self, from: JSONEncoder().encode(c)) == c)
}
@Test func coalescesRapidSubmits() {
    let queue = DispatchQueue(label: "test.ddc")
    let lock = NSLock(); var written: [Int] = []
    let w = LatestValueWriter<Int>(queue: queue, interval: 0.1) { v in lock.lock(); written.append(v); lock.unlock() }
    for v in 1...10 { w.submit(v) }
    Thread.sleep(forTimeInterval: 0.4)   // synchronous on purpose: NSLock is unavailable in async contexts
    lock.lock(); defer { lock.unlock() }
    #expect(written.first == 1)
    #expect(written.last == 10)
    #expect(written.count <= 3)
}
@Test func moveOffOnlyWhenLeavingTheMacsPort() {
    #expect(WindowPlacement.shouldMoveOff(target: .hdmi2, macPort: .hdmi1, destinationAvailable: true))
    #expect(!WindowPlacement.shouldMoveOff(target: .hdmi1, macPort: .hdmi1, destinationAvailable: true))
    #expect(WindowPlacement.shouldMoveOff(target: .hdmi1, macPort: .usbC, destinationAvailable: true))
    #expect(!WindowPlacement.shouldMoveOff(target: .hdmi2, macPort: .hdmi1, destinationAvailable: false))
}
@Test func portLabels() {
    #expect(Input.allCases == [.hdmi1, .hdmi2, .usbC])
    #expect(Input.allCases.map(\.label) == ["HDMI 1", "HDMI 2", "USB-C"])
}
@Test func legacyDeviceKeysMigrateToPorts() throws {
    let c = try JSONDecoder().decode(InputConfig.self,
        from: Data(#"{"command":"lg","mac":144,"ps5":145,"windows":209}"#.utf8))
    #expect(c.command == .lg && c.hdmi1 == 0x90 && c.hdmi2 == 0x91 && c.usbC == 0xD1)
}
@Test func newKeysWinOverLegacyKeys() throws {
    let c = try JSONDecoder().decode(InputConfig.self,
        from: Data(#"{"command":"standard","hdmi1":1,"mac":2}"#.utf8))
    #expect(c.hdmi1 == 1)
}
@Test func encodesPortKeys() throws {
    let json = String(decoding: try JSONEncoder().encode(InputConfig()), as: UTF8.self)
    #expect(json.contains("\"hdmi1\"") && !json.contains("\"mac\""))
}
@Test func automaticCommandByMaker() {
    #expect(InputCommand.automatic(manufacturerID: "GSM") == .lg)
    #expect(InputCommand.automatic(manufacturerID: "PHL") == .standard)
    #expect(InputCommand.automatic(manufacturerID: nil) == .standard)
}
