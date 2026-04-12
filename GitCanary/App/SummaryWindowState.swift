import Foundation
import SwiftUI

@Observable
final class SummaryWindowState {
    static let shared = SummaryWindowState()

    var selectedRepositoryID: UUID?
    var selectedSummaryID: UUID?
    var openTrigger: Int = 0

    /// Stored reference to openWindow, captured from a SwiftUI view
    var openWindowAction: OpenWindowAction?

    private init() {}

    func requestOpen(repoID: UUID? = nil, summaryID: UUID? = nil) {
        selectedRepositoryID = repoID
        selectedSummaryID = summaryID
        openTrigger += 1
    }
}
