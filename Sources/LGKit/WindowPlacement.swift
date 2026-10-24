public enum WindowPlacement {
    /// Leaving the Mac input blanks the external display, which would strand the window on it.
    public static func shouldMoveToBuiltIn(target: Input, windowOnExternal: Bool, builtInAvailable: Bool) -> Bool {
        target != .mac && windowOnExternal && builtInAvailable
    }
}
