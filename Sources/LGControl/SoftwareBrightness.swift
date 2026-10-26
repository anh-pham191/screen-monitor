import AppKit
import Combine
import Foundation
import LGKit

struct SoftwareScreen: Identifiable, Equatable {
    /// The screen's `ScreenKey`, which is also where its level is remembered.
    let id: String
    let name: String
    let level: Int
    let warmth: Int
}

/// Brightness for external screens without hardware control (DisplayLink today): a black,
/// click-through overlay whose opacity dims the screen. Level 100 means no overlay at all.
/// Warmth goes through the screens' colour tables (`ColorTables`), not the overlay.
@MainActor
final class SoftwareBrightness: ObservableObject {
    @Published private(set) var screens: [SoftwareScreen] = []
    /// When off, no screen is warmed (the saved values are kept).
    @Published var warmthEnabled: Bool {
        didSet {
            guard warmthEnabled != oldValue else { return }
            defaults.set(warmthEnabled, forKey: Self.warmthEnabledKey)
            refreshWarmth()
        }
    }

    private static let defaultsKey = "softwareBrightness"
    private static let warmthEnabledKey = "warmthEnabled"

    private let defaults: UserDefaults
    private let hud: HUD
    private var levels: SoftwareLevels
    /// Only screens below 100 have one.
    private var overlays: [String: OverlayPanel] = [:]
    private let colorTables = ColorTables()
    private var saveTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    /// Called after every rebuild; the key tap uses it to let go of screens that may be gone.
    var onRebuild: (() -> Void)?

    init(defaults: UserDefaults, hud: HUD) {
        self.defaults = defaults
        self.hud = hud
        warmthEnabled = defaults.object(forKey: Self.warmthEnabledKey) as? Bool ?? true
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
        let list = current.map { SoftwareScreen(id: $0.key, name: $0.name, level: levels.level(for: $0.key),
                                                      warmth: levels.warmth(for: $0.key)) }
        if list != screens { screens = list }
        let present = Set(current.map(\.key))
        for key in overlays.keys where !present.contains(key) { removeOverlay(key) }
        for entry in current { updateOverlay(key: entry.key, on: entry.screen) }
        refreshWarmth(current)
        onRebuild?()
    }

    /// The overlay follows at once; the level is written to defaults once changes pause.
    func setLevel(_ level: Int, for key: String) {
        levels.set(level, for: key)
        scheduleSave()
        applyChange(for: key)
    }

    /// Same debounced save as levels; the colour tables follow at once.
    func setWarmth(_ warmth: Int, for key: String) {
        levels.setWarmth(warmth, for: key)
        scheduleSave()
        applyChange(for: key)
        refreshWarmth()
    }

    private func applyChange(for key: String) {
        let level = levels.level(for: key), warmth = levels.warmth(for: key)
        if let index = screens.firstIndex(where: { $0.id == key }),
           screens[index].level != level || screens[index].warmth != warmth {
            screens[index] = SoftwareScreen(id: key, name: screens[index].name, level: level, warmth: warmth)
        }
        if let screen = ScreenCatalog.softwareScreens().first(where: { $0.key == key })?.screen {
            updateOverlay(key: key, on: screen)
        } else {
            removeOverlay(key)
        }
    }

    /// Warms every software screen to its effective warmth (0 when warmth is off); every other
    /// screen gets its own colours back.
    private func refreshWarmth(_ current: [(key: String, name: String, screen: NSScreen)]? = nil) {
        var warmths: [CGDirectDisplayID: Int] = [:]
        for entry in current ?? ScreenCatalog.softwareScreens() {
            guard let id = ScreenCatalog.displayID(of: entry.screen) else { continue }
            warmths[id] = warmthEnabled ? levels.warmth(for: entry.key) : 0
        }
        colorTables.update(warmths)
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

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveLevels()
        }
    }

    private func saveLevels() {
        saveTask?.cancel()
        saveTask = nil
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
