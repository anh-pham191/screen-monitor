import AppKit
import SwiftUI
import LGKit

/// The drop targets shown on the LG while a window is dragged over it.
///
/// Same panel set-up as the HUD: it must never take focus or clicks from the drag in progress.
@MainActor
final class SnapOverlay {
    private final class State: ObservableObject {
        /// In the panel's own SwiftUI coordinates (top-left origin).
        @Published var zones: [CGRect] = []
        @Published var highlighted: Int?
    }

    private let state = State()
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    /// - Parameter zones: in Cocoa screen coordinates, inside `screen.visibleFrame`.
    func show(zones: [CGRect], highlighted: Int?, on screen: NSScreen) {
        let frame = screen.visibleFrame
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        // SwiftUI draws from the top-left, Cocoa from the bottom-left.
        let local = zones.map { CGRect(x: $0.minX - frame.minX, y: frame.maxY - $0.maxY, width: $0.width, height: $0.height) }
        if state.zones != local { state.zones = local }
        if state.highlighted != highlighted { state.highlighted = highlighted }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        panel?.orderOut(nil)
        state.highlighted = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        let hosting = NSHostingView(rootView: OverlayContent(state: state))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }

    private struct OverlayContent: View {
        @ObservedObject var state: State

        var body: some View {
            ZStack(alignment: .topLeading) {
                ForEach(state.zones.indices, id: \.self) { i in
                    let zone = state.zones[i].insetBy(dx: 8, dy: 8)
                    let lit = state.highlighted == i
                    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                    shape
                        .fill(Color(nsColor: .controlAccentColor).opacity(lit ? 0.35 : 0.15))
                        .overlay(shape.strokeBorder(Color(nsColor: .controlAccentColor), lineWidth: lit ? 2 : 0))
                        .frame(width: max(zone.width, 0), height: max(zone.height, 0))
                        .offset(x: zone.minX, y: zone.minY)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
