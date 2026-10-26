public enum WindowPlacement {
    /// Leaving the Mac's port blanks the external display, which would strand windows on it.
    public static func shouldMoveOff(target: Input, macPort: Input, destinationAvailable: Bool) -> Bool {
        target != macPort && destinationAvailable
    }

    /// Where windows go when the hardware screen leaves the Mac's port, as an index into `kinds`
    /// (screens in `NSScreen.screens` order): the MacBook screen, else (lid closed) the first
    /// screen with software brightness, else nowhere.
    public static func destination(kinds: [ScreenKind]) -> Int? {
        kinds.firstIndex(of: .builtIn) ?? kinds.firstIndex(of: .software)
    }
}
