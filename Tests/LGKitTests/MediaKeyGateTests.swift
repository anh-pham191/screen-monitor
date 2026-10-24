import Testing
@testable import LGKit

private let plain = (handle: true, fine: false)
private let optionShift = (handle: true, fine: true)
private let blocked = (handle: false, fine: false)

private func down(_ key: MediaKey, repeat rep: Bool = false) -> MediaKeyEvent { MediaKeyEvent(key: key, isDown: true, isRepeat: rep) }
private func up(_ key: MediaKey) -> MediaKeyEvent { MediaKeyEvent(key: key, isDown: false, isRepeat: false) }

@Test func handlesAPressRoutedToTheLGAndSwallowsItsKeyUp() {
    var gate = MediaKeyGate()
    #expect(gate.decide(down(.brightnessUp), modifiers: plain, canHandle: true, route: { .lg }) == .handle(fine: false))
    #expect(gate.decide(up(.brightnessUp), modifiers: plain, canHandle: true, route: { .lg }) == .swallow)
}

@Test func swallowsTheKeyUpEvenAfterThePointerMoved() {
    var gate = MediaKeyGate()
    _ = gate.decide(down(.brightnessDown), modifiers: plain, canHandle: true, route: { .lg })
    #expect(gate.decide(up(.brightnessDown), modifiers: plain, canHandle: true, route: { .passThrough }) == .swallow)
    // The press is over, so the next key-up for that key is not ours.
    #expect(gate.decide(up(.brightnessDown), modifiers: plain, canHandle: true, route: { .lg }) == .passThrough)
}

@Test func passesThroughWhenRoutedAwayAndLeavesItsKeyUpAlone() {
    var gate = MediaKeyGate()
    #expect(gate.decide(down(.volumeUp), modifiers: plain, canHandle: true, route: { .passThrough }) == .passThrough)
    #expect(gate.decide(up(.volumeUp), modifiers: plain, canHandle: true, route: { .lg }) == .passThrough)
}

@Test func passesThroughWithOtherModifiers() {
    var gate = MediaKeyGate()
    #expect(gate.decide(down(.brightnessUp), modifiers: blocked, canHandle: true, route: { .lg }) == .passThrough)
    #expect(gate.decide(up(.brightnessUp), modifiers: blocked, canHandle: true, route: { .lg }) == .passThrough)
}

@Test func optionShiftGivesFineSteps() {
    var gate = MediaKeyGate()
    #expect(gate.decide(down(.volumeDown), modifiers: optionShift, canHandle: true, route: { .lg }) == .handle(fine: true))
}

@Test func passesThroughWhenTheMaximumIsUnknown() {
    var gate = MediaKeyGate()
    #expect(gate.decide(down(.brightnessUp), modifiers: plain, canHandle: false, route: { .lg }) == .passThrough)
    #expect(gate.decide(up(.brightnessUp), modifiers: plain, canHandle: false, route: { .lg }) == .passThrough)
}

@Test func repeatsFollowTheOwnerOfThePress() {
    var gate = MediaKeyGate()
    _ = gate.decide(down(.brightnessUp), modifiers: plain, canHandle: true, route: { .lg })
    // The pointer moving mid-hold doesn't split one press between two displays.
    #expect(gate.decide(down(.brightnessUp, repeat: true), modifiers: plain, canHandle: true, route: { .passThrough }) == .handle(fine: false))
    // A modifier change mid-hold stops the stepping but the press stays ours.
    #expect(gate.decide(down(.brightnessUp, repeat: true), modifiers: blocked, canHandle: true, route: { .lg }) == .swallow)
    // A repeat for a press we never saw belongs to macOS.
    #expect(gate.decide(down(.volumeUp, repeat: true), modifiers: plain, canHandle: true, route: { .lg }) == .passThrough)
}

@Test func doesNotAskForTheRouteOnKeyUpsOrRepeats() {
    var gate = MediaKeyGate()
    var asked = 0
    _ = gate.decide(down(.mute), modifiers: plain, canHandle: true, route: { asked += 1; return .lg })
    _ = gate.decide(down(.mute, repeat: true), modifiers: plain, canHandle: true, route: { asked += 1; return .lg })
    _ = gate.decide(up(.mute), modifiers: plain, canHandle: true, route: { asked += 1; return .lg })
    #expect(asked == 1)
}

@Test func aFreshPressReplacesAStaleOne() {
    var gate = MediaKeyGate()
    _ = gate.decide(down(.brightnessUp), modifiers: plain, canHandle: true, route: { .lg })
    // The key-up was lost (for example the tap was briefly disabled); the next press goes to macOS.
    #expect(gate.decide(down(.brightnessUp), modifiers: plain, canHandle: true, route: { .passThrough }) == .passThrough)
    #expect(gate.decide(up(.brightnessUp), modifiers: plain, canHandle: true, route: { .lg }) == .passThrough)
}

@Test func tracksKeysIndependently() {
    var gate = MediaKeyGate()
    _ = gate.decide(down(.brightnessUp), modifiers: plain, canHandle: true, route: { .lg })
    #expect(gate.decide(up(.volumeUp), modifiers: plain, canHandle: true, route: { .lg }) == .passThrough)
    #expect(gate.decide(up(.brightnessUp), modifiers: plain, canHandle: true, route: { .lg }) == .swallow)
}

@Test func roundsSliderValuesIntoTheDDCRange() {
    #expect(Stepper.wireValue(26.4) == 26)
    #expect(Stepper.wireValue(26.5) == 27)
    #expect(Stepper.wireValue(-3) == 0)
    #expect(Stepper.wireValue(70_000) == UInt16.max)
    #expect(Stepper.wireValue(.nan) == 0)
}

@Test func fillsHUDSegmentsIncludingPartialOnes() {
    #expect(HUDLevel.segmentFills(level: 0, count: 16) == Array(repeating: 0, count: 16))
    #expect(HUDLevel.segmentFills(level: 1, count: 16) == Array(repeating: 1, count: 16))
    let quarter = HUDLevel.segmentFills(level: 0.25 + 0.25 / 16, count: 16)
    #expect(quarter.prefix(4) == [1, 1, 1, 1])
    #expect(abs(quarter[4] - 0.25) < 1e-9)
    #expect(quarter.dropFirst(5).allSatisfy { $0 == 0 })
    #expect(HUDLevel.segmentFills(level: 1.5, count: 4) == [1, 1, 1, 1])
    #expect(HUDLevel.segmentFills(level: -1, count: 4) == [0, 0, 0, 0])
}

@Test func levelIsAFractionOfTheMaximum() {
    #expect(HUDLevel.fraction(50, maximum: 100) == 0.5)
    #expect(HUDLevel.fraction(5, maximum: 0) == 0)
}

@Test func holdingMuteTogglesItOnlyOnce() {
    var gate = MediaKeyGate()
    #expect(gate.decide(down(.mute), modifiers: plain, canHandle: true, route: { .lg }) == .handle(fine: false))
    // Mute is a toggle: acting on every repeat would flicker it on and off while held.
    #expect(gate.decide(down(.mute, repeat: true), modifiers: plain, canHandle: true, route: { .lg }) == .swallow)
    #expect(gate.decide(down(.mute, repeat: true), modifiers: plain, canHandle: true, route: { .lg }) == .swallow)
    #expect(gate.decide(up(.mute), modifiers: plain, canHandle: true, route: { .lg }) == .swallow)
}
