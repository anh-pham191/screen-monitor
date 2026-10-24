import Testing
@testable import LGKit

private final class Fake { let id: Int; init(_ id: Int) { self.id = id } }

@Test func reconnectingWriteSucceedsFirstTimeWithoutRediscovering() {
    var rediscovered = 0, writes: [Int] = []
    let r = ReconnectingWrite.run(current: Fake(1), rediscover: { rediscovered += 1; return Fake(2) },
                                  write: { writes.append($0.id) })
    #expect(r.succeeded)
    #expect(r.controller?.id == 1)
    #expect(writes == [1])
    #expect(rediscovered == 0)
}

@Test func reconnectingWriteRetriesOnceOnAFreshController() {
    var writes: [Int] = []
    let r = ReconnectingWrite.run(current: Fake(1), rediscover: { Fake(2) }, write: { c in
        writes.append(c.id)
        if c.id == 1 { throw DDCError.writeFailed(code: VCP.inputSource) }
    })
    #expect(r.succeeded)
    #expect(r.controller?.id == 2)
    #expect(writes == [1, 2])
}

@Test func reconnectingWriteFailsAfterOneRetry() {
    var writes: [Int] = []
    let r = ReconnectingWrite.run(current: Fake(1), rediscover: { Fake(2) }, write: { c in
        writes.append(c.id)
        throw DDCError.writeFailed(code: VCP.inputSource)
    })
    #expect(!r.succeeded)
    #expect(r.controller?.id == 2)
    #expect(writes == [1, 2])
}

@Test func reconnectingWriteDiscoversWhenThereIsNoController() {
    var writes: [Int] = []
    let r = ReconnectingWrite.run(current: nil, rediscover: { Fake(3) }, write: { writes.append($0.id) })
    #expect(r.succeeded)
    #expect(r.controller?.id == 3)
    #expect(writes == [3])
}

@Test func reconnectingWriteFailsWhenNoDisplayIsFound() {
    var writes: [Int] = []
    let r = ReconnectingWrite.run(current: Fake(1), rediscover: { nil as Fake? }, write: { c in
        writes.append(c.id)
        throw DDCError.writeFailed(code: VCP.inputSource)
    })
    #expect(!r.succeeded)
    #expect(r.controller == nil)
    #expect(writes == [1])
}
