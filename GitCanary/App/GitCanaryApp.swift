import SwiftUI

@main
struct GitCanaryApp: App {
    var body: some Scene {
        MenuBarExtra {
            ContentView()
        } label: {
            Image(systemName: "bird")
        }
        .menuBarExtraStyle(.window)

        Settings {
            Text("GitCanary Settings")
                .frame(width: 400, height: 300)
        }
    }
}
