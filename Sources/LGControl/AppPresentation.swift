import AppKit
import SwiftUI
import LGKit

/// Menu bar app plumbing: Dock policy and bringing windows forward without a Dock icon.
@MainActor
enum AppPresentation {
    static func applyDockPolicy(showInDock: Bool) {
        let policy: NSApplication.ActivationPolicy = DockPolicy.isRegular(showInDock: showInDock) ? .regular : .accessory
        let visible = NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }
        NSApp.setActivationPolicy(policy)
        // macOS can hide windows on a policy change; keep them up and take focus back.
        if policy == .accessory, !visible.isEmpty {
            DispatchQueue.main.async {
                visible.forEach { $0.orderFrontRegardless() }
                activate()
            }
        }
    }

    static func activate() {
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }

    /// Call right after opening a window: the window may not exist yet, so front it on the next turns too.
    static func bringToFront() {
        activate()
        for delay in [0.0, 0.15] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                activate()
                let target = NSApp.windows.last { $0.isVisible && $0.canBecomeKey && !($0 is NSPanel) }
                target?.makeKeyAndOrderFront(nil)
                target?.orderFrontRegardless()
            }
        }
    }
}
