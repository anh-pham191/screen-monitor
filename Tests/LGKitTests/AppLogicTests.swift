import Testing
import Foundation
@testable import LGKit

@Test func defaultInputValues() {
    let c = InputConfig()
    #expect([c.value(for: .mac), c.value(for: .ps5), c.value(for: .windows)] == [0x11, 0x12, 0x0F])
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
