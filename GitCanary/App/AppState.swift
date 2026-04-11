import Foundation
import AppKit
import UserNotifications

@Observable
final class AppState {
    static let shared = AppState()

    var repositories: [Repository] = []
    var isPaused: Bool = false
    var gitAvailable: Bool = true
    var gitError: String?

    private(set) var remotePoller = RemotePoller()
    private(set) var fsEventsWatcher = FSEventsWatcher()
    private(set) var connectivity = ConnectivityMonitor.shared
    private(set) var power = PowerMonitor.shared
    private var gitCLI: GitCLI?

    private let settings = AppSettings.shared
    private let historyStore = SummaryHistoryStore.shared

    private init() {
        remotePoller.onPollResult = { [weak self] repoID, result in
            DispatchQueue.main.async {
                self?.handlePollResult(repoID: repoID, result: result)
            }
        }
    }

    func start() {
        detectGitBinary()
        loadRepositories()
        startPolling()
        setupFSEvents()
        setupWakeObserver()
        setupConnectivityObserver()

        if connectivity.isConnected, let git = gitCLI {
            remotePoller.handleMissedSchedules(gitCLI: git, repositories: repositories)
        }
    }

    func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        NSLog("GitCanary: requesting notification permission")
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            NSLog("GitCanary: notification permission granted=%d error=%@", granted ? 1 : 0, (error?.localizedDescription ?? "none") as NSString)
        }
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
        NSLog("GitCanary: adding repo %@ at %@", name, url.path)
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
        historyStore.deleteAll(for: id)
        saveRepositories()
        restartMonitoring()
    }

    // MARK: - Polling

    func checkAllNow() {
        guard let git = gitCLI else {
            NSLog("GitCanary: gitCLI is nil, cannot check")
            return
        }
        let enabled = repositories.filter { $0.isEnabled }
        NSLog("GitCanary: checking \(enabled.count) repos")
        for i in repositories.indices where repositories[i].isEnabled {
            repositories[i].status = .checking
        }
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
        remotePoller.start(gitCLI: git, repositories: repositories)
    }

    private func handlePollResult(repoID: UUID, result: PollResult) {
        guard let index = repositories.firstIndex(where: { $0.id == repoID }) else {
            NSLog("GitCanary: repo \(repoID) not found")
            return
        }

        switch result {
        case .noChanges:
            NSLog("GitCanary: \(repositories[index].name) — no changes")
            repositories[index].lastCheckedDate = Date()

            if repositories[index].latestSummary == nil {
                // No summary yet — fetch recent commits and generate one
                generateInitialSummary(repoIndex: index)
            } else {
                repositories[index].status = .idle
            }

        case .newCommits(let commits, let fromHash, let toHash):
            NSLog("GitCanary: \(repositories[index].name) — \(commits.count) commits")
            repositories[index].lastCheckedDate = Date()
            repositories[index].lastRemoteHash = toHash
            repositories[index].status = .hasChanges(count: commits.count)
            saveRepositories()
            summarize(repoIndex: index, commits: commits, fromHash: fromHash, toHash: toHash)

        case .error(let message):
            NSLog("GitCanary: \(repositories[index].name) — error: \(message)")
            repositories[index].status = .error(message)
        }
    }

    // MARK: - Summarization

    private func generateInitialSummary(repoIndex: Int) {
        let repo = repositories[repoIndex]
        guard let git = gitCLI else { return }

        repositories[repoIndex].status = .fetching

        Task {
            do {
                let directory = repo.path
                try await git.fetch(remote: repo.remoteName, in: directory)

                let range = "\(repo.remoteName)/\(repo.trackingBranch)"
                let logOutput = try await git.log(range: range, in: directory, maxCount: settings.maxCommitsToSummarize)
                let commits = GitLogParser.parse(logOutput)

                guard !commits.isEmpty else {
                    DispatchQueue.main.async {
                        if let idx = self.repositories.firstIndex(where: { $0.id == repo.id }) {
                            self.repositories[idx].status = .idle
                        }
                    }
                    return
                }

                let toHash = repo.lastRemoteHash ?? commits.first?.hash ?? ""
                let fromHash = commits.last?.hash ?? ""

                DispatchQueue.main.async {
                    if let idx = self.repositories.firstIndex(where: { $0.id == repo.id }) {
                        self.repositories[idx].status = .hasChanges(count: commits.count)
                        self.summarize(repoIndex: idx, commits: commits, fromHash: fromHash, toHash: toHash)
                    }
                }
            } catch {
                NSLog("GitCanary: initial summary failed for %@: %@", repo.name, error.localizedDescription)
                DispatchQueue.main.async {
                    if let idx = self.repositories.firstIndex(where: { $0.id == repo.id }) {
                        self.repositories[idx].status = .error(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func summarize(repoIndex: Int, commits: [CommitInfo], fromHash: String, toHash: String) {
        // Defer summarization if on battery and setting is enabled
        if settings.deferLLMToBattery && !power.isOnACPower {
            return
        }

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
                historyStore.add(diffSummary)
                sendNotification(repoName: repo.name, commitCount: commits.count, summary: summary, repoID: repo.id, summaryID: diffSummary.id)
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
            if connectivity.isConnected {
                remotePoller.handleMissedSchedules(gitCLI: git, repositories: repositories)
            }
            // If not connected, the connectivity observer will catch up once online
        }
    }

    private func setupConnectivityObserver() {
        connectivity.onConnectivityRestored = { [weak self] in
            guard let self, let git = gitCLI, !isPaused else { return }
            remotePoller.handleMissedSchedules(gitCLI: git, repositories: repositories)
        }
    }

    private func restartMonitoring() {
        remotePoller.stop()
        fsEventsWatcher.stopWatching()
        startPolling()
        setupFSEvents()
    }

    // MARK: - Notifications

    private func sendNotification(repoName: String, commitCount: Int, summary: String, repoID: UUID, summaryID: UUID) {
        let content = UNMutableNotificationContent()
        content.title = "\(repoName) — \(commitCount) new \(commitCount == 1 ? "commit" : "commits")"
        content.body = summary
        content.sound = .default
        content.userInfo = [
            "repositoryID": repoID.uuidString,
            "summaryID": summaryID.uuidString
        ]

        let request = UNNotificationRequest(
            identifier: "summary-\(repoName)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
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
