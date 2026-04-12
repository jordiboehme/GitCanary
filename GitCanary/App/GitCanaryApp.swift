import SwiftUI
import UserNotifications

@main
struct GitCanaryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.shared
    @State private var windowState = SummaryWindowState.shared
    @Environment(\.openWindow) private var openWindow

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

        Window("Summary", id: "summary-detail") {
            SummaryDetailView()
                .environment(appState)
        }
        .defaultSize(width: 700, height: 500)
    }

    init() {
        appState.start()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        AppState.shared.requestNotificationPermission()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if let repoIDString = userInfo["repositoryID"] as? String,
           let repoID = UUID(uuidString: repoIDString)
        {
            let summaryID = (userInfo["summaryID"] as? String).flatMap(UUID.init(uuidString:))

            DispatchQueue.main.async {
                SummaryWindowState.shared.requestOpen(repoID: repoID, summaryID: summaryID)
                self.openSummaryWindow()
            }
        }

        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func openSummaryWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.title == "Summary" {
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}
