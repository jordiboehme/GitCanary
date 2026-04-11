import CoreServices
import Foundation

final class FSEventsWatcher {
    private var stream: FSEventStreamRef?
    private var watchedPaths: [String] = []
    var onChange: ((String) -> Void)?

    func watch(repositories: [Repository]) {
        stopWatching()

        let paths = repositories
            .filter { $0.isEnabled }
            .map { $0.path + "/.git/refs/heads" }
            .filter { FileManager.default.fileExists(atPath: $0) }

        guard !paths.isEmpty else { return }
        watchedPaths = paths

        var context = FSEventStreamContext()
        context.info = Unmanaged.passRetained(self).toOpaque()

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)

            for i in 0..<numEvents {
                let path = String(cString: paths[i])
                // Extract repo root from .git/refs/heads/... path
                if let range = path.range(of: "/.git/refs/heads") {
                    let repoPath = String(path[..<range.lowerBound])
                    watcher.onChange?(repoPath)
                }
            }
        }

        let pathsToWatch = paths as CFArray
        stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )

        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    func stopWatching() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    deinit {
        stopWatching()
    }
}
