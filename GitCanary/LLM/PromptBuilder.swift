import Foundation

enum PromptBuilder {
    static var systemPrompt: String {
        var prompt = """
            You are a git commit summarizer. Given a list of commits and optionally a diff stat, \
            produce a concise summary of what changed. Focus on the purpose and impact of changes, \
            not implementation details. Group related changes together. Use markdown bullet points. \
            Keep the summary to 2-5 bullet points.
            """

        let custom = AppSettings.shared.customPromptInstructions
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            prompt += "\n\nAdditional instructions from the user:\n\(custom)"
        }

        return prompt
    }

    static func buildUserPrompt(
        commits: [CommitInfo],
        diff: String?,
        repositoryName: String,
        maxLength: Int = 12000
    ) -> String {
        var parts: [String] = []

        parts.append("## Repository: \(repositoryName)")
        parts.append("")
        parts.append("### Commits (\(commits.count))")
        parts.append("")

        for commit in commits {
            let stats = "+\(commit.insertions) -\(commit.deletions) in \(commit.filesChanged) files"
            parts.append("- `\(commit.shortHash)` \(commit.author): \(commit.subject) (\(stats))")
        }

        if let diff, !diff.isEmpty {
            parts.append("")
            parts.append("### Diff Summary")
            parts.append("")

            let currentLength = parts.joined(separator: "\n").count
            let remaining = maxLength - currentLength - 200
            if remaining > 0 {
                let truncated = diff.count > remaining ? String(diff.prefix(remaining)) + "\n... (truncated)" : diff
                parts.append(truncated)
            }
        }

        parts.append("")
        parts.append("Summarize these changes in 2-5 bullet points.")

        return parts.joined(separator: "\n")
    }
}
