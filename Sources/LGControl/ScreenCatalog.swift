import AppKit
import CoreGraphics
import LGKit

/// Which screen is which: the MacBook's, the one with hardware (DDC) control, and every other
/// external screen, whose brightness is done in software.
///
/// The hardware screen is the external screen whose CoreGraphics vendor and model match the EDID
/// read over DDC, never just "the first external screen": a DisplayLink screen can come first.
@MainActor
enum ScreenCatalog {
    private static let defaultsKey = "hardwareScreenID"
    private static var defaults: UserDefaults?

    /// Set by `MonitorModel` from each refresh's EDID. Sticky: only a different screen replaces it,
    /// so DDC going quiet (the screen showing another input) doesn't turn the hardware screen into
    /// a software one. Remembered across launches, so the hardware screen is known before the first
    /// refresh and never gets a software overlay meanwhile.
    private(set) static var hardwareID: HardwareScreenID?

    /// Call before anything asks which screen is which (before `SoftwareBrightness` is built).
    static func load(from defaults: UserDefaults) {
        self.defaults = defaults
        hardwareID = defaults.data(forKey: defaultsKey)
            .flatMap { try? JSONDecoder().decode(HardwareScreenID.self, from: $0) }
    }

    /// Returns whether the hardware screen changed: an EDID matching the remembered one is no change.
    @discardableResult
    static func update(hardwareEDID edid: EDIDInfo?) -> Bool {
        guard let id = edid.flatMap(HardwareScreenID.init(edid:)), id != hardwareID else { return false }
        hardwareID = id
        defaults?.set(try? JSONEncoder().encode(id), forKey: defaultsKey)
        return true
    }

    /// Screens in `NSScreen.screens` order. One without a display number can't be identified, so it's left out.
    static func infos() -> [(ScreenInfo, NSScreen)] {
        NSScreen.screens.compactMap { screen in
            guard let id = displayID(of: screen) else { return nil }
            let info = ScreenInfo(displayID: id, isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                                  vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                                  serial: CGDisplaySerialNumber(id))
            return (info, screen)
        }
    }

    static func kind(of screen: NSScreen) -> ScreenKind? {
        guard let id = displayID(of: screen) else { return nil }
        return kinds()[id]
    }

    static func hardwareScreen() -> NSScreen? {
        let all = infos()
        let kinds = kinds(of: all)
        return all.first { kinds[$0.0.displayID] == .hardware }?.1
    }

    /// The level key the hardware screen would have as a software screen, so a level stored
    /// before it was recognised can be dropped.
    static func hardwareScreenKey() -> String? {
        let all = infos()
        let kinds = kinds(of: all)
        guard let info = all.first(where: { kinds[$0.0.displayID] == .hardware })?.0 else { return nil }
        return ScreenKey.key(for: info, among: all.map(\.0))
    }

    /// Every external screen without hardware control, keyed for remembering its level.
    static func softwareScreens() -> [(key: String, name: String, screen: NSScreen)] {
        let all = infos()
        let kinds = kinds(of: all)
        let screens = all.map(\.0)
        return all.compactMap { info, screen in
            guard kinds[info.displayID] == .software else { return nil }
            return (ScreenKey.key(for: info, among: screens), screen.localizedName, screen)
        }
    }

    /// Where windows go when the hardware screen leaves the Mac's port; nil when nowhere.
    static func windowDestination() -> NSScreen? {
        let all = infos()
        let kinds = kinds(of: all)
        // classify gives every listed screen a kind; the fallback is never used.
        guard let index = WindowPlacement.destination(kinds: all.map { kinds[$0.0.displayID] ?? .software }) else { return nil }
        return all[index].1
    }

    static func screenUnderPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
    }

    private static func kinds() -> [UInt32: ScreenKind] { kinds(of: infos()) }

    private static func kinds(of all: [(ScreenInfo, NSScreen)]) -> [UInt32: ScreenKind] {
        ScreenClassifier.classify(all.map(\.0), hardware: hardwareID)
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
