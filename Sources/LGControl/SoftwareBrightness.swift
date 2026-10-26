import AppKit
import Combine
import Foundation
import LGKit

struct SoftwareScreen: Identifiable, Equatable {
    /// The screen's `ScreenKey`, which is also where its level is remembered.
    let id: String
    let name: String
    let level: Int
}

/// Brightness for external screens without hardware control (DisplayLink today): a black,
/// click-through overlay whose opacity dims the screen. Level 100 means no overlay at all.
@MainActor
final class SoftwareBrightness: ObservableObject {
    @Published private(set) var screens: [SoftwareScreen] = []

    private static let defaultsKey = "softwareBrightness"

    private let defaults: UserDefaults
    private let hud: HUD
    private var levels: SoftwareLevels
    /// Only screens below 100 have one.
    private var overlays: [String: OverlayPanel] = [:]
    private var screenObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    /// Called after every rebuild; the key tap uses it to let go of screens that may be gone.
    var onRebuild: (() -> Void)?

    init(defaults: UserDefaults, hud: HUD) {
        self.defaults = defaults
        self.hud = hud
        levels = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(SoftwareLevels.self, from: $0) } ?? SoftwareLevels()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hideMisplacedOverlays()
                self?.rebuild()
            }
        }
        // Screens can come back in a different place, or not at all, after sleep.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
        rebuild()
    }

    /// Re-reads the screens and puts each overlay on its screen. Also called by `MonitorModel`
    /// when the hardware screen's EDID changes, which can turn a "software" screen into the hardware one.
    func rebuild() {
        // A level stored while the hardware screen wasn't recognised yet must not dim it later.
        if let key = ScreenCatalog.hardwareScreenKey(), levels.forget(key) { saveLevels() }
        let current = ScreenCatalog.softwareScreens()
        let list = current.map { SoftwareScreen(id: $0.key, name: $0.name, level: levels.level(for: $0.key)) }
        if list != screens { screens = list }
        let present = Set(current.map(\.key))
        for key in overlays.keys where !present.contains(key) { removeOverlay(key) }
        for entry in current { updateOverlay(key: entry.key, on: entry.screen) }
        onRebuild?()
    }

    func setLevel(_ level: Int, for key: String) {
        levels.set(level, for: key)
        saveLevels()
        let clamped = levels.level(for: key)
        if let index = screens.firstIndex(where: { $0.id == key }), screens[index].level != clamped {
            screens[index] = SoftwareScreen(id: key, name: screens[index].name, level: clamped)
        }
        if let screen = ScreenCatalog.softwareScreens().first(where: { $0.key == key })?.screen {
            updateOverlay(key: key, on: screen)
        } else {
            removeOverlay(key)
        }
    }

    /// Same steps and modifier rules as the hardware screen, on a 0–100 scale.
    func handleMediaKey(_ event: MediaKeyEvent, fine: Bool, on screen: NSScreen) {
        guard event.isDown, event.key == .brightnessUp || event.key == .brightnessDown,
              let key = ScreenCatalog.softwareScreens().first(where: { $0.screen == screen })?.key else { return }
        let current = UInt16(levels.level(for: key))
        let next = Stepper.step(current: current, maximum: 100, up: event.key == .brightnessUp, fine: fine)
        setLevel(Int(next), for: key)
        hud.show(.brightness, level: HUDLevel.fraction(next, maximum: 100), on: screen)
    }

    private func saveLevels() {
        defaults.set(try? JSONEncoder().encode(levels), forKey: Self.defaultsKey)
    }

    // MARK: Overlays

    /// After a screen change an overlay may sit where its screen no longer is (or over a screen
    /// that is now the hardware one); hide those at once, before the rebuild sorts out the rest.
    private func hideMisplacedOverlays() {
        let frames = ScreenCatalog.softwareScreens().map(\.screen.frame)
        for panel in overlays.values where !frames.contains(panel.frame) { panel.orderOut(nil) }
    }

    private func updateOverlay(key: String, on screen: NSScreen) {
        let level = levels.level(for: key)
        guard level < 100 else { return removeOverlay(key) }
        let panel = overlays[key] ?? OverlayPanel()
        overlays[key] = panel
        panel.alphaValue = SoftwareDimming.opacity(level: level)
        if panel.frame != screen.frame { panel.setFrame(screen.frame, display: false) }
        // Never make it key: that would steal focus from whatever Anh is typing in.
        panel.orderFrontRegardless()
    }

    private func removeOverlay(_ key: String) {
        overlays.removeValue(forKey: key)?.close()
    }
}

/// A black sheet over one screen: never key or main, never takes a click.
private final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        backgroundColor = .black
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        // Best effort: keeps screenshots and screen sharing undimmed.
        sharingType = .none
        // Above normal windows and the menu bar; the HUD sits one level higher.
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
