import SwiftUI

enum SummarySortOrder: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst
    case mostCommits
    case fewestCommits

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newestFirst: "Newest First"
        case .oldestFirst: "Oldest First"
        case .mostCommits: "Most Commits"
        case .fewestCommits: "Fewest Commits"
        }
    }

    var systemImage: String {
        switch self {
        case .newestFirst, .mostCommits: "arrow.down"
        case .oldestFirst, .fewestCommits: "arrow.up"
        }
    }
}

enum SidebarSelection: Hashable {
    case overview
    case summary(UUID)
}

struct SummaryDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var windowState = SummaryWindowState.shared
    @State private var historyStore = SummaryHistoryStore.shared
    @State private var sidebarSelection: SidebarSelection = .overview
    @AppStorage("summarySortOrder") private var sortOrderRaw = SummarySortOrder.newestFirst.rawValue

    private var sortOrder: SummarySortOrder {
        SummarySortOrder(rawValue: sortOrderRaw) ?? .newestFirst
    }

    private var selectedSummaryID: UUID? {
        if case .summary(let id) = sidebarSelection { return id }
        return nil
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            applyWindowState()
            if case .summary(let id) = sidebarSelection {
                historyStore.markRead(id)
            }
        }
        .onChange(of: windowState.openTrigger) {
            applyWindowState()
        }
        .onChange(of: sidebarSelection) { _, newValue in
            if case .summary(let id) = newValue {
                historyStore.markRead(id)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            Section {
                overviewRow
                    .tag(SidebarSelection.overview)
            }

            let grouped = groupedSummaries
            ForEach(grouped, id: \.repoID) { group in
                Section(group.repoName) {
                    ForEach(group.summaries) { summary in
                        sidebarRow(summary)
                            .tag(SidebarSelection.summary(summary.id))
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
        .safeAreaInset(edge: .top, spacing: 0) {
            if !repoPickerOptions.isEmpty {
                sidebarPicker
            }
        }
    }

    private var overviewRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full")
                .foregroundStyle(filteredUnread.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            Text("Unread Summaries")
                .font(.callout)
            Spacer()
            if !filteredUnread.isEmpty {
                Text("\(filteredUnread.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    private var sidebarPicker: some View {
        HStack(spacing: 8) {
            repoPicker
            sortMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private var repoPicker: some View {
        Picker(selection: Binding(
            get: { windowState.selectedRepositoryID },
            set: { newValue in
                windowState.selectedRepositoryID = newValue
                windowState.selectedSummaryID = nil
                let firstID: UUID?
                if let newValue {
                    firstID = historyStore.summaries(for: newValue).first?.id
                } else {
                    firstID = historyStore.summaries.first?.id
                }
                sidebarSelection = firstID.map(SidebarSelection.summary) ?? .overview
            }
        )) {
            Text("All Repositories").tag(nil as UUID?)
            ForEach(repoPickerOptions, id: \.id) { option in
                Text(option.name).tag(option.id as UUID?)
            }
        } label: {
            Text("Repository")
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SummarySortOrder.allCases) { option in
                Button {
                    sortOrderRaw = option.rawValue
                } label: {
                    if sortOrder == option {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Label(option.displayName, systemImage: option.systemImage)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort summaries")
    }

    private var repoPickerOptions: [(id: UUID, name: String)] {
        let repoIDs = Set(historyStore.summaries.map { $0.repositoryID })
        return repoIDs
            .map { id in
                let name = appState.repositories.first(where: { $0.id == id })?.name ?? "Unknown"
                return (id: id, name: name)
            }
            .sorted { $0.name < $1.name }
    }

    private func sidebarRow(_ summary: DiffSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(summary.generatedAt, style: .date)
                    .font(.caption.weight(summary.isRead ? .regular : .medium))
                    .foregroundStyle(summary.isRead ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                Spacer()
                commitCountBadge(summary)
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

    private func commitCountBadge(_ summary: DiffSummary) -> some View {
        Text("\(summary.commits.count)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(summary.isRead ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background {
                Capsule()
                    .fill(summary.isRead ? Color.clear : Color.blue)
            }
            .overlay {
                if summary.isRead {
                    Capsule().stroke(.secondary, lineWidth: 1)
                }
            }
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
        } else if !filteredUnread.isEmpty {
            unreadOverview
        } else {
            ContentUnavailableView(
                "You're All Caught Up",
                systemImage: "checkmark.circle",
                description: Text("No unread summaries. Pick one from the sidebar to revisit it.")
            )
        }
    }

    // MARK: - Unread Overview

    private var filteredUnread: [DiffSummary] {
        let all: [DiffSummary]
        if let repoID = windowState.selectedRepositoryID {
            all = historyStore.summaries(for: repoID)
        } else {
            all = historyStore.summaries
        }
        return all
            .filter { !$0.isRead }
            .sorted { $0.generatedAt > $1.generatedAt }
    }

    private var unreadOverview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Unread Summaries")
                        .font(.largeTitle.weight(.semibold))
                    Spacer()
                    Text("\(filteredUnread.count) unread")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Mark All as Read") {
                        for summary in filteredUnread {
                            historyStore.markRead(summary.id)
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                ForEach(filteredUnread) { summary in
                    unreadCard(summary)
                }
            }
            .padding(20)
        }
    }

    private func unreadCard(_ summary: DiffSummary) -> some View {
        let repo = appState.repositories.first(where: { $0.id == summary.repositoryID })
        return Button {
            sidebarSelection = .summary(summary.id)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.gearshape")
                        .foregroundStyle(.secondary)
                    Text(repo?.name ?? "Unknown Repository")
                        .font(.headline)
                    Spacer()
                    Text(summary.generatedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(LocalizedStringKey(summary.summary))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    Image(systemName: "text.document")
                    Text("\(summary.commits.count) \(summary.commits.count == 1 ? "commit" : "commits")")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
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
            return RepoGroup(repoID: repoID, repoName: name, summaries: sortSummaries(summaries))
        }
        .sorted { $0.repoName < $1.repoName }
    }

    private func sortSummaries(_ items: [DiffSummary]) -> [DiffSummary] {
        switch sortOrder {
        case .newestFirst: items.sorted { $0.generatedAt > $1.generatedAt }
        case .oldestFirst: items.sorted { $0.generatedAt < $1.generatedAt }
        case .mostCommits: items.sorted { $0.commits.count > $1.commits.count }
        case .fewestCommits: items.sorted { $0.commits.count < $1.commits.count }
        }
    }

    // MARK: - Actions

    private func applyWindowState() {
        if let id = windowState.selectedSummaryID {
            // Verify the summary still exists
            if historyStore.summaries.contains(where: { $0.id == id }) {
                sidebarSelection = .summary(id)
            } else if let repoID = windowState.selectedRepositoryID,
                      let first = historyStore.summaries(for: repoID).first {
                sidebarSelection = .summary(first.id)
            } else {
                sidebarSelection = .overview
            }
        } else if let repoID = windowState.selectedRepositoryID,
                  let first = historyStore.summaries(for: repoID).first {
            sidebarSelection = .summary(first.id)
        }
    }

    private func deleteSummary(_ id: UUID) {
        if selectedSummaryID == id {
            sidebarSelection = .overview
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
