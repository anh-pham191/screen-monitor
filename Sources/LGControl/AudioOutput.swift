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
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }

        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioObjectPropertyName
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let name else { return nil }
        return name.takeRetainedValue() as String
    }
}
