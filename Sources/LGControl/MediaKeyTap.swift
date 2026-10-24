import AppKit
import CoreGraphics
import LGKit

/// Intercepts the brightness and volume keys and hands the LG's share of them to `MonitorModel`.
///
/// Runs on the main run loop, so the callback is on the main thread and can read the model
/// synchronously: it must answer "swallow or pass on" before it returns.
@MainActor
final class MediaKeyTap {
    weak var model: MonitorModel?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var gate = MediaKeyGate()

    var isRunning: Bool { tap != nil }

    /// Needs Accessibility: an active (not listen-only) tap fails to create without it.
    /// Returns whether the tap is running afterwards.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let systemDefined = CGEventType(rawValue: 14)!   // NX_SYSDEFINED, which CGEventType doesn't name
        let mask = (CGEventMask(1) << systemDefined.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: mediaKeyTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            NSLog("LG Control: couldn’t create the key tap (Accessibility not granted?)")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
        gate = MediaKeyGate()
    }

    /// Returns true when the event should be swallowed.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // macOS turns a slow tap off; turn it straight back on or the keys stop working.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard let model, let key = decode(type: type, event: event) else { return false }

        let flags = event.flags
        let modifiers = KeyRouter.modifiersAllowHandling(
            option: flags.contains(.maskAlternate), shift: flags.contains(.maskShift),
            control: flags.contains(.maskControl), command: flags.contains(.maskCommand))
        let action = gate.decide(key, modifiers: modifiers, canHandle: model.canHandleMediaKey(key.key)) {
            KeyRouter.route(key.key,
                            pointerOnLG: Self.pointerOnLG(),
                            // Only the volume keys need CoreAudio; skip the lookup for brightness.
                            lgIsSoundOutput: key.key.isAudio && AudioOutput.lgIsSoundOutput(lgName: model.lgName),
                            lgConnected: model.connected)
        }
        switch action {
        case .passThrough: return false
        case .swallow: return true
        case .handle(let fine):
            model.handleMediaKey(key, fine: fine)
            return true
        }
    }

    private func decode(type: CGEventType, event: CGEvent) -> MediaKeyEvent? {
        switch type {
        case .keyDown, .keyUp:
            return MediaKeyEvent.decode(keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                                        isDown: type == .keyDown,
                                        isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        default:
            // Only systemDefined events have a subtype; NSEvent raises if asked for any other type.
            guard type.rawValue == 14, let ns = NSEvent(cgEvent: event) else { return nil }
            return MediaKeyEvent.decode(subtype: ns.subtype.rawValue, data1: ns.data1)
        }
    }

    static func lgScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return false }
            return CGDisplayIsBuiltin(CGDirectDisplayID(id.uint32Value)) == 0
        }
    }

    private static func pointerOnLG() -> Bool {
        guard let screen = lgScreen() else { return false }
        return NSMouseInRect(NSEvent.mouseLocation, screen.frame, false)
    }
}

private extension MediaKey {
    var isAudio: Bool {
        switch self {
        case .volumeUp, .volumeDown, .mute: return true
        case .brightnessUp, .brightnessDown: return false
        }
    }
}

/// A C callback can't capture anything, so the tap object travels in `userInfo`.
private func mediaKeyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MediaKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
    // The run loop source is on the main run loop, so this is already the main thread.
    let swallow = MainActor.assumeIsolated { tap.handle(type: type, event: event) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
