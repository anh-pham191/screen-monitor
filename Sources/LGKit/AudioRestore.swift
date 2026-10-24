/// Whether to hand the sound back to the LG after returning to the Mac input.
///
/// macOS loses the LG's HDMI audio while the LG shows another input and falls back to the MacBook
/// speakers, then doesn't return to the LG. Only that exact fallback is undone: any other output
/// means Anh picked it on purpose.
public enum AudioRestore {
    public static func shouldRestore(lgWasOutput: Bool, lgDeviceAvailable: Bool,
                                     currentIsLG: Bool, currentIsBuiltIn: Bool) -> Bool {
        lgWasOutput && lgDeviceAvailable && !currentIsLG && currentIsBuiltIn
    }

    /// What to remember about the sound output when leaving the Mac input, before the LG's audio
    /// device goes away. Leaving one other input for another keeps the earlier answer: macOS has
    /// already fallen back to the MacBook by then. So does leaving the Mac again while a restore
    /// is still waiting for the LG's device, because the sound hasn't been handed back yet.
    public static func lgWasOutput(previous: Bool, currentIsLG: Bool,
                                   leavingFromMac: Bool, restorePending: Bool) -> Bool {
        if currentIsLG { return true }
        if restorePending { return previous }
        return leavingFromMac ? false : previous
    }
}
