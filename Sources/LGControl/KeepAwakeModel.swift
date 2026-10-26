import AppKit
import Combine
import Foundation
import LGKit

/// Wires `KeepAwakePolicy` to the clock, the battery, the LG's input and the power assertions.
/// The decisions themselves live in LGKit, where they're tested.
@MainActor
final class KeepAwakeModel: ObservableObject {
    private enum Keys {
        static let away = "keepAwakePS5"
        static let threshold = "keepAwakeBatteryThreshold"
    }

    @Published private(set) var timerEnd: Date?
    @Published private(set) var activePreset: KeepAwakePreset?
    @Published private(set) var decision: KeepAwakeDecision = .idle
    @Published private(set) var lastStop: KeepAwakeStop?
    /// Published apart from `decision` and only on change, so the menu bar label redraws
    /// when its text changes rather than every second.
    @Published private(set) var badgeText: String?
    @Published var awayRuleOn: Bool {
        didSet {
            defaults.set(awayRuleOn, forKey: Keys.away)
            evaluate()
        }
    }
    @Published var batteryThreshold: Int {
        didSet {
            // Assigning inside didSet doesn't call didSet again, so the clamped value has to be
            // persisted and evaluated here rather than on a second pass that never comes.
            let clamped = KeepAwakePolicy.clampThreshold(batteryThreshold)
            if clamped != batteryThreshold { batteryThreshold = clamped }
            defaults.set(clamped, forKey: Keys.threshold)
            evaluate()
        }
    }

    let assertion = PowerAssertion()
    private let monitor: MonitorModel
    private let defaults = UserDefaults.standard
    private var awaySince: Date?
    // nonisolated(unsafe) so the nonisolated deinit can clean up: an isolated deinit needs a
    // newer runtime than macOS 14. They're only written on the main actor, and deinit runs
    // once nothing else holds the model, so there's no concurrent access.
    nonisolated(unsafe) private var tick: Timer?
    private var inputSink: AnyCancellable?
    nonisolated(unsafe) private var wakeObserver: NSObjectProtocol?
    nonisolated(unsafe) private var terminateObserver: NSObjectProtocol?

    init(monitor: MonitorModel) {
        self.monitor = monitor
        awayRuleOn = defaults.object(forKey: Keys.away) as? Bool ?? true
        batteryThreshold = KeepAwakePolicy.clampThreshold(defaults.object(forKey: Keys.threshold) as? Int ?? 20)

        // @Published emits in willSet, so the sink must hand the new value in rather than
        // letting evaluate read the old one back from the monitor.
        inputSink = monitor.$lastInput.sink { [weak self] value in
            MainActor.assumeIsolated { self?.evaluate(lastInput: value) }
        }
        // A sleep that happened anyway (lid closed) can outlast the timer; settle up on wake.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        // The app delegate releases too; this covers a quit that skips it. powerd also drops
        // a process's assertions when it exits.
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutDown() }
        }
    }

    deinit {
        // A timer must be invalidated on the thread whose run loop it was added to (main).
        // Timer isn't Sendable, but invalidate is the only call made on it and that's on main.
        if let timer = tick {
            nonisolated(unsafe) let t = timer
            if Thread.isMainThread { t.invalidate() } else { DispatchQueue.main.async { t.invalidate() } }
        }
        if let o = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        if let o = terminateObserver { NotificationCenter.default.removeObserver(o) }
        // `assertion` releases itself in its own deinit.
    }

    func start(_ preset: KeepAwakePreset) {
        timerEnd = Date().addingTimeInterval(preset.duration)
        activePreset = preset
        lastStop = nil
        evaluate()
    }

    func stop() {
        clearTimer()
        lastStop = nil
        evaluate()
    }

    /// `lastInput` overrides the monitor's value for the Combine sink (see init).
    func evaluate(lastInput override: Input?? = nil) {
        let input = override ?? monitor.lastInput
        let now = Date()
        let awayFromMac = input != nil && input != monitor.macPort
        awaySince = KeepAwakeState.nextAwaySince(current: awaySince, awayFromMac: awayFromMac, now: now)
        let power = PowerSource.read()

        let d = KeepAwakePolicy.evaluate(KeepAwakeInputs(
            timerEnd: timerEnd, now: now, awayFromMac: awayFromMac, awayRuleOn: awayRuleOn,
            onBattery: power.onBattery, batteryPercent: power.percent,
            batteryThreshold: batteryThreshold, awaySince: awaySince))

        if d.hold {
            assertion.hold(reason: d.reason == .otherInput ? "The screen is showing another input" : "Keep Awake timer")
        } else {
            assertion.release()
        }
        if d.clearTimer { clearTimer() }
        let nextStop = KeepAwakeState.nextLastStop(current: lastStop, decision: d)
        if nextStop != lastStop { lastStop = nextStop }
        // A running timer's remaining time differs every tick, so this publishes once a second
        // and the card's clock and ring move with it.
        if d != decision { decision = d }
        let badge = KeepAwakeState.badgeText(for: d, port: monitor.lastInput?.label)
        if badge != badgeText { badgeText = badge }

        updateTick(awayFromMac: awayFromMac, now: now)
    }

    private func clearTimer() {
        timerEnd = nil
        activePreset = nil
    }

    private func updateTick(awayFromMac: Bool, now: Date) {
        let needed = KeepAwakeState.needsTick(timerEnd: timerEnd, awayRuleOn: awayRuleOn,
                                              awayFromMac: awayFromMac, awaySince: awaySince, now: now)
        if needed, tick == nil {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
            t.tolerance = 0.2
            // .common keeps the countdown moving while the menu bar panel tracks the mouse.
            RunLoop.main.add(t, forMode: .common)
            tick = t
        } else if !needed, let t = tick {
            t.invalidate()
            tick = nil
        }
    }

    private func shutDown() {
        tick?.invalidate()
        tick = nil
        assertion.release()
    }
}
