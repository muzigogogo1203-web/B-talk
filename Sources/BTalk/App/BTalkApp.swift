import SwiftUI

@main
struct BTalkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appDelegate: appDelegate)
        } label: {
            Image(systemName: appDelegate.appState.isRecording ? "mic.fill" : "mic")
        }

        Settings {
            SettingsView()
        }

        WindowGroup("Library", id: "library") {
            LibraryView()
        }
        .defaultSize(width: 700, height: 500)
        .commandsRemoved()
    }
}
