import Foundation
import AppKit

@Observable
final class AppState {
    static let shared = AppState()

    var repositories: [Repository] = []
    var isPaused: Bool = false
    var gitAvailable: Bool = true
    var gitError: String?

    private(set) var remotePoller = RemotePoller()
    private(set) var fsEventsWatcher = FSEventsWatcher()
    private var gitCLI: GitCLI?

    private let settings = AppSettings.shared

    private init() {}

    func start() {
        detectGitBinary()
        loadRepositories()
        startPolling()
        setupFSEvents()
        setupWakeObserver()
        remotePoller.handleMissedSchedules(gitCLI: gitCLI!, repositories: repositories)
    }

    func stop() {
        remotePoller.stop()
        fsEventsWatcher.stopWatching()
    }

    // MARK: - Git Binary

    private func detectGitBinary() {
        let path = settings.gitBinaryPath
        if GitCLI.isAvailable(at: path) {
            gitCLI = GitCLI(binaryPath: path)
            gitAvailable = true
            gitError = nil
            return
        }

        if let found = GitCLI.findGitBinary() {
            settings.gitBinaryPath = found
            gitCLI = GitCLI(binaryPath: found)
            gitAvailable = true
            gitError = nil
            return
        }

        gitAvailable = false
        gitError = "Git not found. Install Xcode Command Line Tools or configure the path in Settings."
        gitCLI = GitCLI(binaryPath: path)
    }

    // MARK: - Repositories

    func addRepository(url: URL) {
        let name = url.lastPathComponent
        let bookmarkData = try? BookmarkManager.createBookmark(for: url)

        var repo = Repository(
            name: name,
            path: url.path,
            bookmarkData: bookmarkData
        )

        // Detect branch and remote
        Task {
            if let git = gitCLI {
                if let branch = try? await git.currentBranch(in: url.path) {
                    repo.trackingBranch = branch
                }
                if let remotes = try? await git.remotes(in: url.path), let first = remotes.first {
                    repo.remoteName = first
                }
            }
            repositories.append(repo)
            saveRepositories()
            restartMonitoring()
        }
    }

    func removeRepository(id: UUID) {
        repositories.removeAll { $0.id == id }
        saveRepositories()
        restartMonitoring()
    }

    // MARK: - Polling

    func checkAllNow() {
        guard let git = gitCLI else { return }
        remotePoller.checkNow(gitCLI: git, repositories: repositories)
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            remotePoller.stop()
        } else {
            startPolling()
        }
    }

    private func startPolling() {
        guard !isPaused, let git = gitCLI else { return }

        remotePoller.onPollResult = { [weak self] repoID, result in
            self?.handlePollResult(repoID: repoID, result: result)
        }

        remotePoller.start(gitCLI: git, repositories: repositories)
    }

    private func handlePollResult(repoID: UUID, result: PollResult) {
        guard let index = repositories.firstIndex(where: { $0.id == repoID }) else { return }

        switch result {
        case .noChanges:
            repositories[index].status = .idle
            repositories[index].lastCheckedDate = Date()

        case .newCommits(let commits, let fromHash, let toHash):
            repositories[index].status = .hasChanges(count: commits.count)
            repositories[index].lastCheckedDate = Date()
            repositories[index].lastRemoteHash = toHash
            saveRepositories()
            summarize(repoIndex: index, commits: commits, fromHash: fromHash, toHash: toHash)

        case .error(let message):
            repositories[index].status = .error(message)
        }
    }

    // MARK: - Summarization

    private func summarize(repoIndex: Int, commits: [CommitInfo], fromHash: String, toHash: String) {
        let repo = repositories[repoIndex]
        repositories[repoIndex].status = .summarizing

        Task {
            let service = currentLLMService()
            do {
                let diffStat = try? await gitCLI?.diff(range: "\(fromHash)..\(toHash)", in: repo.path)
                let summary = try await service.summarize(
                    commits: commits,
                    diff: diffStat,
                    repositoryName: repo.name
                )

                let diffSummary = DiffSummary(
                    repositoryID: repo.id,
                    provider: settings.selectedLLMProvider,
                    summary: summary,
                    commits: commits,
                    fromHash: fromHash,
                    toHash: toHash
                )

                if let idx = repositories.firstIndex(where: { $0.id == repo.id }) {
                    repositories[idx].latestSummary = diffSummary
                    repositories[idx].status = .idle
                }
            } catch {
                if let idx = repositories.firstIndex(where: { $0.id == repo.id }) {
                    repositories[idx].status = .error("Summary failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func currentLLMService() -> any LLMService {
        switch settings.selectedLLMProvider {
        case .ollama:
            OllamaService(baseURL: settings.ollamaBaseURL, model: settings.ollamaModel)
        case .claude:
            ClaudeService(model: settings.claudeModel)
        case .openai:
            OpenAIService(model: settings.openAIModel)
        case .appleIntelligence:
            #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                AppleIntelligenceService()
            } else {
                AppleIntelligenceFallbackService()
            }
            #else
            AppleIntelligenceFallbackService()
            #endif
        }
    }

    // MARK: - FSEvents

    private func setupFSEvents() {
        fsEventsWatcher.onChange = { [weak self] repoPath in
            guard let self else { return }
            // A local change happened — could trigger a re-check
            if let repo = repositories.first(where: { $0.path == repoPath }),
               let git = gitCLI
            {
                Task {
                    let result = await self.remotePoller.poll(repo, gitCLI: git)
                    self.handlePollResult(repoID: repo.id, result: result)
                }
            }
        }
        fsEventsWatcher.watch(repositories: repositories)
    }

    private func setupWakeObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let git = gitCLI else { return }
            remotePoller.handleMissedSchedules(gitCLI: git, repositories: repositories)
        }
    }

    private func restartMonitoring() {
        remotePoller.stop()
        fsEventsWatcher.stopWatching()
        startPolling()
        setupFSEvents()
    }

    // MARK: - Persistence

    private func saveRepositories() {
        let persisted = repositories.map { PersistedRepository(from: $0) }
        if let data = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(data, forKey: "repositories")
        }
    }

    private func loadRepositories() {
        guard let data = UserDefaults.standard.data(forKey: "repositories"),
              let persisted = try? JSONDecoder().decode([PersistedRepository].self, from: data)
        else { return }
        repositories = persisted.map { $0.toRepository() }
    }
}
