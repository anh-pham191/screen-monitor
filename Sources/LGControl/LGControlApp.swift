import AppKit
import SwiftUI
import LGKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // The menu bar icon should outlive the main window.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
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
