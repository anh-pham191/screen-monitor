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
}
