import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            if !appState.gitAvailable {
                gitWarningBanner
                Divider()
            }

            if appState.repositories.isEmpty {
                emptyState
            } else {
                repositoryList
            }

            Divider()
            actionButtons
            Divider()
            footerButtons
        }
        .frame(width: 300)
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
        .padding(10)
        .background(.orange.opacity(0.08))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bird")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
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
        .padding(24)
    }

    // MARK: - Repository List

    private var repositoryList: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(appState.repositories) { repo in
                    RepositoryRow(repository: repo)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 280)
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 0) {
            if let next = appState.remotePoller.nextScheduledCheck {
                HStack {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Next check \(next, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Button {
                appState.checkAllNow()
            } label: {
                Label("Check All Now", systemImage: "arrow.clockwise")
            }
            .disabled(appState.repositories.isEmpty || !appState.gitAvailable)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Button {
                appState.togglePause()
            } label: {
                Label(
                    appState.isPaused ? "Resume Monitoring" : "Pause Monitoring",
                    systemImage: appState.isPaused ? "play.fill" : "pause.fill"
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Footer

    private var footerButtons: some View {
        VStack(spacing: 0) {
            SettingsLink {
                Label("Settings...", systemImage: "gear")
            }
            .keyboardShortcut(",", modifiers: .command)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit GitCanary", systemImage: "power")
            }
            .keyboardShortcut("q")
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Actions

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
