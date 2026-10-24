import ApplicationServices
import CoreGraphics
import Foundation

/// Reading and writing other apps' windows over Accessibility. Every element gets a 0.1 s
/// messaging timeout before use so a hung app can't freeze Screen Monitor on the main thread.
enum AXWindow {
    static let timeout: Float = 0.1

    static func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { return nil }
        // CF types can't be checked with `as?` against AXUIElement; compare type IDs instead.
        if T.self == AXUIElement.self {
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! T)
        }
        return value as? T
    }

    private static func axValue(_ name: String, of element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    static func position(of window: AXUIElement) -> CGPoint? {
        var point = CGPoint.zero
        guard let value = axValue(kAXPositionAttribute, of: window), AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(of window: AXUIElement) -> CGSize? {
        var size = CGSize.zero
        guard let value = axValue(kAXSizeAttribute, of: window), AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let position = position(of: window), let size = size(of: window) else { return nil }
        return CGRect(origin: position, size: size)
    }

    static func setPosition(_ point: CGPoint, of window: AXUIElement) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        log(AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value), "position")
    }

    static func setSize(_ size: CGSize, of window: AXUIElement) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        log(AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value), "size")
    }

    /// Size first so a window moving to a bigger screen isn't clamped to the old one on the move,
    /// then size again because some apps clamp the size to the old screen when they move.
    static func setFrame(_ frame: CGRect, of window: AXUIElement) {
        setSize(frame.size, of: window)
        setPosition(frame.origin, of: window)
        setSize(frame.size, of: window)
    }

    /// Some windows refuse a move or resize (fixed-size panels, apps that are hung); they simply
    /// stay where they are.
    private static func log(_ error: AXError, _ what: String) {
        if error != .success { NSLog("Screen Monitor: couldn’t set the window %@ (AXError %d)", what, error.rawValue) }
    }
}
