import CoreAudio
import Foundation

/// Whether the volume keys belong to the LG: only when macOS is sending sound to it.
enum AudioOutput {
    /// An exact match on the EDID name. A loose "contains LG" match would also catch LG headphones
    /// or another LG screen, and then the keys would silently change the wrong device.
    static func lgIsSoundOutput(lgName: String) -> Bool {
        defaultOutputName() == lgName
    }

    static func defaultOutputName() -> String? {
        defaultOutputDevice().flatMap(name(of:))
    }

    /// The LG's audio device, if macOS currently has it. It disappears while the LG shows another
    /// input and comes back a moment after the switch back to the Mac.
    static func lgDeviceID(lgName: String) -> AudioObjectID? {
        var size: UInt32 = 0
        var address = globalAddress(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        var devices = [AudioObjectID](repeating: kAudioObjectUnknown, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return nil }
        return devices.first { name(of: $0) == lgName && hasOutput($0) }
    }

    /// True when macOS fell back to the MacBook's own speakers (or headphone jack).
    static func currentIsBuiltIn() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = globalAddress(kAudioDevicePropertyTransportType)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBuiltIn
    }

    /// Sets both the output and the alert sound device, as choosing it in Sound settings does.
    @discardableResult
    static func setDefaultOutput(_ device: AudioObjectID) -> Bool {
        var ok = true
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
            var device = device
            var address = globalAddress(selector)
            let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                                    UInt32(MemoryLayout<AudioObjectID>.size), &device)
            if status != noErr {
                NSLog("LG Control: couldn’t set the sound output (OSStatus %d)", status)
                ok = false
            }
        }
        return ok
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = globalAddress(kAudioHardwarePropertyDefaultOutputDevice)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func name(of device: AudioObjectID) -> String? {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = globalAddress(kAudioObjectPropertyName)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let name else { return nil }
        return name.takeRetainedValue() as String
    }

    /// A device with the same name but no output streams can't take the sound.
    private static func hasOutput(_ device: AudioObjectID) -> Bool {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func globalAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
