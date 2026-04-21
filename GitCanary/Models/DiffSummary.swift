import Foundation

struct DiffSummary: Identifiable, Equatable, Codable {
    let id: UUID
    let repositoryID: UUID
    let generatedAt: Date
    let provider: LLMProviderType
    let summary: String
    let commits: [CommitInfo]
    let fromHash: String
    let toHash: String
    var isRead: Bool

    init(
        id: UUID = UUID(),
        repositoryID: UUID,
        generatedAt: Date = Date(),
        provider: LLMProviderType,
        summary: String,
        commits: [CommitInfo],
        fromHash: String,
        toHash: String,
        isRead: Bool = false
    ) {
        self.id = id
        self.repositoryID = repositoryID
        self.generatedAt = generatedAt
        self.provider = provider
        self.summary = summary
        self.commits = commits
        self.fromHash = fromHash
        self.toHash = toHash
        self.isRead = isRead
    }

    enum CodingKeys: String, CodingKey {
        case id, repositoryID, generatedAt, provider, summary, commits, fromHash, toHash, isRead
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        repositoryID = try container.decode(UUID.self, forKey: .repositoryID)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        provider = try container.decode(LLMProviderType.self, forKey: .provider)
        summary = try container.decode(String.self, forKey: .summary)
        commits = try container.decode([CommitInfo].self, forKey: .commits)
        fromHash = try container.decode(String.self, forKey: .fromHash)
        toHash = try container.decode(String.self, forKey: .toHash)
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
    }
}
