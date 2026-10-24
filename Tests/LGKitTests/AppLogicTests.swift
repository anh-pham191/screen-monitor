import Testing
import Foundation
@testable import LGKit

@Test func defaultInputValues() {
    let c = InputConfig()
    #expect(c.command == .lg)
    #expect([c.value(for: .mac), c.value(for: .ps5), c.value(for: .windows)] == [0x90, 0x91, 0xD1])
    let s = InputConfig.defaults(for: .standard)
    #expect(s.command == .standard)
    #expect([s.value(for: .mac), s.value(for: .ps5), s.value(for: .windows)] == [0x11, 0x12, 0x0F])
    #expect(InputConfig.defaults(for: .lg) == c)
    #expect(Input.allCases.map(\.label) == ["Mac (HDMI 1)", "PS5 (HDMI 2)", "Windows (USB-C)"])
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
    var c = InputConfig(); c.set(0x1B, for: .windows)
    #expect(try JSONDecoder().decode(InputConfig.self, from: JSONEncoder().encode(c)) == c)
}
@Test func inputCommandWireValues() {
    #expect(InputCommand.allCases == [.lg, .standard])
    #expect(InputCommand.lg.vcp == 0xF4 && InputCommand.lg.dataAddress == 0x50)
    #expect(InputCommand.standard.vcp == 0x60 && InputCommand.standard.dataAddress == 0x51)
    #expect(InputCommand.allCases.map(\.label) == ["LG (recommended)", "Standard (VCP 0x60)"])
}
@Test func setCommandResetsValuesToThatCommandsDefaults() {
    var c = InputConfig(); c.set(0x1B, for: .windows)
    c.setCommand(.standard)
    #expect(c == InputConfig.defaults(for: .standard))
    c.set(0x13, for: .ps5)
    c.setCommand(.lg)
    #expect(c == InputConfig())
}
@Test func legacyInputConfigDecodesAsStandard() throws {
    // Configs saved before the LG command existed hold standard VCP 0x60 values.
    let c = try JSONDecoder().decode(InputConfig.self, from: Data(#"{"mac":17,"ps5":18,"windows":15}"#.utf8))
    #expect(c.command == .standard)
    #expect([c.mac, c.ps5, c.windows] == [17, 18, 15])
}
@Test func partialInputConfigFallsBackPerKey() throws {
    let lg = try JSONDecoder().decode(InputConfig.self, from: Data(#"{"command":"lg","ps5":146}"#.utf8))
    #expect(lg.command == .lg && [lg.mac, lg.ps5, lg.windows] == [0x90, 146, 0xD1])
    let std = try JSONDecoder().decode(InputConfig.self, from: Data(#"{"windows":27}"#.utf8))
    #expect(std.command == .standard && [std.mac, std.ps5, std.windows] == [0x11, 0x12, 27])
}
@Test func standardInputConfigRoundTripsJSON() throws {
    var c = InputConfig.defaults(for: .standard); c.set(0x1B, for: .windows)
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
@Test func movesOnlyWhenLeavingTheMacFromTheExternalScreen() {
    #expect(WindowPlacement.shouldMoveToBuiltIn(target: .ps5, windowOnExternal: true, builtInAvailable: true))
    #expect(WindowPlacement.shouldMoveToBuiltIn(target: .windows, windowOnExternal: true, builtInAvailable: true))
    #expect(!WindowPlacement.shouldMoveToBuiltIn(target: .mac, windowOnExternal: true, builtInAvailable: true))
    #expect(!WindowPlacement.shouldMoveToBuiltIn(target: .ps5, windowOnExternal: false, builtInAvailable: true))
}
@Test func noMoveWithoutBuiltInScreen() {
    #expect(!WindowPlacement.shouldMoveToBuiltIn(target: .ps5, windowOnExternal: true, builtInAvailable: false))
}
