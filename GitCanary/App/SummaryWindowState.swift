import Foundation

@Observable
final class SummaryWindowState {
    static let shared = SummaryWindowState()

    var selectedRepositoryID: UUID?
    var selectedSummaryID: UUID?

    private init() {}

    func requestOpen(repoID: UUID? = nil, summaryID: UUID? = nil) {
        selectedRepositoryID = repoID
        selectedSummaryID = summaryID
    }
}
