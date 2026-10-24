import AppKit
import ApplicationServices
import LGKit

/// Watches other apps' window drags and snaps a window dropped on the LG into the half under
/// the pointer.
///
/// macOS has no "window drag" event for other apps, so this infers one: on mouse down it finds
/// the window under the pointer, and while the mouse is dragged it checks whether that window's
/// position follows. Global monitors are delivered on the main thread; every Accessibility call
/// has a 0.1 s timeout so a hung app can't freeze LG Control.
@MainActor
final class WindowDragMonitor {
    private struct Tracked {
        let window: AXUIElement
        let startPosition: CGPoint
        let startSize: CGSize
        var position: CGPoint
        var size: CGSize
        var lastRead: TimeInterval
    }

    private static let timeout: Float = 0.1
    /// Reading another app's window over Accessibility is a cross-process round trip; a drag
    /// produces events far faster than that is worth.
    private static let readInterval: TimeInterval = 0.05

    private let systemWide = AXUIElementCreateSystemWide()
    private let overlay = SnapOverlay()
    private var monitor: Any?
    private var tracked: Tracked?
    private var highlighted: Int?

    var isRunning: Bool { monitor != nil }

    init() {
        AXUIElementSetMessagingTimeout(systemWide, Self.timeout)
    }

    /// Needs Accessibility: without it the hit test finds nothing and the monitor sees no events.
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        reset()
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown: mouseDown()
        case .leftMouseDragged: mouseDragged()
        case .leftMouseUp: mouseUp()
        default: break
        }
    }

    // MARK: Events

    private func mouseDown() {
        reset()
        // Nothing to snap to without the LG; skip the cross-process hit test on every click.
        guard MediaKeyTap.lgScreen() != nil, let primary = Self.primaryScreenHeight else { return }
        let point = SnapZones.axPoint(fromCocoa: NSEvent.mouseLocation, primaryScreenHeight: primary)
        var hit: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit)
        guard error == .success, let hit else { return }
        guard let window = Self.window(containing: hit), !Self.isOwnWindow(window),
              let position = Self.position(of: window), let size = Self.size(of: window) else { return }
        tracked = Tracked(window: window, startPosition: position, startSize: size,
                          position: position, size: size, lastRead: ProcessInfo.processInfo.systemUptime)
    }

    private func mouseDragged() {
        guard var t = tracked else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - t.lastRead >= Self.readInterval {
            t.lastRead = now
            if let p = Self.position(of: t.window) { t.position = p }
            if let s = Self.size(of: t.window) { t.size = s }
            tracked = t
        }
        // The pointer is local, so the highlight follows it on every event even between reads.
        let pointer = NSEvent.mouseLocation
        guard let lg = MediaKeyTap.lgScreen(),
              SnapZones.isWindowDrag(startPosition: t.startPosition, startSize: t.startSize,
                                     position: t.position, size: t.size,
                                     pointerOnLG: NSMouseInRect(pointer, lg.frame, false)) else {
            hideOverlay()
            return
        }
        let zones = SnapZones.halves(of: lg.visibleFrame)
        highlighted = SnapZones.zoneIndex(at: pointer, in: zones)
        overlay.show(zones: zones, highlighted: highlighted, on: lg)
    }

    private func mouseUp() {
        defer { reset() }
        guard let t = tracked, let index = highlighted, let lg = MediaKeyTap.lgScreen(),
              let primary = Self.primaryScreenHeight else { return }
        let zones = SnapZones.halves(of: lg.visibleFrame)
        guard zones.indices.contains(index) else { return }
        let target = SnapZones.axRect(fromCocoa: zones[index], primaryScreenHeight: primary)
        // Size first so a window arriving from the smaller MacBook screen isn't clamped to it when
        // it moves, then size again because some apps clamp the size to the old screen on the move.
        Self.setSize(target.size, of: t.window)
        Self.setPosition(target.origin, of: t.window)
        Self.setSize(target.size, of: t.window)
    }

    private func reset() {
        tracked = nil
        hideOverlay()
    }

    private func hideOverlay() {
        highlighted = nil
        if overlay.isVisible { overlay.hide() }
    }

    // MARK: Accessibility

    /// Accessibility coordinates are anchored to the screen at (0, 0), not NSScreen.main.
    private static var primaryScreenHeight: CGFloat? { NSScreen.screens.first?.frame.height }

    private static func window(containing element: AXUIElement) -> AXUIElement? {
        AXUIElementSetMessagingTimeout(element, timeout)
        if let window: AXUIElement = attribute(kAXWindowAttribute, of: element) {
            AXUIElementSetMessagingTimeout(window, timeout)
            return window
        }
        // Some elements (title bars, toolbars) don't answer kAXWindow; walk up instead. The cap
        // guards against a broken hierarchy that loops.
        var current = element
        for _ in 0..<64 {
            if let role: String = attribute(kAXRoleAttribute, of: current), role == kAXWindowRole as String {
                return current
            }
            guard let parent: AXUIElement = attribute(kAXParentAttribute, of: current) else { return nil }
            AXUIElementSetMessagingTimeout(parent, timeout)
            current = parent
        }
        return nil
    }

    private static func isOwnWindow(_ window: AXUIElement) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return true }
        return pid == ProcessInfo.processInfo.processIdentifier
    }

    private static func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
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

    private static func position(of window: AXUIElement) -> CGPoint? {
        var point = CGPoint.zero
        guard let value = axValue(kAXPositionAttribute, of: window), AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private static func size(of window: AXUIElement) -> CGSize? {
        var size = CGSize.zero
        guard let value = axValue(kAXSizeAttribute, of: window), AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    private static func setPosition(_ point: CGPoint, of window: AXUIElement) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        log(AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value), "position")
    }

    private static func setSize(_ size: CGSize, of window: AXUIElement) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        log(AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value), "size")
    }

    /// Some windows refuse a move or resize (fixed-size panels, apps that are hung); the drop
    /// simply doesn't snap.
    private static func log(_ error: AXError, _ what: String) {
        if error != .success { NSLog("LG Control: couldn’t set the window %@ (AXError %d)", what, error.rawValue) }
    }
}
