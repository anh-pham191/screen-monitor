import AppKit
import SwiftUI
import LGKit

/// The on-screen indicator for key presses, drawn on the LG. macOS's own OSD is private API,
/// so this imitates it: a symbol over a 16-segment bar.
@MainActor
final class HUD {
    enum Kind { case brightness, volume, muted }

    private final class State: ObservableObject {
        @Published var kind: Kind = .brightness
        @Published var level: Double = 0
    }

    private static let size = NSSize(width: 200, height: 200)
    private let state = State()
    private var panel: NSPanel?
    private var hideTimer: Timer?
    /// Bumped on every show, so a fade that finishes after a newer show doesn't hide it.
    private var generation = 0

    func show(_ kind: Kind, level: Double, on screen: NSScreen) {
        state.kind = kind
        state.level = level
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let frame = screen.frame
        panel.setFrameOrigin(NSPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + 140))
        generation += 1
        // A plain assignment doesn't stop a fade already running in the animator, which would
        // carry on to 0; a zero-length animation replaces it.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            panel.animator().alphaValue = 1
        }
        // Never make it key: that would steal focus from whatever Anh is typing in.
        panel.orderFrontRegardless()

        hideTimer?.invalidate()
        let shown = generation
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fadeOut(generation: shown) }
        }
    }

    private func fadeOut(generation shown: Int) {
        guard let panel, shown == generation else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, shown == self.generation else { return }
                panel.orderOut(nil)
            }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false

        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 18
        blur.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: HUDContent(state: state))
        hosting.frame = blur.bounds
        hosting.autoresizingMask = [.width, .height]
        blur.addSubview(hosting)
        panel.contentView = blur
        return panel
    }

    private struct HUDContent: View {
        @ObservedObject var state: State

        var body: some View {
            VStack(spacing: 28) {
                Image(systemName: symbol)
                    .font(.system(size: 72, weight: .regular))
                    .frame(height: 90)
                SegmentBar(fills: HUDLevel.segmentFills(level: state.kind == .muted ? 0 : state.level, count: 16))
            }
            .foregroundStyle(.primary)
            .frame(width: 200, height: 200)
        }

        private var symbol: String {
            switch state.kind {
            case .brightness: return "sun.max.fill"
            case .volume: return "speaker.wave.2.fill"
            case .muted: return "speaker.slash.fill"
            }
        }
    }

    private struct SegmentBar: View {
        let fills: [Double]

        var body: some View {
            HStack(spacing: 2) {
                ForEach(fills.indices, id: \.self) { i in
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.primary.opacity(0.2))
                            Rectangle().fill(.primary).frame(width: geo.size.width * fills[i])
                        }
                    }
                }
            }
            .frame(width: 160, height: 8)
        }
    }
}
