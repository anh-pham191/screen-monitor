import AppKit
import SwiftUI
import LGKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the App's init, so quitting can release the power assertions. Static because the
    /// delegate adaptor's instance isn't reachable from there.
    static var keepAwake: KeepAwakeModel?
    /// Set by the App's init with the models in place; the menu bar panel is built from it once
    /// AppKit has finished launching.
    static var makeMenuBarPanel: (() -> MenuBarPanel)?
    private var menuBarPanel: MenuBarPanel?

    // The menu bar icon should outlive the main window.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppPresentation.applyDockPolicy(showInDock: UserDefaults.standard.bool(forKey: DockPolicy.defaultsKey))
        menuBarPanel = Self.makeMenuBarPanel?()
        // SwiftUI opens the first Window scene at launch, and `defaultLaunchBehavior(.suppressed)`
        // can't be applied conditionally (macOS 15 only; SceneBuilder has no else). Close it
        // before it is drawn so only the menu bar icon appears, including at login.
        DispatchQueue.main.async {
            for window in NSApp.windows where !(window is NSPanel) && window.identifier?.rawValue.contains("main") == true {
                window.close()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.keepAwake?.assertion.release()
    }
}

@main
struct LGControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: MonitorModel
    @StateObject private var softwareBrightness: SoftwareBrightness
    @StateObject private var keepAwake: KeepAwakeModel

    init() {
        // One HUD for both, so a hardware and a software key press never show two indicators.
        // The remembered hardware screen first, so no overlay lands on it at launch.
        ScreenCatalog.load(from: .standard)
        let hud = HUD()
        let s = SoftwareBrightness(defaults: .standard, hud: hud)
        _softwareBrightness = StateObject(wrappedValue: s)
        let m = MonitorModel(defaults: .standard, softwareBrightness: s, hud: hud)
        _model = StateObject(wrappedValue: m)
        let k = KeepAwakeModel(monitor: m)
        _keepAwake = StateObject(wrappedValue: k)
        AppDelegate.keepAwake = k
        AppDelegate.makeMenuBarPanel = {
            MenuBarPanel(keepAwake: k) {
                MenuBarContent().environmentObject(m).environmentObject(s).environmentObject(k)
            }
        }
    }

    var body: some Scene {
        Window("Screen Monitor", id: "main") {
            ContentView().environmentObject(model).environmentObject(softwareBrightness)
        }
        .windowResizability(.contentSize)

        Window("Details", id: "details") {
            DetailsView().environmentObject(model)
        }

        Settings {
            SettingsView().environmentObject(model).environmentObject(softwareBrightness).environmentObject(keepAwake)
        }
    }
}

