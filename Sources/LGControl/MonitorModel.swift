import AppKit
import Combine
import Foundation
import LGKit

@MainActor
final class MonitorModel: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var hasTransport = false
    @Published var brightness: Double = 0
    @Published var contrast: Double = 0
    @Published var volume: Double = 0
    @Published private(set) var brightnessMax: Double = 100
    @Published private(set) var contrastMax: Double = 100
    @Published private(set) var volumeMax: Double = 100
    @Published private(set) var muted = false
    @Published private(set) var lastInput: Input? {
        didSet { defaults.set(lastInput?.rawValue, forKey: Keys.lastInput) }
    }
    @Published var inputConfig: InputConfig {
        didSet { defaults.set(try? JSONEncoder().encode(inputConfig), forKey: Keys.inputConfig) }
    }
    @Published private(set) var raw: [UInt8: VCPReading] = [:]
    @Published private(set) var details: DisplayDetails?
    @Published private(set) var capabilities: Capabilities?
    @Published private(set) var capabilitiesError: String?
    @Published private(set) var refreshing = false
    @Published private(set) var loadingCapabilities = false
    @Published var keysEnabled: Bool {
        didSet {
            defaults.set(keysEnabled, forKey: Keys.keysEnabled)
            if keysEnabled && !accessibilityTrusted { Accessibility.prompt() }
            updateKeyTap()
        }
    }
    @Published private(set) var accessibilityTrusted = Accessibility.isTrusted()
    /// The LG's EDID name, which is also its CoreAudio device name. Cached so a key press never
    /// walks the IORegistry.
    private(set) var lgName = MonitorModel.defaultLGName

    private enum Keys {
        static let lastInput = "lastInput"
        static let inputConfig = "inputConfig"
        static let keysEnabled = "keysEnabled"
    }

    private static let defaultLGName = "LG ULTRAFINE"

    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.anhpham.lgcontrol.ddc")
    /// Only ever touched on `queue`: the controller and the private API behind it are not main-actor safe.
    nonisolated(unsafe) private var ddc: DDCController?
    private var brightnessWriter: LatestValueWriter<UInt16>!
    private var contrastWriter: LatestValueWriter<UInt16>!
    private var volumeWriter: LatestValueWriter<UInt16>!
    private var screenObserver: NSObjectProtocol?
    private let keyTap = MediaKeyTap()
    private let hud = HUD()
    private var trustTimer: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastInput = defaults.string(forKey: Keys.lastInput).flatMap(Input.init(rawValue:))
        inputConfig = InputConfig.decodeOrDefault(defaults.data(forKey: Keys.inputConfig))
        keysEnabled = defaults.object(forKey: Keys.keysEnabled) as? Bool ?? true

        brightnessWriter = makeWriter(VCP.brightness)
        contrastWriter = makeWriter(VCP.contrast)
        volumeWriter = makeWriter(VCP.volume)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()

        keyTap.model = self
        if keysEnabled && !accessibilityTrusted { Accessibility.prompt() }
        recheckAccessibility()
    }

    private func makeWriter(_ code: UInt8) -> LatestValueWriter<UInt16> {
        LatestValueWriter(queue: queue, interval: 0.1) { [weak self] value in
            // Runs on `queue`. A dropped slider write is harmless; the next refresh shows the truth.
            try? self?.ddc?.write(code, value: value)
        }
    }

    // MARK: Reading

    func refresh() {
        // Repeated Retry presses would otherwise queue up seconds of timeouts.
        guard !refreshing else { return }
        refreshing = true
        queue.async { [weak self] in
            guard let self else { return }
            // Find the transport again each time: it goes stale after hot-plug or sleep.
            let transport = findExternalTransport()
            let controller = transport.map { DDCController(transport: $0) }
            self.ddc = controller
            let readout = controller.map { c in MonitorReadout.read { try c.read($0) } }
            // Not DDC, but an IORegistry walk: keep it off the main thread too.
            let name = DisplayDetailsReader.read()?.edid?.name
            DispatchQueue.main.async {
                self.lgName = name ?? Self.defaultLGName
                self.apply(hasTransport: transport != nil, readout: readout)
            }
        }
    }

    private func apply(hasTransport: Bool, readout: MonitorReadout?) {
        refreshing = false
        self.hasTransport = hasTransport
        guard let readout else {
            connected = false
            return
        }
        raw.merge(readout.raw) { _, new in new }
        guard readout.isComplete,
              let b = readout.raw[VCP.brightness], let c = readout.raw[VCP.contrast],
              let v = readout.raw[VCP.volume] else {
            connected = false
            return
        }
        brightnessMax = Double(max(b.maximum, 1))
        contrastMax = Double(max(c.maximum, 1))
        volumeMax = Double(max(v.maximum, 1))
        brightness = Double(b.current)
        contrast = Double(c.current)
        volume = Double(v.current)
        muted = readout.muted ?? false
        connected = true
    }

    // MARK: Writing

    func setBrightness(_ value: Double) {
        brightness = value
        brightnessWriter.submit(UInt16(value.rounded()))
    }

    func setContrast(_ value: Double) {
        contrast = value
        contrastWriter.submit(UInt16(value.rounded()))
    }

    func setVolume(_ value: Double) {
        volume = value
        volumeWriter.submit(UInt16(value.rounded()))
    }

    func setMuted(_ value: Bool) {
        muted = value
        queue.async { [weak self] in
            try? self?.ddc?.write(VCP.mute, value: value ? 1 : 2)
        }
    }

    func switchTo(_ input: Input) {
        if WindowPlacement.shouldMoveToBuiltIn(target: input,
                                               windowOnExternal: WindowMover.isWindowOnExternal(),
                                               builtInAvailable: WindowMover.builtInAvailable()) {
            // Leaving the Mac input blanks the LG, so get the window somewhere visible first.
            WindowMover.moveAppWindowsToBuiltInScreen()
        }
        let value = inputConfig.value(for: input)
        queue.async { [weak self] in
            guard let self else { return }
            let outcome = ReconnectingWrite.run(
                current: self.ddc,
                rediscover: { findExternalTransport().map { DDCController(transport: $0) } },
                write: { try $0.write(VCP.inputSource, value: value) })
            self.ddc = outcome.controller
            DispatchQueue.main.async {
                // Only record the input once the LG took it; otherwise the UI would claim a switch
                // that never happened. A refresh shows the user the LG is unreachable.
                if outcome.succeeded {
                    self.lastInput = input
                } else {
                    self.refresh()
                }
            }
        }
    }

    // MARK: Keys

    /// Call when Settings appears too: the grant can be revoked while the app runs.
    func recheckAccessibility() {
        accessibilityTrusted = Accessibility.isTrusted()
        updateKeyTap()
        guard !accessibilityTrusted, trustTimer == nil else { return }
        // macOS sends no notification when Anh ticks the box, so poll until he does.
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, Accessibility.isTrusted() else { return }
                timer.invalidate()
                self.trustTimer = nil
                self.accessibilityTrusted = true
                self.updateKeyTap()
            }
        }
    }

    private func updateKeyTap() {
        if keysEnabled && accessibilityTrusted { keyTap.start() } else { keyTap.stop() }
    }

    /// Unknown maximum (never read, or reported as 0): the keys stay with macOS rather than guess.
    func canHandleMediaKey(_ key: MediaKey) -> Bool {
        switch key {
        case .brightnessUp, .brightnessDown: return (raw[VCP.brightness]?.maximum ?? 0) > 0
        case .volumeUp, .volumeDown: return (raw[VCP.volume]?.maximum ?? 0) > 0
        case .mute: return true
        }
    }

    /// Updates the published value straight away so a run of presses builds on itself rather than
    /// on a stale reading, then writes through the same rate-limited writer as the slider.
    func handleMediaKey(_ event: MediaKeyEvent, fine: Bool) {
        guard event.isDown else { return }
        switch event.key {
        case .brightnessUp, .brightnessDown:
            guard let maximum = raw[VCP.brightness]?.maximum, maximum > 0 else { return }
            let next = Stepper.step(current: Stepper.wireValue(brightness), maximum: maximum,
                                    up: event.key == .brightnessUp, fine: fine)
            setBrightness(Double(next))
            showHUD(.brightness, level: HUDLevel.fraction(next, maximum: maximum))
        case .volumeUp, .volumeDown:
            guard let maximum = raw[VCP.volume]?.maximum, maximum > 0 else { return }
            // Like macOS: a volume key while muted unmutes, then steps.
            if muted { setMuted(false) }
            let next = Stepper.step(current: Stepper.wireValue(volume), maximum: maximum,
                                    up: event.key == .volumeUp, fine: fine)
            setVolume(Double(next))
            showHUD(.volume, level: HUDLevel.fraction(next, maximum: maximum))
        case .mute:
            setMuted(!muted)
            let maximum = raw[VCP.volume]?.maximum ?? 0
            showHUD(muted ? .muted : .volume, level: HUDLevel.fraction(Stepper.wireValue(volume), maximum: maximum))
        }
    }

    private func showHUD(_ kind: HUD.Kind, level: Double) {
        guard let screen = MediaKeyTap.lgScreen() else { return }
        hud.show(kind, level: level, on: screen)
    }

    // MARK: Details

    func loadDetails(forceCapabilities: Bool = false) {
        details = DisplayDetailsReader.read()
        if forceCapabilities {
            capabilities = nil
            capabilitiesError = nil
        }
        // A capabilities fetch takes seconds, so keep the first good one.
        guard capabilities == nil, !loadingCapabilities else { return }
        loadingCapabilities = true
        queue.async { [weak self] in
            guard let self else { return }
            if self.ddc == nil { self.ddc = findExternalTransport().map { DDCController(transport: $0) } }
            let result: Result<Capabilities, Error>
            if let ddc = self.ddc {
                result = Result { Capabilities.parse(try ddc.capabilities()) }
            } else {
                result = .failure(DDCError.noReply(code: 0xF3))
            }
            DispatchQueue.main.async {
                self.loadingCapabilities = false
                switch result {
                case .success(let caps):
                    self.capabilities = caps
                    self.capabilitiesError = nil
                case .failure(let error):
                    self.capabilitiesError = Self.describe(error)
                }
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case DDCError.noReply: return "The LG didn’t answer the capabilities request."
        case DDCError.writeFailed: return "Couldn’t send the capabilities request."
        default: return error.localizedDescription
        }
    }
}
