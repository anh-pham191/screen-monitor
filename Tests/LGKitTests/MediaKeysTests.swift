import Testing
import Foundation
@testable import LGKit

// NX_SYSDEFINED media keys: subtype 8; keyCode = (data1 & 0xFFFF0000) >> 16; state = (data1 & 0xFF00) >> 8 (0x0A down, 0x0B up); repeat = data1 & 0x1
func data1(_ code: Int, down: Bool, rep: Bool = false) -> Int { (code << 16) | ((down ? 0x0A : 0x0B) << 8) | (rep ? 1 : 0) }

@Test func decodesMediaKeys() {
    #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(2, down: true)) == MediaKeyEvent(key: .brightnessUp, isDown: true, isRepeat: false))
    #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(3, down: false))?.key == .brightnessDown)
    #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(0, down: true, rep: true)) == MediaKeyEvent(key: .volumeUp, isDown: true, isRepeat: true))
    #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(1, down: true))?.key == .volumeDown)
    #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(7, down: true))?.key == .mute)
}
@Test func decodesBrightnessKeyCodes() {
    #expect(MediaKeyEvent.decode(keyCode: 144, isDown: true, isRepeat: false) == MediaKeyEvent(key: .brightnessUp, isDown: true, isRepeat: false))
    #expect(MediaKeyEvent.decode(keyCode: 145, isDown: false, isRepeat: false)?.key == .brightnessDown)
    #expect(MediaKeyEvent.decode(keyCode: 0, isDown: true, isRepeat: false) == nil)
    #expect(MediaKeyEvent.decode(keyCode: 122, isDown: true, isRepeat: false) == nil)
}
@Test func ignoresOtherSystemEvents() {
    #expect(MediaKeyEvent.decode(subtype: 7, data1: data1(2, down: true)) == nil)
    #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(16, down: true)) == nil)
}
@Test func routesKeysByPointerAndSoundOutput() {
    #expect(KeyRouter.route(.brightnessUp, pointerScreen: .hardware, hardwareIsSoundOutput: false, hardwareConnected: true) == .hardware)
    #expect(KeyRouter.route(.brightnessUp, pointerScreen: nil, hardwareIsSoundOutput: true, hardwareConnected: true) == .passThrough)
    #expect(KeyRouter.route(.volumeUp, pointerScreen: nil, hardwareIsSoundOutput: true, hardwareConnected: true) == .hardware)
    #expect(KeyRouter.route(.mute, pointerScreen: .hardware, hardwareIsSoundOutput: false, hardwareConnected: true) == .passThrough)
    #expect(KeyRouter.route(.brightnessUp, pointerScreen: .hardware, hardwareIsSoundOutput: true, hardwareConnected: false) == .passThrough)
    #expect(KeyRouter.route(.volumeDown, pointerScreen: .hardware, hardwareIsSoundOutput: true, hardwareConnected: false) == .passThrough)
}
@Test func stepsLikeMacOS() {
    #expect(Stepper.step(current: 26, maximum: 100, up: true, fine: false) == 31)
    #expect(Stepper.step(current: 25, maximum: 100, up: true, fine: false) == 31)
    #expect(Stepper.step(current: 26, maximum: 100, up: false, fine: false) == 25)
    #expect(Stepper.step(current: 98, maximum: 100, up: true, fine: false) == 100)
    #expect(Stepper.step(current: 0, maximum: 100, up: false, fine: false) == 0)
    #expect(Stepper.step(current: 26, maximum: 100, up: true, fine: true) == 27)
    #expect(Stepper.step(current: 0, maximum: 0, up: true, fine: false) == 0)
    #expect(Stepper.step(current: 31, maximum: 100, up: true, fine: false) == 38)
    #expect(Stepper.step(current: 38, maximum: 100, up: false, fine: false) == 31)
    var v: UInt16 = 0; for _ in 0..<16 { v = Stepper.step(current: v, maximum: 100, up: true, fine: false) }
    #expect(v == 100)
}
@Test func modifiersAllowHandlingMatchesNormalMac() {
    #expect(KeyRouter.modifiersAllowHandling(option: false, shift: false, control: false, command: false) == (handle: true, fine: false))
    #expect(KeyRouter.modifiersAllowHandling(option: true, shift: true, control: false, command: false) == (handle: true, fine: true))
    for bits in 0..<16 where bits != 0 && bits != 0b0011 {
        let r = KeyRouter.modifiersAllowHandling(option: bits & 1 != 0, shift: bits & 2 != 0, control: bits & 4 != 0, command: bits & 8 != 0)
        #expect(r.handle == false, "bits \(bits)")
    }
    #expect(KeyRouter.modifiersAllowHandling(option: true, shift: false, control: false, command: false).handle == false)
}
