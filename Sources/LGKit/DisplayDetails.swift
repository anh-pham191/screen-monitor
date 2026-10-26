import CoreGraphics
import Foundation
import IOKit

public struct DisplayDetails: Equatable, Sendable {
    public let edid: EDIDInfo?
    public let connection: String?
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let pointWidth: Int
    public let pointHeight: Int
    public let refreshHz: Double?

    public init(edid: EDIDInfo?, connection: String?, pixelWidth: Int, pixelHeight: Int,
                pointWidth: Int, pointHeight: Int, refreshHz: Double?) {
        self.edid = edid
        self.connection = connection
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.pointWidth = pointWidth
        self.pointHeight = pointHeight
        self.refreshHz = refreshHz
    }
}

public enum DisplayDetailsReader {
    /// Details of the screen the EDID belongs to. Nil without an EDID, or when no online display
    /// matches it (another screen's mode must never be shown under this screen's name).
    public static func read() -> DisplayDetails? {
        let (edid, connection) = readEDID()
        guard let edid else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return nil }
        let screens = ids.prefix(Int(count)).map {
            ScreenInfo(displayID: $0, isBuiltIn: CGDisplayIsBuiltin($0) != 0,
                       vendor: CGDisplayVendorNumber($0), model: CGDisplayModelNumber($0),
                       serial: CGDisplaySerialNumber($0))
        }
        guard let id = displayID(among: screens, matching: HardwareScreenID(edid: edid)) else { return nil }

        let bounds = CGDisplayBounds(id)
        let mode = CGDisplayCopyDisplayMode(id)
        // A refresh rate of 0 means "not reported" (common on HDMI/virtual modes), not 0 Hz.
        let hz = mode.map(\.refreshRate).flatMap { $0 > 0 ? $0 : nil }
        return DisplayDetails(
            edid: edid, connection: connection,
            pixelWidth: mode?.pixelWidth ?? Int(bounds.width),
            pixelHeight: mode?.pixelHeight ?? Int(bounds.height),
            pointWidth: Int(bounds.width), pointHeight: Int(bounds.height),
            refreshHz: hz)
    }

    /// The first non-built-in screen with the given vendor and model.
    static func displayID(among screens: [ScreenInfo], matching hardware: HardwareScreenID?) -> UInt32? {
        ScreenClassifier.classify(screens, hardware: hardware).first { $0.value == .hardware }?.key
    }

    /// The EDID lives in a `Metadata` dictionary on an IOService entry, not on the display node itself.
    private static func readEDID() -> (EDIDInfo?, String?) {
        var iterator: io_iterator_t = 0
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane,
                                       IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS
        else { return (nil, nil) }
        defer { IOObjectRelease(iterator) }

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let property = IORegistryEntryCreateCFProperty(entry, "Metadata" as CFString,
                                                                 kCFAllocatorDefault, 0)?.takeRetainedValue(),
                  let metadata = property as? [String: Any],
                  let data = metadata["EDID"] as? Data else { continue }
            return (EDIDInfo.parse([UInt8](data)), metadata["DFP Type Description"] as? String)
        }
        return (nil, nil)
    }
}
