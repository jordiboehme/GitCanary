import SwiftUI

@main
struct GitCanaryApp: App {
    @State private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            if appState.isPaused {
                Image(systemName: "pause.circle")
            } else {
                Image("MenuBarIcon")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }

    init() {
        appState.start()
    }
}
