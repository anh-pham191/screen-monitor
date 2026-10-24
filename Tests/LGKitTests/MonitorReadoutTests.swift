import Testing
import Foundation
@testable import LGKit

private func fakeReads(_ values: [UInt8: VCPReading], log: Box<[UInt8]> = Box([])) -> (UInt8) throws -> VCPReading {
    { code in
        log.value.append(code)
        guard let v = values[code] else { throw DDCError.noReply(code: code) }
        return v
    }
}

final class Box<T> { var value: T; init(_ value: T) { self.value = value } }

private let full: [UInt8: VCPReading] = [
    0x10: VCPReading(current: 26, maximum: 100),
    0x12: VCPReading(current: 70, maximum: 100),
    0x62: VCPReading(current: 12, maximum: 100),
    0x8D: VCPReading(current: 2, maximum: 2),
    0x60: VCPReading(current: 0, maximum: 18),
]

@Test func readoutCompleteWhenAllRequiredCodesAnswer() {
    let r = MonitorReadout.read(fakeReads(full))
    #expect(r.isComplete)
    #expect(r.raw == full)
    #expect(r.raw[VCP.brightness]?.current == 26)
    #expect(r.muted == false)
}

@Test func muteValueOneMeansMuted() {
    var values = full
    values[0x8D] = VCPReading(current: 1, maximum: 2)
    #expect(MonitorReadout.read(fakeReads(values)).muted == true)
}

@Test func inputReadFailureIsIgnored() {
    var values = full
    values[0x60] = nil
    let r = MonitorReadout.read(fakeReads(values))
    #expect(r.isComplete)
    #expect(r.raw[0x60] == nil)
    #expect(r.raw.count == 4)
}

@Test func requiredFailureMakesReadoutIncompleteAndStopsReading() {
    var values = full
    values[0x12] = nil
    let log = Box<[UInt8]>([])
    let r = MonitorReadout.read(fakeReads(values, log: log))
    #expect(!r.isComplete)
    #expect(r.muted == nil)
    // A silent LG costs several retries per code, so give up at the first required miss.
    #expect(log.value == [0x10, 0x12])
    #expect(r.raw == [0x10: VCPReading(current: 26, maximum: 100)])
}

@Test func formatsReadingsForDetails() {
    #expect(DetailsFormat.reading(VCPReading(current: 26, maximum: 100)) == "26 / 100")
    #expect(DetailsFormat.reading(nil) == "—")
    #expect(DetailsFormat.hexList([0x11, 0x12, 0x0F, 0x00]) == "0x11 0x12 0x0F 0x00")
}

private let lgDetails = DisplayDetails(edid: nil, connection: "HDMI", pixelWidth: 3840, pixelHeight: 2160,
                                       pointWidth: 1920, pointHeight: 1080, refreshHz: 59.94)

@Test func headerSubtitleJoinsConnectionResolutionAndRefresh() {
    #expect(DetailsFormat.headerSubtitle(lgDetails) == "HDMI · 3840 × 2160 · 60 Hz")
    let bare = DisplayDetails(edid: nil, connection: nil, pixelWidth: 2560, pixelHeight: 1440,
                              pointWidth: 2560, pointHeight: 1440, refreshHz: nil)
    #expect(DetailsFormat.headerSubtitle(bare) == "2560 × 1440")
}

@Test func formatsResolutionAndRefresh() {
    #expect(DetailsFormat.resolution(lgDetails) == "3840 × 2160 px, looks like 1920 × 1080")
    #expect(DetailsFormat.refresh(lgDetails) == "60 Hz")
    #expect(DetailsFormat.refresh(DisplayDetails(edid: nil, connection: nil, pixelWidth: 1, pixelHeight: 1,
                                                 pointWidth: 1, pointHeight: 1, refreshHz: nil)) == "—")
}

@Test func storedInputConfigFallsBackToDefaults() throws {
    var custom = InputConfig(); custom.set(0x1B, for: .windows)
    #expect(InputConfig.decodeOrDefault(try JSONEncoder().encode(custom)) == custom)
    #expect(InputConfig.decodeOrDefault(nil) == InputConfig())
    // An older blob (no command) holds standard values; any missing key takes the standard default.
    var legacy = InputConfig.defaults(for: .standard); legacy.set(17, for: .mac)
    #expect(InputConfig.decodeOrDefault(Data(#"{"mac":17}"#.utf8)) == legacy)
    #expect(InputConfig.decodeOrDefault(Data("garbage".utf8)) == InputConfig())
}
