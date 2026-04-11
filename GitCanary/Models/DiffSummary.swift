import Foundation

struct DiffSummary: Identifiable, Equatable {
    let id: UUID
    let repositoryID: UUID
    let generatedAt: Date
    let provider: LLMProviderType
    let summary: String
    let commits: [CommitInfo]
    let fromHash: String
    let toHash: String

    init(
        id: UUID = UUID(),
        repositoryID: UUID,
        generatedAt: Date = Date(),
        provider: LLMProviderType,
        summary: String,
        commits: [CommitInfo],
        fromHash: String,
        toHash: String
    ) {
        self.id = id
        self.repositoryID = repositoryID
        self.generatedAt = generatedAt
        self.provider = provider
        self.summary = summary
        self.commits = commits
        self.fromHash = fromHash
        self.toHash = toHash
    }
}
