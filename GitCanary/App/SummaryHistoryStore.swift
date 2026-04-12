import Foundation

@Observable
final class SummaryHistoryStore {
    static let shared = SummaryHistoryStore()

    private(set) var summaries: [DiffSummary] = []
    private let directory: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = appSupport.appendingPathComponent("GitCanary/Summaries", isDirectory: true)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    func add(_ summary: DiffSummary) {
        summaries.insert(summary, at: 0)
        save(summary)
    }

    func summaries(for repoID: UUID) -> [DiffSummary] {
        summaries.filter { $0.repositoryID == repoID }
    }

    func delete(_ summaryID: UUID) {
        if let index = summaries.firstIndex(where: { $0.id == summaryID }) {
            let file = directory.appendingPathComponent("\(summaryID.uuidString).json")
            try? FileManager.default.removeItem(at: file)
            summaries.remove(at: index)
        }
    }

    func deleteAll(for repoID: UUID) {
        let toRemove = summaries.filter { $0.repositoryID == repoID }
        summaries.removeAll { $0.repositoryID == repoID }

        for summary in toRemove {
            let file = directory.appendingPathComponent("\(summary.id.uuidString).json")
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Private

    private func load() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        let decoder = JSONDecoder()
        var loaded: [DiffSummary] = []

        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let summary = try? decoder.decode(DiffSummary.self, from: data)
            {
                loaded.append(summary)
            }
        }

        summaries = loaded.sorted { $0.generatedAt > $1.generatedAt }
    }

    private func save(_ summary: DiffSummary) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(summary) else { return }

        let file = directory.appendingPathComponent("\(summary.id.uuidString).json")
        try? data.write(to: file, options: .atomic)
    }
}
