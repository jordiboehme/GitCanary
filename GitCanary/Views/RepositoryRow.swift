import SwiftUI

struct RepositoryRow: View {
    let repository: Repository
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        mainRow
    }

    private var mainRow: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(repository.name)
                        .font(.system(.body, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(repository.activeBranch ?? repository.trackingBranch)
                        .font(.caption2)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .clipShape(Capsule())
                        .fixedSize()
                }

                if case .error(let msg) = repository.status {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(msg)
                            .foregroundStyle(.orange)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(msg)
                        if let date = repository.lastCheckedDate {
                            Text(date, style: .relative)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(.caption)
                } else {
                    HStack(spacing: 4) {
                        statusText
                        if let date = repository.lastCheckedDate {
                            Text("·")
                            Text(date, style: .relative)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            .layoutPriority(-1)

            Spacer(minLength: 4)

            if case .hasChanges(let count) = repository.status {
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue)
                    .clipShape(Capsule())
            }

            if repository.latestSummary != nil {
                Button {
                    openSummaryWindow(repoID: repository.id, summaryID: repository.latestSummary?.id)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("View full summary")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch repository.status {
        case .idle:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
        case .checking, .fetching:
            ProgressView()
                .controlSize(.small)
        case .summarizing:
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
                .symbolEffect(.pulse)
        case .hasChanges:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func openSummaryWindow(repoID: UUID, summaryID: UUID?) {
        SummaryWindowState.shared.requestOpen(repoID: repoID, summaryID: summaryID)
        openWindow(id: "summary-detail")
        NSApp.activate(ignoringOtherApps: true)
    }

    @ViewBuilder
    private var statusText: some View {
        switch repository.status {
        case .idle:
            Text("Up to date")
        case .checking:
            Text("Checking...")
        case .fetching:
            Text("Fetching...")
        case .summarizing:
            Text("Summarizing...")
        case .hasChanges(let count):
            Text("\(count) new \(count == 1 ? "commit" : "commits")")
                .foregroundStyle(.blue)
        case .error(let msg):
            Text(msg)
                .foregroundStyle(.orange)
                .lineLimit(1)
        }
    }
}
