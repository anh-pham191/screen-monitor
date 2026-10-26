import Testing
import Foundation
@testable import LGKit

// `lgEDID` (hex string) and `bytes(_:)` live in EDIDTests.swift (same test module).
private let lgInfo = EDIDInfo.parse(bytes(lgEDID))!
private let macScreen = ScreenInfo(displayID: 1, isBuiltIn: true, vendor: 0x610, model: 0xa04f, serial: 0)
private let lgScreen = ScreenInfo(displayID: 2, isBuiltIn: false, vendor: 0x1E6D, model: 0x5CBB, serial: 1)
private let phl1 = ScreenInfo(displayID: 9, isBuiltIn: false, vendor: 0x410C, model: 0xC171, serial: 11)
private let phl2 = ScreenInfo(displayID: 10, isBuiltIn: false, vendor: 0x410C, model: 0xC171, serial: 12)

@Test func vendorNumberPacksManufacturerID() {
    #expect(lgInfo.vendorNumber == 0x1E6D)   // "GSM"
}
@Test func vendorNumberIsZeroForMalformedIDs() {
    func info(_ id: String) -> EDIDInfo {
        EDIDInfo(manufacturerID: id, productCode: 1, serialNumber: 1, week: 1, year: 2020,
                 widthCm: 1, heightCm: 1, name: nil, serialString: nil)
    }
    #expect(info("").vendorNumber == 0)
    #expect(info("GS").vendorNumber == 0)
    #expect(info("GSMX").vendorNumber == 0)
    #expect(info("gsm").vendorNumber == 0)
    #expect(info("G5M").vendorNumber == 0)
}
@Test func classifierFindsHardwareByEDIDNotOrder() {
    let k = ScreenClassifier.classify([macScreen, phl1, lgScreen, phl2], hardwareEDID: lgInfo)
    #expect(k == [1: .builtIn, 9: .software, 2: .hardware, 10: .software])
}
@Test func classifierWithoutEDIDHasNoHardwareScreen() {
    let k = ScreenClassifier.classify([phl1, phl2], hardwareEDID: nil)
    #expect(k == [9: .software, 10: .software])
}
@Test func classifierWhenHardwareScreenAbsent() {
    #expect(ScreenClassifier.classify([phl1], hardwareEDID: lgInfo) == [9: .software])
}
@Test func classifierNeverMatchesAZeroVendor() {
    let bad = EDIDInfo(manufacturerID: "??", productCode: 0, serialNumber: 0, week: 1, year: 2020,
                       widthCm: 1, heightCm: 1, name: nil, serialString: nil)
    let zero = ScreenInfo(displayID: 5, isBuiltIn: false, vendor: 0, model: 0, serial: 0)
    #expect(ScreenClassifier.classify([zero], hardwareEDID: bad) == [5: .software])
}
@Test func classifierOnlyMarksTheFirstMatchAsHardware() {
    let twin = ScreenInfo(displayID: 3, isBuiltIn: false, vendor: 0x1E6D, model: 0x5CBB, serial: 2)
    #expect(ScreenClassifier.classify([lgScreen, twin], hardwareEDID: lgInfo) == [2: .hardware, 3: .software])
}
@Test func identicalScreensGetDistinctKeys() {
    #expect(ScreenKey.key(for: phl1, among: [phl1, phl2]) == "410c-c171-11")
    let a = ScreenInfo(displayID: 9, isBuiltIn: false, vendor: 0x410C, model: 0xC171, serial: 0)
    let b = ScreenInfo(displayID: 10, isBuiltIn: false, vendor: 0x410C, model: 0xC171, serial: 0)
    #expect(ScreenKey.key(for: a, among: [macScreen, a, b]) == "410c-c171-0#0")
    #expect(ScreenKey.key(for: b, among: [macScreen, a, b]) == "410c-c171-0#1")
}
@Test func dimmingCurve() {
    #expect(SoftwareDimming.opacity(level: 100) == 0)
    #expect(abs(SoftwareDimming.opacity(level: 50) - 0.45) < 1e-9)
    #expect(SoftwareDimming.opacity(level: 150) == 0)
}
@Test func dimmingNeverFullyBlack() {
    #expect(abs(SoftwareDimming.opacity(level: 0) - 0.9) < 1e-9)
    #expect(SoftwareDimming.opacity(level: -20) < 1)
}
@Test func softwareLevelsDefaultAndClamp() throws {
    var s = SoftwareLevels()
    #expect(s.level(for: "x") == 100)
    s.set(-5, for: "x"); #expect(s.level(for: "x") == 0)
    s.set(40, for: "y")
    #expect(try JSONDecoder().decode(SoftwareLevels.self, from: JSONEncoder().encode(s)) == s)
}
@Test func softwareRouteIgnoresHardwareConnection() {
    #expect(KeyRouter.route(.brightnessUp, pointerScreen: .software, hardwareIsSoundOutput: false, hardwareConnected: false) == .software)
    #expect(KeyRouter.route(.brightnessDown, pointerScreen: .hardware, hardwareIsSoundOutput: false, hardwareConnected: true) == .hardware)
    #expect(KeyRouter.route(.brightnessDown, pointerScreen: .hardware, hardwareIsSoundOutput: false, hardwareConnected: false) == .passThrough)
    #expect(KeyRouter.route(.brightnessUp, pointerScreen: .builtIn, hardwareIsSoundOutput: true, hardwareConnected: true) == .passThrough)
    #expect(KeyRouter.route(.brightnessUp, pointerScreen: nil, hardwareIsSoundOutput: true, hardwareConnected: true) == .passThrough)
    #expect(KeyRouter.route(.volumeUp, pointerScreen: .software, hardwareIsSoundOutput: true, hardwareConnected: true) == .hardware)
    #expect(KeyRouter.route(.mute, pointerScreen: .hardware, hardwareIsSoundOutput: false, hardwareConnected: true) == .passThrough)
}

@Test func destinationPrefersBuiltIn() {
    #expect(WindowPlacement.destination(kinds: [.hardware, .software, .builtIn]) == 2)
}
@Test func destinationFallsBackToSoftwareScreen() {
    #expect(WindowPlacement.destination(kinds: [.hardware, .software, .software]) == 1)
}
@Test func destinationNoneWhenOnlyHardware() {
    #expect(WindowPlacement.destination(kinds: [.hardware]) == nil)
    #expect(WindowPlacement.destination(kinds: []) == nil)
}
@Test func hardwareScreenIDFromEDID() throws {
    #expect(HardwareScreenID(edid: lgInfo) == HardwareScreenID(vendor: 0x1E6D, model: 0x5CBB))
    let bad = EDIDInfo(manufacturerID: "??", productCode: 7, serialNumber: 0, week: 1, year: 2020,
                       widthCm: 1, heightCm: 1, name: nil, serialString: nil)
    #expect(HardwareScreenID(edid: bad) == nil)
    let id = HardwareScreenID(vendor: 0x1E6D, model: 0x5CBB)
    #expect(try JSONDecoder().decode(HardwareScreenID.self, from: JSONEncoder().encode(id)) == id)
}
@Test func classifierAcceptsARememberedHardwareID() {
    let id = HardwareScreenID(vendor: 0x1E6D, model: 0x5CBB)
    #expect(ScreenClassifier.classify([macScreen, phl1, lgScreen], hardware: id) == [1: .builtIn, 9: .software, 2: .hardware])
    #expect(ScreenClassifier.classify([phl1], hardware: nil) == [9: .software])
    #expect(ScreenClassifier.classify([phl1], hardware: HardwareScreenID(vendor: 0, model: 0xC171)) == [9: .software])
}
@Test func softwareLevelsForget() {
    var s = SoftwareLevels()
    s.set(30, for: "x")
    let first = s.forget("x")
    #expect(first)
    #expect(s.level(for: "x") == 100)
    let second = s.forget("x")
    #expect(!second)
}

// MARK: Warmth

@Test func warmthZeroIsNeutral() {
    let m = ColorTemperature.multipliers(warmth: 0)
    #expect(m.red == 1 && m.green == 1 && m.blue == 1)
    #expect(ColorTemperature.kelvin(warmth: 0) == 6500 && ColorTemperature.kelvin(warmth: 100) == 2700)
}
@Test func fullWarmthMatchesNightShiftWarmEnd() {
    let m = ColorTemperature.multipliers(warmth: 100)
    #expect(m.red == 1)
    #expect(m.green > 0.6 && m.green < 0.72)
    #expect(m.blue > 0.3 && m.blue < 0.42)
}
@Test func warmerMeansLessBlue() {
    let b = stride(from: 0, through: 100, by: 10).map { ColorTemperature.multipliers(warmth: $0).blue }
    #expect(zip(b, b.dropFirst()).allSatisfy { $0 >= $1 })
}
@Test func warmthClampsOutOfRange() {
    let high = ColorTemperature.multipliers(warmth: 150), full = ColorTemperature.multipliers(warmth: 100)
    #expect(high.red == full.red && high.green == full.green && high.blue == full.blue)
    let low = ColorTemperature.multipliers(warmth: -5), none = ColorTemperature.multipliers(warmth: 0)
    #expect(low.red == none.red && low.green == none.green && low.blue == none.blue)
}
@Test func scaledTable() {
    #expect(ColorTemperature.scaled([0, 0.5, 1], by: 0.4) == [0, 0.2, 0.4])
}
@Test func warmthDefaultsAndOldJSONDecodes() throws {
    var s = SoftwareLevels(); s.set(40, for: "a")
    #expect(s.warmth(for: "a") == 0)
    s.setWarmth(150, for: "a"); #expect(s.warmth(for: "a") == 100)
    #expect(try JSONDecoder().decode(SoftwareLevels.self, from: JSONEncoder().encode(s)) == s)
}
@Test func jsonSavedBeforeWarmthDecodesWithZeroWarmth() throws {
    let old = Data(#"{"levels":{"a":40,"b":75}}"#.utf8)
    let s = try JSONDecoder().decode(SoftwareLevels.self, from: old)
    #expect(s.level(for: "a") == 40 && s.level(for: "b") == 75)
    #expect(s.warmth(for: "a") == 0 && s.warmth(for: "b") == 0)
}
