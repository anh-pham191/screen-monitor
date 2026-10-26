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
    /// Set by `MonitorModel` from each refresh. Sticky: only a new EDID replaces it, so DDC going
    /// quiet (the screen showing another input) doesn't turn the hardware screen into a software one.
    private(set) static var hardwareEDID: EDIDInfo?

    /// Returns whether the stored EDID changed.
    @discardableResult
    static func update(hardwareEDID edid: EDIDInfo?) -> Bool {
        guard let edid, edid != hardwareEDID else { return false }
        hardwareEDID = edid
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
        ScreenClassifier.classify(all.map(\.0), hardwareEDID: hardwareEDID)
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
