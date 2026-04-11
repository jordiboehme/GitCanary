import Foundation
import SwiftUI

@Observable
final class SummaryWindowState {
    static let shared = SummaryWindowState()

    var selectedRepositoryID: UUID?
    var selectedSummaryID: UUID?
    var pendingOpen: Bool = false

    /// Stored reference to the SwiftUI openWindow action, captured from a rendered view
    var openWindowAction: OpenWindowAction?

    private init() {}

    func requestOpen(repoID: UUID? = nil, summaryID: UUID? = nil) {
        selectedRepositoryID = repoID
        selectedSummaryID = summaryID
        pendingOpen = true
        openWindowAction?(id: "summary-detail")
    }
}
