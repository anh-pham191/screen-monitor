import AppKit
import Combine
import SwiftUI

/// The menu bar icon and its drop-down panel, built by hand instead of with `MenuBarExtra`.
/// SwiftUI's window-style `MenuBarExtra` grows with its content but never shrinks back, so after
/// sleeping at one desk and waking at another the panel sat in a window sized for screens that
/// were gone, and resizing that window from outside didn't stick. Here the panel's content is
/// built fresh each time it opens and the window always takes its size.
@MainActor
final class MenuBarPanel: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let makeContent: () -> AnyView
    private var panel: DropDownPanel?
    private var outsideClickMonitor: Any?
    private var closedAt = Date.distantPast
    private var badgeSubscription: AnyCancellable?

    init<Content: View>(keepAwake: KeepAwakeModel, @ViewBuilder content: @escaping () -> Content) {
        makeContent = { AnyView(content()) }
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Screen Monitor")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(toggle)
        }
        // While Keep Awake holds, the time left (or the port) sits beside the icon.
        badgeSubscription = keepAwake.$badgeText.receive(on: RunLoop.main).sink { [weak self] badge in
            guard let button = self?.statusItem.button else { return }
            // Monospaced digits stop the menu bar item jittering as the minutes change.
            button.attributedTitle = NSAttributedString(
                string: badge.map { " " + $0 } ?? "",
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)])
        }
    }

    @objc private func toggle() {
        if panel?.isVisible == true { close(); return }
        // The click on the icon already closed the panel (it lost focus on mouse down); don't reopen.
        if Date().timeIntervalSince(closedAt) < 0.3 { return }
        open()
    }

    private func open() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let host = FittingHostingView(rootView: makeContent())
        host.onSizeChange = { [weak self] in self?.fit() }
        panel.contentHost.subviews.forEach { $0.removeFromSuperview() }
        host.translatesAutoresizingMaskIntoConstraints = false
        panel.contentHost.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: panel.contentHost.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: panel.contentHost.trailingAnchor),
            host.topAnchor.constraint(equalTo: panel.contentHost.topAnchor),
            host.bottomAnchor.constraint(equalTo: panel.contentHost.bottomAnchor),
        ])

        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = host.fittingSize
        var origin = NSPoint(x: anchor.minX, y: anchor.minY - 4 - size.height)
        if let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    /// Follows the content while the panel is open (a screen plugged in, a setting turned on),
    /// keeping the top edge under the menu bar.
    private func fit() {
        DispatchQueue.main.async { [weak self] in
            guard let panel = self?.panel, panel.isVisible,
                  let host = panel.contentHost.subviews.first else { return }
            let size = host.fittingSize
            guard size.height > 0, abs(panel.frame.height - size.height) > 0.5 else { return }
            var frame = panel.frame
            frame.origin.y += frame.height - size.height
            frame.size.height = size.height
            panel.setFrame(frame, display: true)
        }
    }

    private func close() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        // Drop the content so nothing in it keeps updating while hidden, and the next open
        // measures it from scratch.
        panel.contentHost.subviews.forEach { $0.removeFromSuperview() }
        statusItem.button?.highlight(false)
        closedAt = Date()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    private func makePanel() -> DropDownPanel {
        let panel = DropDownPanel()
        panel.onResignKey = { [weak self] in self?.close() }
        panel.onCancel = { [weak self] in self?.close() }
        return panel
    }
}

/// A borderless panel that can take keyboard focus (for sliders) without activating the app,
/// drawn with the same material and corners as a menu bar drop-down.
private final class DropDownPanel: NSPanel {
    var onResignKey: (() -> Void)?
    var onCancel: (() -> Void)?
    let contentHost = NSView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let material = NSVisualEffectView()
        material.material = .menu
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 10
        material.layer?.masksToBounds = true
        contentView = material
        contentHost.frame = material.bounds
        contentHost.autoresizingMask = [.width, .height]
        material.addSubview(contentHost)
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Tells the panel when the SwiftUI content's size changes.
private final class FittingHostingView: NSHostingView<AnyView> {
    var onSizeChange: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onSizeChange?()
    }
}
