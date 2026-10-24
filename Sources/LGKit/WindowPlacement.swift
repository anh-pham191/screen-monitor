public enum WindowPlacement {
    /// Leaving the Mac input blanks the external display, which would strand the window on it.
    public static func shouldMoveToBuiltIn(target: Input, windowOnExternal: Bool, builtInAvailable: Bool) -> Bool {
        target != .mac && windowOnExternal && builtInAvailable
    }

    /// The all-windows path: which windows are on the LG is decided per window while moving them,
    /// so only the input and the MacBook screen matter here.
    public static func shouldMoveToBuiltIn(target: Input, builtInAvailable: Bool) -> Bool {
        shouldMoveToBuiltIn(target: target, windowOnExternal: true, builtInAvailable: builtInAvailable)
    }
}
