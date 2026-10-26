import AppKit
import CoreGraphics

@MainActor
enum WindowMover {
    static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return false }
            return CGDisplayIsBuiltin(CGDirectDisplayID(id.uint32Value)) != 0
        }
    }

    static func isWindowOnExternal() -> Bool {
        guard let builtIn = builtInScreen() else { return !appWindows().isEmpty }
        return appWindows().contains { $0.screen != builtIn }
    }

    static func moveAppWindows(to destination: NSScreen) {
        let area = destination.visibleFrame
        for window in appWindows() where window.screen != destination {
            let width = min(window.frame.width, area.width)
            let height = min(window.frame.height, area.height)
            let frame = NSRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
            window.setFrame(frame, display: true)
        }
    }

    /// Real app windows only: the status item and the menu bar panel are untitled or can't become main.
    private static func appWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) && $0.canBecomeMain }
    }
}
