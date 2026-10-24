import Foundation
import IOKit.ps

enum PowerSource {
    /// Any failure reads as plugged in with no level, so the battery rule never fires on a
    /// desktop or when macOS can't say.
    static func read() -> (onBattery: Bool, percent: Int?) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return (false, nil) }
        let providing = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?
        let onBattery = providing == kIOPSBatteryPowerValue

        var percent: Int?
        let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for ps in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = info[kIOPSCurrentCapacityKey] as? Int,
                  let max = info[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            percent = Int((Double(current) / Double(max) * 100).rounded())
            break
        }
        return (onBattery, percent)
    }
}
