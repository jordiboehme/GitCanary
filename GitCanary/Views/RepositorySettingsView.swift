import SwiftUI

struct RepositorySettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selection: UUID?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(appState.repositories) { repo in
                    repositoryRow(repo)
                        .tag(repo.id)
                }
            }
            .listStyle(.bordered)

            HStack(spacing: 6) {
                Button(action: addRepository) {
                    Image(systemName: "plus")
                }
                Button(action: removeSelected) {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil)
                Spacer()
            }
            .padding(8)
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
                Text(repo.trackingBranch)
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
