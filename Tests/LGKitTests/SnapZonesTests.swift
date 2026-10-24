import CoreGraphics
import Testing
@testable import LGKit

@Test func halvesSplitVisibleFrame() {
    let f = CGRect(x: 1512, y: 0, width: 1921, height: 1055)
    #expect(SnapZones.halves(of: f) == [CGRect(x: 1512, y: 0, width: 960, height: 1055), CGRect(x: 2472, y: 0, width: 961, height: 1055)])
}

@Test func findsZoneUnderPointer() {
    let zones = SnapZones.halves(of: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    #expect(SnapZones.zoneIndex(at: CGPoint(x: 10, y: 500), in: zones) == 0)
    #expect(SnapZones.zoneIndex(at: CGPoint(x: 1900, y: 500), in: zones) == 1)
    #expect(SnapZones.zoneIndex(at: CGPoint(x: 3000, y: 500), in: zones) == nil)
}

@Test func convertsToAccessibilityCoordinates() {
    #expect(SnapZones.axRect(fromCocoa: CGRect(x: 0, y: 0, width: 960, height: 1055), primaryScreenHeight: 1080) == CGRect(x: 0, y: 25, width: 960, height: 1055))
    #expect(SnapZones.axPoint(fromCocoa: CGPoint(x: 100, y: 1000), primaryScreenHeight: 1080) == CGPoint(x: 100, y: 80))
}
