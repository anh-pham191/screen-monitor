/// Whether the app shows in the Dock. The app is a menu bar app by default.
public enum DockPolicy {
    /// UserDefaults key (Bool, default false).
    public static let defaultsKey = "showInDock"

    /// `true` for the regular activation policy (Dock icon), `false` for accessory (menu bar only).
    public static func isRegular(showInDock: Bool) -> Bool { showInDock }
}
