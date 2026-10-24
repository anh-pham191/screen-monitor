import AppKit
import SwiftUI
import LGKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // The menu bar icon should outlive the main window.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppPresentation.applyDockPolicy(showInDock: UserDefaults.standard.bool(forKey: DockPolicy.defaultsKey))
        // SwiftUI opens the first Window scene at launch, and `defaultLaunchBehavior(.suppressed)`
        // can't be applied conditionally (macOS 15 only; SceneBuilder has no else). Close it
        // before it is drawn so only the menu bar icon appears, including at login.
        DispatchQueue.main.async {
            for window in NSApp.windows where !(window is NSPanel) && window.identifier?.rawValue.contains("main") == true {
                window.close()
            }
        }
    }
}

@main
struct LGControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = MonitorModel()

    var body: some Scene {
        Window("Screen Monitor", id: "main") {
            ContentView().environmentObject(model)
        }
        .windowResizability(.contentSize)

        Window("Details", id: "details") {
            DetailsView().environmentObject(model)
        }

        Settings {
            SettingsView().environmentObject(model)
        }

        // The window style is needed for sliders; the default menu style can't host them.
        MenuBarExtra("Screen Monitor", systemImage: "display") {
            MenuBarContent().environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}
