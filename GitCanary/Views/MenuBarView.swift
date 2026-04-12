import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !appState.gitAvailable {
                gitWarningBanner
                Divider()
            }

            if appState.repositories.contains(where: { $0.status.isActive }) {
                summarizingBanner
                Divider()
            }

            if appState.repositories.isEmpty {
                emptyState
            } else {
                repositoryList
            }

            Divider()

            if let next = appState.remotePoller.nextScheduledCheck {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text("Next check \(next, style: .relative)")
                    Spacer()
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                Divider()
            }

            menuButton("Check All Now", icon: "arrow.clockwise") {
                appState.checkAllNow()
            }
            .disabled(appState.repositories.isEmpty || !appState.gitAvailable)

            menuButton("View Summaries", icon: "text.document") {
                openSummaryWindow()
            }

            menuButton(
                appState.isPaused ? "Resume Monitoring" : "Pause Monitoring",
                icon: appState.isPaused ? "play.fill" : "pause.fill"
            ) {
                appState.togglePause()
            }

            Divider()

            SettingsLink {
                menuLabel("Settings...", icon: "gear")
            }
            .simultaneousGesture(TapGesture().onEnded {
                dismissPopover()
            })
            .keyboardShortcut(",", modifiers: .command)

            menuButton("Quit GitCanary", icon: "power") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")

            Spacer().frame(height: 6)
        }
        .buttonStyle(.plain)
        .frame(width: 260)
        .onAppear {
            SummaryWindowState.shared.openWindowAction = openWindow
        }
    }

    // MARK: - Activity Banner

    private var summarizingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(activityLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var activityLabel: String {
        let active = appState.repositories.filter { $0.status.isActive }
        guard let first = active.first else { return "" }
        switch first.status {
        case .checking, .fetching:
            return "Checking \(first.name)..."
        case .summarizing:
            return "Summarizing \(first.name)..."
        default:
            return "Working..."
        }
    }

    // MARK: - Git Warning

    private var gitWarningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Git not found")
                    .font(.caption.weight(.semibold))
                Text(appState.gitError ?? "Install Command Line Tools")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.08))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
            Text("No repositories")
                .font(.headline)
            Text("Add a git repository to start\nmonitoring remote changes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add Repository...") {
                addRepository()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    // MARK: - Repository List

    private var repositoryList: some View {
        VStack(spacing: 0) {
            ForEach(appState.repositories) { repo in
                RepositoryRow(repository: repo)
            }
        }
    }

    // MARK: - Menu Button

    private func menuButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            menuLabel(title, icon: icon)
        }
    }

    private func menuLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16, alignment: .center)
            Text(title)
            Spacer()
        }
        .font(.body)
        .contentShape(Rectangle())
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    /// Dismisses the MenuBarExtra popover panel
    private func dismissPopover() {
        if let panel = NSApp.keyWindow as? NSPanel {
            panel.close()
        }
    }

    private func openSummaryWindow() {
        dismissPopover()
        SummaryWindowState.shared.requestOpen()
        openWindow(id: "summary-detail")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func addRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a git repository"
        panel.prompt = "Add"

        if panel.runModal() == .OK, let url = panel.url {
            appState.addRepository(url: url)
        }
    }
}
