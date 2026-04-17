import SwiftUI

struct RepositorySettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var settings = AppSettings.shared
    @State private var selection: UUID?

    private var sortedRepositories: [Repository] {
        switch settings.repositorySortOrder {
        case .dateAdded:
            return appState.repositories
        case .name:
            return appState.repositories.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .path:
            return appState.repositories.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(sortedRepositories) { repo in
                    repositoryRow(repo)
                        .tag(repo.id)
                }
            }
            .listStyle(.bordered)

            HStack(spacing: 4) {
                Button(action: addRepository) {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)

                Button(action: removeSelected) {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .disabled(selection == nil)

                Spacer()

                Menu {
                    Picker("Sort by", selection: $settings.repositorySortOrder) {
                        ForEach(RepositorySortOrder.allCases) { order in
                            Text(order.displayName).tag(order)
                        }
                    }
                } label: {
                    Label("Sort: \(settings.repositorySortOrder.displayName)", systemImage: "arrow.up.arrow.down")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(8)

            branchSettings
        }
        .padding()
    }

    private func repositoryRow(_ repo: Repository) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 4) {
                    Text(repo.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Text(repo.activeBranch ?? repo.trackingBranch)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary)
                    .clipShape(Capsule())

                Text(repo.remoteName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var branchSettings: some View {
        if let id = selection, let index = appState.repositories.firstIndex(where: { $0.id == id }) {
            @Bindable var state = appState
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                HStack(spacing: 12) {
                    Text("Branch")
                        .font(.caption.weight(.medium))

                    Picker("", selection: $state.repositories[index].branchMode) {
                        ForEach(BranchMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                    .onChange(of: appState.repositories[index].branchMode) { _, _ in
                        appState.saveAndRestart()
                    }

                    if appState.repositories[index].branchMode == .fixed {
                        TextField("Branch name", text: $state.repositories[index].trackingBranch)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 150)
                            .onSubmit {
                                appState.saveAndRestart()
                            }
                    } else {
                        Text("Follows current branch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
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

    private func removeSelected() {
        if let id = selection {
            appState.removeRepository(id: id)
            selection = nil
        }
    }
}
