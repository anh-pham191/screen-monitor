public enum WindowPlacement {
    /// Leaving the Mac's port blanks the external display, which would strand windows on it.
    public static func shouldMoveOff(target: Input, macPort: Input, destinationAvailable: Bool) -> Bool {
        target != macPort && destinationAvailable
    }
}
