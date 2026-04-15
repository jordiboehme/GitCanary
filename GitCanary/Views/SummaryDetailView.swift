import SwiftUI

struct SummaryDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var windowState = SummaryWindowState.shared
    @State private var historyStore = SummaryHistoryStore.shared
    @State private var selectedSummaryID: UUID?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            applyWindowState()
        }
        .onChange(of: windowState.openTrigger) {
            applyWindowState()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedSummaryID) {
            let grouped = groupedSummaries
            ForEach(grouped, id: \.repoID) { group in
                Section(group.repoName) {
                    ForEach(group.summaries) { summary in
                        sidebarRow(summary)
                            .tag(summary.id)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteSummary(summary.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
    }

    private func sidebarRow(_ summary: DiffSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(summary.generatedAt, style: .date)
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(summary.commits.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.blue)
                    .clipShape(Capsule())
            }
            Text(summary.generatedAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(summary.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let summaryID = selectedSummaryID,
           let summary = historyStore.summaries.first(where: { $0.id == summaryID })
        {
            let repo = appState.repositories.first(where: { $0.id == summary.repositoryID })

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    detailHeader(summary: summary, repo: repo)
                    Divider()
                    summarySection(summary)
                    Divider()
                    commitsSection(summary)
                }
                .padding(20)
            }
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        copySummary(summary, repo: repo)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .help("Copy summary to clipboard")

                    Button {
                        exportSummary(summary, repo: repo)
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .help("Export as Markdown")

                    Button(role: .destructive) {
                        deleteSummary(summary.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .help("Delete this summary")
                }
            }
        } else {
            ContentUnavailableView(
                "No Summary Selected",
                systemImage: "text.document",
                description: Text("Select a summary from the sidebar to view details.")
            )
        }
    }

    private func detailHeader(summary: DiffSummary, repo: Repository?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .foregroundStyle(.secondary)
                Text(repo?.name ?? "Unknown Repository")
                    .font(.title2.weight(.semibold))
                if let branch = repo?.activeBranch ?? repo?.trackingBranch {
                    Text(branch)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Label(
                    "\(summary.commits.count) \(summary.commits.count == 1 ? "commit" : "commits")",
                    systemImage: "text.document"
                )
                Label(
                    "\(summary.fromHash.prefix(7))..\(summary.toHash.prefix(7))",
                    systemImage: "arrow.triangle.branch"
                )
                .font(.caption.monospaced())

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: summary.provider.icon)
                    Text(summary.provider.displayName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(summary.generatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func summarySection(_ summary: DiffSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.headline)

            Text(LocalizedStringKey(summary.summary))
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func commitsSection(_ summary: DiffSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Commits")
                .font(.headline)

            ForEach(summary.commits) { commit in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(commit.shortHash)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)

                        Text(commit.subject)
                            .font(.callout)
                            .lineLimit(2)

                        Spacer()

                        Text(commit.timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 12) {
                        Text(commit.author)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !commit.fileStats.isEmpty {
                            HStack(spacing: 4) {
                                Text("\(commit.filesChanged) \(commit.filesChanged == 1 ? "file" : "files")")
                                if commit.insertions > 0 {
                                    Text("+\(commit.insertions)")
                                        .foregroundStyle(.green)
                                }
                                if commit.deletions > 0 {
                                    Text("-\(commit.deletions)")
                                        .foregroundStyle(.red)
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)

                if commit.id != summary.commits.last?.id {
                    Divider()
                }
            }
        }
    }

    // MARK: - Grouping

    private struct RepoGroup: Equatable {
        let repoID: UUID
        let repoName: String
        let summaries: [DiffSummary]
    }

    private var groupedSummaries: [RepoGroup] {
        let filtered: [DiffSummary]
        if let repoID = windowState.selectedRepositoryID {
            filtered = historyStore.summaries(for: repoID)
        } else {
            filtered = historyStore.summaries
        }

        let grouped = Dictionary(grouping: filtered) { $0.repositoryID }
        return grouped.map { repoID, summaries in
            let name = appState.repositories.first(where: { $0.id == repoID })?.name ?? "Unknown"
            return RepoGroup(repoID: repoID, repoName: name, summaries: summaries)
        }
        .sorted { $0.repoName < $1.repoName }
    }

    // MARK: - Actions

    private func applyWindowState() {
        if let id = windowState.selectedSummaryID {
            // Verify the summary still exists
            if historyStore.summaries.contains(where: { $0.id == id }) {
                selectedSummaryID = id
            } else if let repoID = windowState.selectedRepositoryID,
                      let first = historyStore.summaries(for: repoID).first {
                selectedSummaryID = first.id
            } else {
                selectedSummaryID = nil
            }
        } else if let repoID = windowState.selectedRepositoryID,
                  let first = historyStore.summaries(for: repoID).first {
            selectedSummaryID = first.id
        }
    }

    private func deleteSummary(_ id: UUID) {
        if selectedSummaryID == id {
            selectedSummaryID = nil
        }
        historyStore.delete(id)
    }

    private func copySummary(_ summary: DiffSummary, repo: Repository?) {
        let repoName = repo?.name ?? "Unknown"
        let text = """
        # \(repoName) — \(summary.commits.count) commits

        \(summary.summary)

        ## Commits
        \(summary.commits.map { "- \($0.shortHash) \($0.subject) (\($0.author))" }.joined(separator: "\n"))
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exportSummary(_ summary: DiffSummary, repo: Repository?) {
        let repoName = repo?.name ?? "Unknown"
        let text = """
        # \(repoName) — Summary

        **\(summary.commits.count) commits** | \(summary.fromHash.prefix(7))..\(summary.toHash.prefix(7))
        **Generated:** \(summary.generatedAt.formatted()) by \(summary.provider.displayName)

        ---

        \(summary.summary)

        ---

        ## Commits

        \(summary.commits.map { "- `\($0.shortHash)` \($0.subject) — *\($0.author)* (+\($0.insertions)/-\($0.deletions))" }.joined(separator: "\n"))
        """

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(repoName)-summary-\(summary.generatedAt.formatted(.dateTime.year().month().day())).md"

        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
