import Foundation

enum BookmarkError: LocalizedError {
    case creationFailed(Error)
    case resolutionFailed(Error)
    case stale

    var errorDescription: String? {
        switch self {
        case .creationFailed(let error): "Failed to create bookmark: \(error.localizedDescription)"
        case .resolutionFailed(let error): "Failed to resolve bookmark: \(error.localizedDescription)"
        case .stale: "Bookmark is stale and needs to be recreated"
        }
    }
}

enum BookmarkManager {
    static func createBookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw BookmarkError.creationFailed(error)
        }
    }

    static func resolveBookmark(_ data: Data) throws -> URL {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                throw BookmarkError.stale
            }
            return url
        } catch let error as BookmarkError {
            throw error
        } catch {
            throw BookmarkError.resolutionFailed(error)
        }
    }

    static func withAccess<T>(to bookmarkData: Data, perform work: (URL) async throws -> T) async throws -> T {
        let url = try resolveBookmark(bookmarkData)
        guard url.startAccessingSecurityScopedResource() else {
            throw BookmarkError.resolutionFailed(
                NSError(domain: "BookmarkManager", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to access security-scoped resource",
                ])
            )
        }
        defer { url.stopAccessingSecurityScopedResource() }
        return try await work(url)
    }
}
