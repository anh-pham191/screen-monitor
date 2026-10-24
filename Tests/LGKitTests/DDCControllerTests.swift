import Foundation
import Testing
@testable import LGKit

final class FakeTransport: I2CTransport {
    var queue: [[UInt8]?]
    var writes: [[UInt8]] = []
    var readCounts: [Int] = []
    var writeSucceeds = true

    init(reads: [[UInt8]?]) { queue = reads }

    func write(dataAddress: UInt32, bytes: [UInt8]) -> Bool {
        writes.append(bytes)
        return writeSucceeds
    }

    func read(dataAddress: UInt32, count: Int) -> [UInt8]? {
        readCounts.append(count)
        return queue.isEmpty ? nil : queue.removeFirst()
    }
}

@Suite struct DDCControllerTests {
    @Test func readSendsRequestWaitsAndParses() throws {
        let t = FakeTransport(reads: [[0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x1A, 0x00]])
        var sleeps: [useconds_t] = []
        let c = DDCController(transport: t, sleep: { sleeps.append($0) })
        #expect(try c.read(VCP.brightness) == VCPReading(current: 26, maximum: 100))
        #expect(t.writes == [DDCPacket.getRequest(0x10)])
        #expect(sleeps.first == 50_000)
        #expect(t.readCounts == [11])
    }

    @Test func readRetriesThenSucceeds() throws {
        let t = FakeTransport(reads: [nil, [UInt8](repeating: 0, count: 11), [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x05, 0x00]])
        #expect(try DDCController(transport: t, sleep: { _ in }).read(0x10).current == 5)
        #expect(t.writes.count == 3)
    }

    @Test func readGivesUpAfterThreeAttempts() {
        let t = FakeTransport(reads: [nil, nil, nil, nil])
        #expect(throws: DDCError.noReply(code: 0x10)) { try DDCController(transport: t, sleep: { _ in }).read(0x10) }
        #expect(t.writes.count == 3)
    }

    @Test func writeSendsPacketTwice() throws {
        let t = FakeTransport(reads: [])
        var sleeps: [useconds_t] = []
        try DDCController(transport: t, sleep: { sleeps.append($0) }).write(VCP.inputSource, value: 0x12)
        #expect(t.writes == [DDCPacket.setRequest(0x60, value: 0x12), DDCPacket.setRequest(0x60, value: 0x12)])
        #expect(sleeps.contains(20_000))
    }

    @Test func enforcesGapBetweenCommands() throws {
        let t = FakeTransport(reads: [[0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x1A, 0x00]])
        var sleeps: [useconds_t] = []
        let c = DDCController(transport: t, sleep: { sleeps.append($0) })   // sleeps are no-ops, so ~no real time passes
        try c.write(VCP.brightness, value: 30)
        let before = sleeps.count
        _ = try c.read(VCP.brightness)
        #expect(sleeps[before] > 40_000 && sleeps[before] <= 50_000)        // gap sleep comes before the get request
    }

    @Test func writeThrowsWhenBothAttemptsFail() {
        let t = FakeTransport(reads: []); t.writeSucceeds = false
        #expect(throws: DDCError.writeFailed(code: 0x60)) { try DDCController(transport: t, sleep: { _ in }).write(0x60, value: 0x12) }
    }

    @Test func capabilitiesConcatenatesChunksUntilEmpty() throws {
        let t = FakeTransport(reads: [
            [0x6E, 0x86, 0xE3, 0x00, 0x00, 0x28, 0x76, 0x63, 0x00],   // "(vc" at offset 0
            [0x6E, 0x85, 0xE3, 0x00, 0x03, 0x70, 0x29, 0x00],          // "p)" at offset 3
            [0x6E, 0x83, 0xE3, 0x00, 0x05, 0x00],                      // end
        ])
        #expect(try DDCController(transport: t, sleep: { _ in }).capabilities() == "(vcp)")
        #expect(t.writes == [DDCPacket.capabilitiesRequest(offset: 0), DDCPacket.capabilitiesRequest(offset: 3), DDCPacket.capabilitiesRequest(offset: 5)])
    }
}
