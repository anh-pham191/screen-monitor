import AppKit
import ApplicationServices

/// The key tap (and later the screen split) needs Accessibility. macOS ties the grant to the code
/// signature, which is why build-app.sh signs with a stable local certificate.
enum Accessibility {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static func isTrusted() -> Bool { AXIsProcessTrusted() }

    /// Shows the system dialog and adds the app to the Accessibility list, so Anh only has to tick it.
    @discardableResult
    static func prompt() -> Bool {
        // The constant is a global `var` in the SDK; its value is fixed, so spell it out.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() { NSWorkspace.shared.open(settingsURL) }
}
