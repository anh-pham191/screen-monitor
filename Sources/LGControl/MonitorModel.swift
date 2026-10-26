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
    /// Starts on the Mac's port: the app is opened there, and the LG reports input 0 whatever it shows,
    /// so a remembered input from an earlier session (maybe a switch that bounced back) would lie.
    @Published private(set) var lastInput: Input?
    /// The port this Mac is plugged into.
    @Published var macPort: Input {
        didSet {
            defaults.set(macPort.rawValue, forKey: Keys.macPort)
            // Still on the Mac, now under its new port.
            if lastInput == oldValue { lastInput = macPort }
        }
    }
    @Published var inputConfig: InputConfig {
        didSet {
            defaults.set(try? JSONEncoder().encode(inputConfig), forKey: Keys.inputConfig)
            // Any change that isn't the automatic pick is the user's own.
            if !applyingAutomaticCommand { commandIsAutomatic = false }
        }
    }
    @Published private(set) var raw: [UInt8: VCPReading] = [:]
    @Published private(set) var details: DisplayDetails? {
        // A screen that matches a new EDID stops being a software screen (and loses its overlay).
        didSet { if ScreenCatalog.update(hardwareEDID: details?.edid) { softwareBrightness.rebuild() } }
    }
    @Published private(set) var capabilities: Capabilities?
    /// The string the LG sent, kept next to the parse so Details can show what the parser missed.
    @Published private(set) var capabilitiesRaw: String?
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
    @Published var splitEnabled: Bool {
        didSet {
            defaults.set(splitEnabled, forKey: Keys.splitEnabled)
            if splitEnabled && !accessibilityTrusted { Accessibility.prompt() }
            updateKeyTap()
        }
    }
    @Published private(set) var accessibilityTrusted = Accessibility.isTrusted()
    /// False while the keys are wanted but the event tap couldn't be created, so Settings can say so.
    @Published private(set) var keyTapActive = false
    @Published var syncEnabled: Bool {
        didSet {
            guard syncEnabled != oldValue else { return }
            defaults.set(syncEnabled, forKey: Keys.syncEnabled)
            updateSync(turningOn: syncEnabled)
        }
    }
    /// In the LG's brightness units. Mirrors `follower.offset`, which is the source of truth.
    @Published private(set) var syncOffset: Int {
        didSet { defaults.set(syncOffset, forKey: Keys.syncOffset) }
    }
    /// The LG's EDID name, which is also its CoreAudio device name. Cached so a key press never
    /// walks the IORegistry.
    private(set) var lgName = MonitorModel.defaultLGName

    private enum Keys {
        static let inputConfig = "inputConfig"
        static let macPort = "macPort"
        static let keysEnabled = "keysEnabled"
        static let splitEnabled = "splitEnabled"
        static let syncEnabled = "syncEnabled"
        static let syncOffset = "syncOffset"
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
    private var wakeObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    /// Refreshes that failed in a row; drives the retry back-off.
    private var failedRefreshes = 0
    /// Whether macOS was sending sound to the LG when it last left the Mac input.
    private var lgWasSoundOutput = false
    private var audioRestoreTimer: Timer?
    private var refreshCoalescer = RefreshCoalescer()
    /// One delayed refresh at a time: a burst of screen or wake notifications shares it.
    private var delayedRefresh: DispatchWorkItem?
    private var keyTapRetry: Timer?
    /// True while nothing was ever saved and the user hasn't edited the config since, so the
    /// command may follow the screen's maker. `seenManufacturers` keeps it to once per maker.
    private var commandIsAutomatic: Bool
    private var applyingAutomaticCommand = false
    private var seenManufacturers: Set<String> = []
    private let keyTap = MediaKeyTap()
    private let dragMonitor = WindowDragMonitor()
    /// Shared with `softwareBrightness`, so there is only ever one indicator on screen.
    private let hud: HUD
    let softwareBrightness: SoftwareBrightness
    private var trustTimer: Timer?
    private var follower: BrightnessFollower
    private var syncTimer: Timer?

    init(defaults: UserDefaults = .standard, softwareBrightness: SoftwareBrightness, hud: HUD) {
        self.defaults = defaults
        self.softwareBrightness = softwareBrightness
        self.hud = hud
        inputConfig = InputConfig.decodeOrDefault(defaults.data(forKey: Keys.inputConfig))
        commandIsAutomatic = defaults.data(forKey: Keys.inputConfig) == nil
        let storedPort = defaults.string(forKey: Keys.macPort).flatMap(Input.init(rawValue:)) ?? .hdmi1
        macPort = storedPort
        lastInput = storedPort
        keysEnabled = defaults.object(forKey: Keys.keysEnabled) as? Bool ?? true
        splitEnabled = defaults.object(forKey: Keys.splitEnabled) as? Bool ?? true
        let storedOffset = defaults.integer(forKey: Keys.syncOffset)
        follower = BrightnessFollower(offset: storedOffset)
        syncOffset = storedOffset
        syncEnabled = defaults.bool(forKey: Keys.syncEnabled)

        brightnessWriter = makeWriter(VCP.brightness)
        contrastWriter = makeWriter(VCP.contrast)
        volumeWriter = makeWriter(VCP.volume)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                // The LG's DDC often isn't ready yet when the screen first appears, so look again.
                self?.scheduleRefresh(after: 1.5)
            }
        }
        // The transport goes stale over sleep, and the LG takes a moment to answer after wake.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh(after: 2) }
        }
        // Opening the window is when Anh looks; don't make him wait for the next retry.
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.connected else { return }
                self.refresh()
            }
        }
        refresh()

        keyTap.model = self
        keyTap.softwareBrightness = softwareBrightness
        if (keysEnabled || splitEnabled) && !accessibilityTrusted { Accessibility.prompt() }
        recheckAccessibility()
        // Resuming after a relaunch keeps the stored offset: the LG isn't read yet, so there is
        // nothing to capture, and the first poll once it answers applies the offset.
        if syncEnabled { startSyncTimer() }
    }

    private func makeWriter(_ code: UInt8) -> LatestValueWriter<UInt16> {
        LatestValueWriter(queue: queue, interval: 0.1) { [weak self] value in
            // Runs on `queue`. A dropped slider write is harmless; the next refresh shows the truth.
            try? self?.ddc?.write(code, value: value)
        }
    }

    // MARK: Reading

    func refresh() {
        // Repeated requests would otherwise queue up seconds of timeouts; the coalescer folds any
        // made mid-refresh into one rerun, so a hot-plug during a slow refresh isn't lost.
        guard refreshCoalescer.request() else { return }
        refreshing = true
        queue.async { [weak self] in
            guard let self else { return }
            // Find the transport again each time: it goes stale after hot-plug or sleep.
            let transport = findExternalTransport()
            let controller = transport.map { DDCController(transport: $0) }
            self.ddc = controller
            let readout = controller.map { c in MonitorReadout.read { try c.read($0) } }
            // Not DDC, but an IORegistry walk: keep it off the main thread too. Publishing it here
            // lets the header recover when the LG shows up after launch.
            let details = DisplayDetailsReader.read()
            DispatchQueue.main.async {
                self.details = details
                self.lgName = details?.edid?.name ?? Self.defaultLGName
                self.applyAutomaticCommand(manufacturerID: details?.edid?.manufacturerID)
                self.apply(hasTransport: transport != nil, readout: readout)
                self.refreshing = false
                if self.refreshCoalescer.finished() {
                    self.refresh()
                } else {
                    self.retryIfDisconnected()
                }
            }
        }
    }

    /// Debounced: a newer request replaces a pending one, so a burst of notifications costs one refresh.
    private func scheduleRefresh(after delay: TimeInterval) {
        delayedRefresh?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.delayedRefresh = nil
                self?.refresh()
            }
        }
        delayedRefresh = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// The LG doesn't always post a screen change when it changes input, so one failed refresh
    /// would otherwise leave "not connected" up for good. A delayed refresh already pending (after
    /// a wake or a switch) does the same job, so it isn't replaced and retries never stack.
    private func retryIfDisconnected() {
        guard !connected else {
            failedRefreshes = 0
            return
        }
        failedRefreshes += 1
        guard delayedRefresh == nil else { return }
        scheduleRefresh(after: RetryPolicy.delay(afterFailures: failedRefreshes))
    }

    private func apply(hasTransport: Bool, readout: MonitorReadout?) {
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

    /// The manual path (slider, menu bar, keys). While following the MacBook, the new difference
    /// becomes the offset. Sync writes go through `applySync` instead, which never touches it.
    func setBrightness(_ value: Double) {
        brightness = value
        let wire = UInt16(value.rounded())
        brightnessWriter.submit(wire)
        guard syncEnabled else { return }
        follower.manualChange(lg: wire, builtIn: BuiltInBrightness.read(), maximum: syncMaximum)
        publishOffset()
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

    /// With nothing ever saved, the first screen of each maker picks the command that suits it.
    /// Assigning always persists, so only assign when the value changes.
    private func applyAutomaticCommand(manufacturerID: String?) {
        guard commandIsAutomatic, let m = manufacturerID, seenManufacturers.insert(m).inserted else { return }
        let auto = InputConfig.defaults(for: .automatic(manufacturerID: m))
        guard auto != inputConfig else { return }
        applyingAutomaticCommand = true
        inputConfig = auto
        applyingAutomaticCommand = false
    }

    func switchTo(_ input: Input) {
        if input != macPort { recordSoundOutput() }
        if WindowPlacement.shouldMoveOff(target: input, macPort: macPort,
                                         destinationAvailable: ScreenCatalog.windowDestination() != nil) {
            // Leaving the Mac's port blanks the hardware screen, so get every window somewhere visible first.
            WindowShuffler.moveWindowsOffHardwareScreen()
        }
        let value = inputConfig.value(for: input)
        let command = inputConfig.command
        queue.async { [weak self] in
            guard let self else { return }
            let outcome = ReconnectingWrite.run(
                current: self.ddc,
                rediscover: { findExternalTransport().map { DDCController(transport: $0) } },
                write: { try $0.write(command.vcp, value: value, dataAddress: command.dataAddress) })
            self.ddc = outcome.controller
            DispatchQueue.main.async {
                // Only record the input once the LG took it; otherwise the UI would claim a switch
                // that never happened. A refresh shows the user the LG is unreachable.
                if outcome.succeeded {
                    // Back on the Mac input, or found again after being lost: the LG answers DDC
                    // again only once it has settled on the new input, so read it then.
                    if !self.connected || input == self.macPort { self.scheduleRefresh(after: 1.75) }
                    if input == self.macPort {
                        WindowShuffler.restoreWindows()
                        self.restoreSoundOutput()
                    }
                    self.lastInput = input
                } else {
                    // The LG never left the Mac, so the moved windows belong back on it now.
                    if input != self.macPort { WindowShuffler.restoreWindows() }
                    self.refresh()
                }
            }
        }
    }

    // MARK: Sound output

    /// Called before leaving the Mac input, while the LG's audio device still exists. Leaving one
    /// non-Mac input for another keeps what was recorded when the Mac was left: by then macOS has
    /// already fallen back to the MacBook speakers.
    private func recordSoundOutput() {
        lgWasSoundOutput = AudioRestore.lgWasOutput(previous: lgWasSoundOutput,
                                                    currentIsLG: AudioOutput.lgIsSoundOutput(lgName: lgName),
                                                    leavingFromMac: lastInput == macPort,
                                                    restorePending: audioRestoreTimer != nil)
        audioRestoreTimer?.invalidate()
        audioRestoreTimer = nil
    }

    /// The LG's audio device comes back a moment after the switch, so poll for it for a while.
    private func restoreSoundOutput() {
        audioRestoreTimer?.invalidate()
        audioRestoreTimer = nil
        guard lgWasSoundOutput else { return }
        var attempts = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                attempts += 1
                let device = AudioOutput.lgDeviceID(lgName: self.lgName)
                let currentIsLG = AudioOutput.lgIsSoundOutput(lgName: self.lgName)
                let currentIsBuiltIn = AudioOutput.currentIsBuiltIn()
                let restore = AudioRestore.shouldRestore(lgWasOutput: self.lgWasSoundOutput,
                                                         lgDeviceAvailable: device != nil,
                                                         currentIsLG: currentIsLG, currentIsBuiltIn: currentIsBuiltIn)
                // A failed set leaves it unsettled, so the next tick tries again within the 10 s.
                let restored = restore && device.map(AudioOutput.setDefaultOutput) == true
                // Done once the sound is sorted one way or another: restored, macOS went back to the
                // LG by itself, Anh picked another output, or 10 s passed without the LG appearing.
                // No default device at all is macOS mid-change, not a choice.
                let userPicked = !currentIsLG && !currentIsBuiltIn && AudioOutput.defaultOutputName() != nil
                let settled = restored || currentIsLG || userPicked
                guard settled || attempts >= 20 else { return }
                timer.invalidate()
                self.audioRestoreTimer = nil
                self.lgWasSoundOutput = false
            }
        }
        audioRestoreTimer = timer
    }

    // MARK: Following the MacBook

    /// Zero while the LG isn't answering, which makes the follower write nothing.
    private var syncMaximum: UInt16 {
        guard connected else { return 0 }
        return raw[VCP.brightness]?.maximum ?? 0
    }

    private func updateSync(turningOn: Bool) {
        guard turningOn else {
            syncTimer?.invalidate()
            syncTimer = nil
            return
        }
        // Capture the current difference first so turning on doesn't make the LG jump.
        let write = follower.enable(lg: Stepper.wireValue(brightness), builtIn: BuiltInBrightness.read(),
                                    maximum: syncMaximum)
        publishOffset()
        if let write, write != Stepper.wireValue(brightness) { applySync(target: write) }
        startSyncTimer()
    }

    private func startSyncTimer() {
        guard syncTimer == nil else { return }
        // The built-in read is a cheap local call, so polling on the main thread is fine; the DDC
        // write still goes through the writer on the DDC queue.
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollBuiltIn() }
        }
        timer.tolerance = 0.1
        syncTimer = timer
    }

    private func pollBuiltIn() {
        guard syncEnabled,
              let write = follower.poll(builtIn: BuiltInBrightness.read(), maximum: syncMaximum) else { return }
        applySync(target: write)
    }

    /// Sets the offset to 0 and, while following, applies the plain MacBook level straight away.
    func resetSyncOffset() {
        let write = follower.reset(builtIn: syncEnabled ? BuiltInBrightness.read() : nil, maximum: syncMaximum)
        publishOffset()
        if let write { applySync(target: write) }
    }

    /// Never recomputes the offset: a clamped write would otherwise wear it away.
    private func applySync(target: UInt16) {
        brightness = Double(target)
        brightnessWriter.submit(target)
    }

    private func publishOffset() {
        if syncOffset != follower.offset { syncOffset = follower.offset }
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

    /// Starts or stops everything that needs Accessibility: the key tap and the screen split.
    private func updateKeyTap() {
        keyTapRetry?.invalidate()
        keyTapRetry = nil
        if keysEnabled && accessibilityTrusted {
            startKeyTap(retriesLeft: 5)
        } else {
            keyTap.stop()
            keyTapActive = false
        }
        if splitEnabled && accessibilityTrusted { dragMonitor.start() } else { dragMonitor.stop() }
    }

    /// Creating the tap can fail briefly right after the Accessibility grant, before macOS has
    /// caught up, so give it a few more tries before telling Anh.
    private func startKeyTap(retriesLeft: Int) {
        keyTapActive = keyTap.start()
        guard !keyTapActive, retriesLeft > 0 else { return }
        keyTapRetry = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.keysEnabled, self.accessibilityTrusted else { return }
                self.keyTapRetry = nil
                self.startKeyTap(retriesLeft: retriesLeft - 1)
            }
        }
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
        guard let screen = ScreenCatalog.hardwareScreen() else { return }
        hud.show(kind, level: level, on: screen)
    }

    // MARK: Details

    func loadDetails(forceCapabilities: Bool = false) {
        // An IORegistry walk: not DDC, but slow enough to keep off the main thread.
        queue.async { [weak self] in
            let details = DisplayDetailsReader.read()
            DispatchQueue.main.async { self?.details = details }
        }
        if forceCapabilities {
            capabilities = nil
            capabilitiesRaw = nil
            capabilitiesError = nil
        }
        // A capabilities fetch takes seconds, so keep the first good one.
        guard capabilities == nil, !loadingCapabilities else { return }
        loadingCapabilities = true
        queue.async { [weak self] in
            guard let self else { return }
            if self.ddc == nil { self.ddc = findExternalTransport().map { DDCController(transport: $0) } }
            let result: Result<String, Error>
            if let ddc = self.ddc {
                result = Result { try ddc.capabilities() }
            } else {
                result = .failure(DDCError.noReply(code: 0xF3))
            }
            DispatchQueue.main.async {
                self.loadingCapabilities = false
                switch result {
                case .success(let text):
                    self.capabilitiesRaw = text
                    self.capabilities = Capabilities.parse(text)
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
