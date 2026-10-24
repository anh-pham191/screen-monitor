import Foundation
import IOKit.pwr_mgt

/// Holds both "prevent idle sleep" assertions, so the screens and the Mac stay awake together.
final class PowerAssertion {
    private static let name = "Screen Monitor: Keep Awake" as CFString

    // 0 means "not held", so a partial create failure leaves the other one retryable.
    private var displayID: IOPMAssertionID = 0
    private var systemID: IOPMAssertionID = 0
    private var reason: String?

    var isHeld: Bool { displayID != 0 || systemID != 0 }

    /// Idempotent: a second hold doesn't create more assertions; it only retries a missing one.
    /// A new reason is written onto the held assertions so `pmset -g assertions` stays current.
    func hold(reason: String) {
        if reason != self.reason {
            for id in [displayID, systemID] where id != 0 {
                IOPMAssertionSetProperty(id, kIOPMAssertionDetailsKey as CFString, reason as CFString)
            }
            self.reason = reason
        }
        if displayID == 0 {
            displayID = Self.create(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, reason: reason)
        }
        if systemID == 0 {
            systemID = Self.create(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, reason: reason)
        }
    }

    func release() {
        if displayID != 0 {
            IOPMAssertionRelease(displayID)
            displayID = 0
        }
        if systemID != 0 {
            IOPMAssertionRelease(systemID)
            systemID = 0
        }
        reason = nil
    }

    deinit { release() }

    private static func create(_ type: CFString, reason: String) -> IOPMAssertionID {
        var id: IOPMAssertionID = 0
        guard IOPMAssertionCreateWithName(type, IOPMAssertionLevel(kIOPMAssertionLevelOn), name, &id)
                == kIOReturnSuccess else { return 0 }
        // The fixed name is what `pmset -g assertions` greps for; the reason says why it's held.
        IOPMAssertionSetProperty(id, kIOPMAssertionDetailsKey as CFString, reason as CFString)
        return id
    }
}
