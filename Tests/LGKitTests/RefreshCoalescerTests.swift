import Testing
@testable import LGKit

@Test func startsARefreshWhenIdle() {
    var c = RefreshCoalescer()
    #expect(c.request() == true)
    #expect(c.isRunning)
}

@Test func aRequestDuringARefreshLeadsToExactlyOneRerun() {
    var c = RefreshCoalescer()
    _ = c.request()
    #expect(c.request() == false)
    #expect(c.finished() == true)
    // The rerun starts as a fresh request and, with nothing new pending, ends the chain.
    #expect(c.request() == true)
    #expect(c.finished() == false)
    #expect(!c.isRunning)
}

@Test func manyRequestsDuringARefreshStillLeadToOneRerun() {
    var c = RefreshCoalescer()
    _ = c.request()
    for _ in 0..<5 { #expect(c.request() == false) }
    #expect(c.finished() == true)
    #expect(c.request() == true)
    #expect(c.finished() == false)
}

@Test func noRerunWithoutARequestDuringTheRefresh() {
    var c = RefreshCoalescer()
    _ = c.request()
    #expect(c.finished() == false)
    #expect(!c.isRunning)
}
