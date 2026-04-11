import Foundation

enum GitLogParser {
    static func parse(_ output: String) -> [CommitInfo] {
        guard !output.isEmpty else { return [] }

        var commits: [CommitInfo] = []
        var currentHeader: (hash: String, author: String, email: String, timestamp: Date, subject: String)?
        var currentStats: [FileStat] = []

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("COMMIT|") {
                // Flush previous commit
                if let header = currentHeader {
                    commits.append(CommitInfo(
                        hash: header.hash,
                        author: header.author,
                        authorEmail: header.email,
                        timestamp: header.timestamp,
                        subject: header.subject,
                        fileStats: currentStats
                    ))
                }

                let parts = trimmed.split(separator: "|", maxSplits: 5)
                guard parts.count >= 6 else {
                    currentHeader = nil
                    currentStats = []
                    continue
                }

                let timestamp = TimeInterval(parts[4]) ?? 0
                currentHeader = (
                    hash: String(parts[1]),
                    author: String(parts[2]),
                    email: String(parts[3]),
                    timestamp: Date(timeIntervalSince1970: timestamp),
                    subject: String(parts[5])
                )
                currentStats = []
            } else if trimmed.isEmpty {
                continue
            } else {
                // numstat line: <insertions>\t<deletions>\t<path>
                let statParts = trimmed.split(separator: "\t", maxSplits: 2)
                guard statParts.count == 3 else { continue }

                let ins = Int(statParts[0]) ?? 0 // binary files show "-"
                let del = Int(statParts[1]) ?? 0
                currentStats.append(FileStat(
                    insertions: ins,
                    deletions: del,
                    path: String(statParts[2])
                ))
            }
        }

        // Flush last commit
        if let header = currentHeader {
            commits.append(CommitInfo(
                hash: header.hash,
                author: header.author,
                authorEmail: header.email,
                timestamp: header.timestamp,
                subject: header.subject,
                fileStats: currentStats
            ))
        }

        return commits
    }
}
