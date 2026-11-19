import SwiftUI
import SweepCore

struct SweepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // The App value lives for the whole run, so a plain reference is enough
    // (and avoids SwiftUI's @State macro, which Command Line Tools doesn't ship).
    private let model = Model()

    var body: some Scene {
        Window("Sweep", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 940, height: 640)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the weekly job pointing at this copy if the app was moved (off the main thread).
        let executable = CLI.executable
        Task.detached(priority: .utility) { Schedule.repair(executable: executable) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
