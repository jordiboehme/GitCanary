import SwiftUI

@main
struct GitCanaryApp: App {
    @State private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }

    private var menuBarIcon: String {
        if appState.isPaused {
            return "bird.slash"
        }
        let hasChanges = appState.repositories.contains {
            if case .hasChanges = $0.status { return true }
            return false
        }
        return hasChanges ? "bird.fill" : "bird"
    }

    init() {
        appState.start()
    }
}
