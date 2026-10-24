import AppKit
import ApplicationServices
import LGKit

/// Moves every app's windows off the LG before it leaves the Mac input, and puts them back on
/// return. Leaving the Mac input blanks the LG while macOS still treats it as a screen, so
/// anything left there would be out of sight until the switch back.
///
/// Runs on the main thread; every Accessibility element gets a 0.1 s timeout so one hung app
/// costs at most a moment rather than freezing the switch.
@MainActor
enum WindowShuffler {
    private struct Moved {
        let pid: pid_t
        let window: AXUIElement
        /// In Accessibility coordinates, as read before the move.
        let frame: CGRect
    }

    private static var moved: [Moved] = []
    private static var pendingRestore: Timer?
    /// After a switch back the LG may take a moment to reappear as a screen; restoring before it
    /// does would clamp the windows onto the MacBook.
    private static let restoreWait: TimeInterval = 10
    private static let restorePoll: TimeInterval = 0.5

    static func moveAllWindowsToBuiltIn() {
        pendingRestore?.invalidate()
        pendingRestore = nil
        guard WindowMover.builtInScreen() != nil else { return }
        // Our own windows go through AppKit: an AX request to our own process is answered on the
        // main thread, which is the one waiting for it, so it would just time out.
        WindowMover.moveAppWindowsToBuiltInScreen()
        guard Accessibility.isTrusted() else { return }
        guard let builtIn = WindowMover.builtInScreen() else { return }
        guard let lg = MediaKeyTap.lgScreen(), let primary = NSScreen.screens.first?.frame.height else { return }
        let lgFrame = SnapZones.axRect(fromCocoa: lg.frame, primaryScreenHeight: primary)
        let destination = SnapZones.axRect(fromCocoa: builtIn.visibleFrame, primaryScreenHeight: primary)
        let ownPID = ProcessInfo.processInfo.processIdentifier

        // A second switch away (PS5 then Windows) keeps the first set of frames: those are the ones
        // that belong on the LG.
        let alreadyMoved = moved
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != ownPID {
            let pid = app.processIdentifier
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, AXWindow.timeout)
            guard let windows: [AXUIElement] = AXWindow.attribute(kAXWindowsAttribute, of: element) else { continue }
            for window in windows {
                AXUIElementSetMessagingTimeout(window, AXWindow.timeout)
                // Minimised windows are out of sight anyway; a full-screen one owns its own Space on the LG.
                if isMinimisedOrFullScreen(window) { continue }
                guard let frame = AXWindow.frame(of: window), WindowRelocation.isOn(frame, screen: lgFrame) else { continue }
                AXWindow.setFrame(WindowRelocation.target(for: frame, from: lgFrame, to: destination), of: window)
                if !alreadyMoved.contains(where: { CFEqual($0.window, window) }) {
                    moved.append(Moved(pid: pid, window: window, frame: frame))
                }
            }
        }
    }

    /// Waits for the LG to come back as a screen, then puts each moved window back. Windows closed
    /// in the meantime no longer answer and are skipped.
    static func restoreWindows() {
        pendingRestore?.invalidate()
        pendingRestore = nil
        guard !moved.isEmpty else { return }
        guard Accessibility.isTrusted() else {
            moved = []
            return
        }
        if MediaKeyTap.lgScreen() != nil {
            restoreNow()
            return
        }
        let deadline = Date().addingTimeInterval(restoreWait)
        pendingRestore = Timer.scheduledTimer(withTimeInterval: restorePoll, repeats: true) { timer in
            MainActor.assumeIsolated {
                if MediaKeyTap.lgScreen() != nil {
                    timer.invalidate()
                    pendingRestore = nil
                    restoreNow()
                } else if Date() >= deadline {
                    // The LG never came back: the windows are fine where they are on the MacBook.
                    timer.invalidate()
                    pendingRestore = nil
                    moved = []
                }
            }
        }
    }

    private static func restoreNow() {
        for entry in moved {
            // A closed window, or an app that quit, no longer reports a position.
            // Minimised or made full screen while away: Anh moved it on purpose, so leave it.
            guard NSRunningApplication(processIdentifier: entry.pid) != nil,
                  AXWindow.position(of: entry.window) != nil,
                  !isMinimisedOrFullScreen(entry.window) else { continue }
            AXWindow.setFrame(entry.frame, of: entry.window)
        }
        moved = []
    }

    private static func isMinimisedOrFullScreen(_ window: AXUIElement) -> Bool {
        let minimised: Bool = AXWindow.attribute(kAXMinimizedAttribute, of: window) ?? false
        let fullScreen: Bool = AXWindow.attribute("AXFullScreen", of: window) ?? false
        return minimised || fullScreen
    }
}
