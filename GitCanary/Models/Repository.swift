import Foundation

enum RepositoryStatus: Equatable {
    case idle
    case checking
    case fetching
    case hasChanges(count: Int)
    case summarizing
    case error(String)

    var isActive: Bool {
        switch self {
        case .checking, .fetching, .summarizing: true
        default: false
        }
    }
}

enum BranchMode: String, Codable, CaseIterable, Identifiable {
    case auto
    case fixed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .fixed: "Fixed"
        }
    }
}

struct Repository: Identifiable, Equatable {
    let id: UUID
    var name: String
    var path: String
    var bookmarkData: Data?
    var remoteName: String
    var branchMode: BranchMode
    var trackingBranch: String
    var activeBranch: String?
    var lastCheckedDate: Date?
    var lastRemoteHash: String?
    var status: RepositoryStatus
    var latestSummary: DiffSummary?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        bookmarkData: Data? = nil,
        remoteName: String = "origin",
        branchMode: BranchMode = .auto,
        trackingBranch: String = "main",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmarkData = bookmarkData
        self.remoteName = remoteName
        self.branchMode = branchMode
        self.trackingBranch = trackingBranch
        self.activeBranch = nil
        self.lastCheckedDate = nil
        self.lastRemoteHash = nil
        self.status = .idle
        self.latestSummary = nil
        self.isEnabled = isEnabled
    }
}

struct PersistedRepository: Codable {
    let id: UUID
    var name: String
    var path: String
    var bookmarkData: Data?
    var remoteName: String
    var branchMode: BranchMode?
    var trackingBranch: String
    var lastRemoteHash: String?
    var isEnabled: Bool

    init(from repo: Repository) {
        self.id = repo.id
        self.name = repo.name
        self.path = repo.path
        self.bookmarkData = repo.bookmarkData
        self.remoteName = repo.remoteName
        self.branchMode = repo.branchMode
        self.trackingBranch = repo.trackingBranch
        self.lastRemoteHash = repo.lastRemoteHash
        self.isEnabled = repo.isEnabled
    }

    func toRepository() -> Repository {
        var repo = Repository(
            id: id,
            name: name,
            path: path,
            bookmarkData: bookmarkData,
            remoteName: remoteName,
            branchMode: branchMode ?? .auto,
            trackingBranch: trackingBranch,
            isEnabled: isEnabled
        )
        repo.lastRemoteHash = lastRemoteHash
        return repo
    }
}
