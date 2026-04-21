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
            Group {
                if appState.isPaused {
                    Image(systemName: "bird.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                } else if appState.repositories.contains(where: { $0.status == .summarizing }) {
                    Image(systemName: "bird.fill")
                        .symbolEffect(.pulse)
                } else {
                    Image(systemName: "bird.fill")
                }
            }
            .background { SettingsCapture() }
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

/// Invisible helper placed in the MenuBarExtra label so it mounts at launch.
/// Captures the SwiftUI openSettings action into SettingsNavigator so
/// AppDelegate (which has no SwiftUI env) can open the Settings scene.
struct SettingsCapture: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                SettingsNavigator.shared.openSettingsAction = openSettings
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItemRightClickMonitor: Any?
    private var dropView: StatusBarDropView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        AppState.shared.requestNotificationPermission()
        installStatusItemRightClickMonitor()
        DispatchQueue.main.async { [weak self] in
            self?.installDropTarget()
        }
    }

    deinit {
        if let monitor = statusItemRightClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func installStatusItemRightClickMonitor() {
        statusItemRightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self else { return event }
            guard let window = event.window else { return event }
            if String(describing: type(of: window)).contains("StatusBar") {
                DispatchQueue.main.async { self.openSummaryWindow() }
                return nil
            }
            return event
        }
    }

    private func installDropTarget() {
        guard let button = findStatusBarButton() else { return }
        let drop = StatusBarDropView(frame: button.bounds)
        drop.autoresizingMask = [.width, .height]
        drop.onDrop = { [weak self] urls in
            DispatchQueue.main.async { self?.handleDrop(urls: urls) }
        }
        button.addSubview(drop)
        dropView = drop
    }

    private func findStatusBarButton() -> NSStatusBarButton? {
        for window in NSApp.windows
            where String(describing: type(of: window)).contains("StatusBar")
        {
            guard let content = window.contentView else { continue }
            if let button = content as? NSStatusBarButton { return button }
            if let button = findStatusBarButton(in: content) { return button }
        }
        return nil
    }

    private func findStatusBarButton(in view: NSView) -> NSStatusBarButton? {
        for sub in view.subviews {
            if let button = sub as? NSStatusBarButton { return button }
            if let button = findStatusBarButton(in: sub) { return button }
        }
        return nil
    }

    @MainActor
    func handleDrop(urls: [URL]) {
        let added = AppState.shared.addRepositories(from: urls)
        guard !added.isEmpty else { return }
        SettingsNavigator.shared.targetRepositoriesTab = true
        SettingsNavigator.shared.pendingSelectedRepoID = added.count == 1 ? added.first : nil
        openSettingsWindow()
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)

        // If the SwiftUI Settings window already exists, bring it forward.
        for window in NSApp.windows
            where window.identifier?.rawValue == "com_apple_SwiftUI_Settings_window"
        {
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Otherwise use the SwiftUI action captured from MenuBarView's env.
        SettingsNavigator.shared.openSettingsAction?()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            for window in NSApp.windows
                where window.identifier?.rawValue == "com_apple_SwiftUI_Settings_window"
            {
                window.makeKeyAndOrderFront(nil)
            }
        }
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
        // Try to find and activate an existing window
        for window in NSApp.windows where window.title == "Summary" {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // Window not yet created — use stored openWindow action
        SummaryWindowState.shared.openWindowAction?(id: "summary-detail")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Transparent overlay hosted as a subview of the status-item button. The
/// button's backing window doesn't reliably deliver drag events on
/// LSUIElement apps, so we attach an NSDraggingDestination subview.
/// `hitTest` returns nil so mouse clicks fall through to the button.
final class StatusBarDropView: NSView {
    var onDrop: ([URL]) -> Void = { _ in }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        acceptableURLs(from: sender).isEmpty ? [] : .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        acceptableURLs(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = acceptableURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onDrop(urls)
        return true
    }

    private func acceptableURLs(from sender: any NSDraggingInfo) -> [URL] {
        let pb = sender.draggingPasteboard
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        else { return [] }
        return urls.filter { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        }
    }
}
