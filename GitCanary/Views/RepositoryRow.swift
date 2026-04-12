import SwiftUI

struct RepositoryRow: View {
    let repository: Repository
    @Environment(\.openWindow) private var openWindow
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            if isExpanded, let summary = repository.latestSummary {
                SummaryView(summary: summary)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if repository.latestSummary != nil {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
        }
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

                    Text(repository.trackingBranch)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }

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
            }

            Spacer()

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

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
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
