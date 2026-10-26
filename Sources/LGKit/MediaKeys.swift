import Foundation

public enum MediaKey: Equatable, Sendable { case brightnessUp, brightnessDown, volumeUp, volumeDown, mute }

public struct MediaKeyEvent: Equatable, Sendable {
    public let key: MediaKey
    public let isDown: Bool
    public let isRepeat: Bool

    public init(key: MediaKey, isDown: Bool, isRepeat: Bool) {
        self.key = key; self.isDown = isDown; self.isRepeat = isRepeat
    }

    /// NX_SYSDEFINED media keys: subtype 8; keyCode = (data1 & 0xFFFF0000) >> 16;
    /// state = (data1 & 0xFF00) >> 8 (0x0A down, 0x0B up); repeat = data1 & 0x1.
    public static func decode(subtype: Int16, data1: Int) -> MediaKeyEvent? {
        guard subtype == 8 else { return nil }
        let code = (data1 & 0xFFFF0000) >> 16
        let state = (data1 & 0xFF00) >> 8
        let key: MediaKey
        switch code {
        case 0: key = .volumeUp
        case 1: key = .volumeDown
        case 2: key = .brightnessUp
        case 3: key = .brightnessDown
        case 7: key = .mute
        default: return nil
        }
        guard state == 0x0A || state == 0x0B else { return nil }
        return MediaKeyEvent(key: key, isDown: state == 0x0A, isRepeat: data1 & 0x1 != 0)
    }

    /// Apple Silicon built-in keyboards send brightness as plain key events: 144 up, 145 down.
    public static func decode(keyCode: Int64, isDown: Bool, isRepeat: Bool) -> MediaKeyEvent? {
        switch keyCode {
        case 144: return MediaKeyEvent(key: .brightnessUp, isDown: isDown, isRepeat: isRepeat)
        case 145: return MediaKeyEvent(key: .brightnessDown, isDown: isDown, isRepeat: isRepeat)
        default: return nil
        }
    }
}

/// Who handles a key: the DDC screen, a software-dimmed screen, or macOS.
public enum KeyRoute: Equatable, Sendable { case hardware, software, passThrough }

public enum KeyRouter {
    /// - Parameter pointerScreen: the kind of screen under the pointer, nil when it's on none.
    public static func route(_ key: MediaKey, pointerScreen: ScreenKind?, hardwareIsSoundOutput: Bool,
                             hardwareConnected: Bool) -> KeyRoute {
        switch key {
        case .brightnessUp, .brightnessDown:
            // A software screen needs no DDC, so it works whatever the hardware screen is doing.
            if pointerScreen == .software { return .software }
            return pointerScreen == .hardware && hardwareConnected ? .hardware : .passThrough
        case .volumeUp, .volumeDown, .mute:
            return hardwareConnected && hardwareIsSoundOutput ? .hardware : .passThrough
        }
    }

    /// Same shortcuts as a normal Mac: no modifiers handles normally, exactly option+shift
    /// handles with quarter steps; anything else passes through so macOS shortcuts keep working.
    public static func modifiersAllowHandling(option: Bool, shift: Bool, control: Bool, command: Bool) -> (handle: Bool, fine: Bool) {
        if control || command { return (false, false) }
        switch (option, shift) {
        case (false, false): return (true, false)
        case (true, true): return (true, true)
        default: return (false, false)
        }
    }
}

public enum Stepper {
    /// Step boundaries b(k) = round(k * maximum / n), k = 0...n (n = 16, or 64 when fine).
    public static func step(current: UInt16, maximum: UInt16, up: Bool, fine: Bool) -> UInt16 {
        guard maximum > 0 else { return current }
        let n = fine ? 64 : 16
        let bounds = (0...n).map { UInt16((Double($0) * Double(maximum) / Double(n)).rounded()) }
        if up { return bounds.first { $0 > current } ?? maximum }
        return bounds.last { $0 < current } ?? 0
    }
}
