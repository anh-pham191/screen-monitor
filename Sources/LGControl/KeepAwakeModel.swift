import AppKit
import Combine
import Foundation
import LGKit

/// Wires `KeepAwakePolicy` to the clock, the battery, the LG's input and the power assertions.
/// The decisions themselves live in LGKit, where they're tested.
@MainActor
final class KeepAwakeModel: ObservableObject {
    private enum Keys {
        static let ps5 = "keepAwakePS5"
        static let threshold = "keepAwakeBatteryThreshold"
    }

    @Published private(set) var timerEnd: Date?
    @Published private(set) var activePreset: KeepAwakePreset?
    @Published private(set) var decision: KeepAwakeDecision = .idle
    @Published private(set) var lastStop: KeepAwakeStop?
    /// Published apart from `decision` and only on change, so the menu bar label redraws
    /// when its text changes rather than every second.
    @Published private(set) var badgeText: String?
    @Published var ps5RuleOn: Bool {
        didSet {
            defaults.set(ps5RuleOn, forKey: Keys.ps5)
            evaluate()
        }
    }
    @Published var batteryThreshold: Int {
        didSet {
            let clamped = KeepAwakePolicy.clampThreshold(batteryThreshold)
            if clamped != batteryThreshold { batteryThreshold = clamped; return }
            defaults.set(batteryThreshold, forKey: Keys.threshold)
            evaluate()
        }
    }

    let assertion = PowerAssertion()
    private let monitor: MonitorModel
    private let defaults = UserDefaults.standard
    private var ps5Since: Date?
    private var tick: Timer?
    private var inputSink: AnyCancellable?
    private var wakeObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    init(monitor: MonitorModel) {
        self.monitor = monitor
        ps5RuleOn = defaults.object(forKey: Keys.ps5) as? Bool ?? true
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
        let ps5Showing = input == .ps5
        ps5Since = KeepAwakeState.nextPS5Since(current: ps5Since, ps5Showing: ps5Showing, now: now)
        let power = PowerSource.read()

        let d = KeepAwakePolicy.evaluate(KeepAwakeInputs(
            timerEnd: timerEnd, now: now, ps5Showing: ps5Showing, ps5RuleOn: ps5RuleOn,
            onBattery: power.onBattery, batteryPercent: power.percent,
            batteryThreshold: batteryThreshold, ps5Since: ps5Since))

        if d.hold {
            assertion.hold(reason: d.reason == .ps5 ? "The LG is showing the PS5" : "Keep Awake timer")
        } else {
            assertion.release()
        }
        if d.clearTimer { clearTimer() }
        let nextStop = KeepAwakeState.nextLastStop(current: lastStop, decision: d)
        if nextStop != lastStop { lastStop = nextStop }
        if d != decision { decision = d }
        let badge = KeepAwakeState.badgeText(for: d)
        if badge != badgeText { badgeText = badge }

        updateTick(ps5Showing: ps5Showing, now: now)
    }

    private func clearTimer() {
        timerEnd = nil
        activePreset = nil
    }

    private func updateTick(ps5Showing: Bool, now: Date) {
        let needed = KeepAwakeState.needsTick(timerEnd: timerEnd, ps5RuleOn: ps5RuleOn,
                                              ps5Showing: ps5Showing, ps5Since: ps5Since, now: now)
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
