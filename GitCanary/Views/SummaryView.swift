import SwiftUI

struct SummaryView: View {
    let summary: DiffSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "text.document")
                    .foregroundStyle(.secondary)
                Text("\(summary.commits.count) commits")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(summary.fromHash.prefix(7) + ".." + summary.toHash.prefix(7))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }

            // AI Summary
            Text(LocalizedStringKey(summary.summary))
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Commits disclosure
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(summary.commits) { commit in
                        HStack(spacing: 6) {
                            Text(commit.shortHash)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Text(commit.subject)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
            } label: {
                Text("Commits")
                    .font(.caption.weight(.medium))
            }

            // Footer
            HStack(spacing: 4) {
                Image(systemName: summary.provider.icon)
                    .font(.caption2)
                Text(summary.provider.displayName)
                    .font(.caption2)
                Text("·")
                Text(summary.generatedAt, style: .relative)
                    .font(.caption2)
                Spacer()
            }
            .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }
}
