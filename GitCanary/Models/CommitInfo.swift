import Foundation

struct CommitInfo: Identifiable, Codable, Equatable {
    var id: String { hash }
    let hash: String
    let author: String
    let authorEmail: String
    let timestamp: Date
    let subject: String
    let fileStats: [FileStat]

    var filesChanged: Int { fileStats.count }
    var insertions: Int { fileStats.reduce(0) { $0 + $1.insertions } }
    var deletions: Int { fileStats.reduce(0) { $0 + $1.deletions } }

    var shortHash: String { String(hash.prefix(7)) }
}

struct FileStat: Codable, Equatable {
    let insertions: Int
    let deletions: Int
    let path: String
}
