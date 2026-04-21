import Foundation
import os
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
    private(set) var connectivity = ConnectivityMonitor.shared
    private(set) var power = PowerMonitor.shared
    private var gitCLI: GitCLI?
    private let logger = Logger(subsystem: "com.jordiboehme.GitCanary", category: "AppState")

    private let settings = AppSettings.shared
    private let historyStore = SummaryHistoryStore.shared

    private init() {
        remotePoller.onPollResult = { [weak self] repoID, resolved in
            DispatchQueue.main.async {
                self?.handlePollResult(repoID: repoID, resolved: resolved)
            }
        }
    }

    func start() {
        detectGitBinary()
        loadRepositories()
        startPolling()
        setupWakeObserver()
        setupConnectivityObserver()
        setupScheduleObserver()

        if connectivity.isConnected, let git = gitCLI {
            remotePoller.handleMissedSchedules(gitCLI: git, repositories: repositories)
        }
    }

    func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        logger.info("Requesting notification permission")
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [self] granted, error in
            logger.info("Notification permission granted=\(granted) error=\(error?.localizedDescription ?? "none")")
        }
    }

    func stop() {
        remotePoller.stop()
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
        _ = addRepositoryReturningID(url: url)
    }

    @discardableResult
    func addRepositoryReturningID(url: URL) -> UUID {
        let name = url.lastPathComponent
        logger.info("Adding repo \(name) at \(url.path)")
        let bookmarkData = try? BookmarkManager.createBookmark(for: url)

        var repo = Repository(
            name: name,
            path: url.path,
            bookmarkData: bookmarkData
        )
        let repoID = repo.id

        // Detect branch and remote; mutate on the main actor so SwiftUI's
        // @Observable propagation hits the current render tick.
        Task { @MainActor in
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

        return repoID
    }

    @discardableResult
    func addRepositories(from urls: [URL]) -> [UUID] {
        var seenPaths = Set(repositories.map { $0.path })
        var added: [UUID] = []
        for source in urls {
            for repoURL in GitRepoScanner.findRepositories(at: source) {
                guard seenPaths.insert(repoURL.path).inserted else { continue }
                let id = addRepositoryReturningID(url: repoURL)
                added.append(id)
            }
        }
        return added
    }

    func removeRepository(id: UUID) {
        repositories.removeAll { $0.id == id }
        historyStore.deleteAll(for: id)
        saveRepositories()
        restartMonitoring()
    }

    func saveAndRestart() {
        saveRepositories()
        restartMonitoring()
    }

    // MARK: - Polling

    func checkAllNow() {
        guard let git = gitCLI else {
            logger.error("gitCLI is nil, cannot check")
            return
        }
        let enabled = repositories.filter { $0.isEnabled }
        logger.info("Checking \(enabled.count) repos")
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

    private func handlePollResult(repoID: UUID, resolved: RemotePoller.ResolvedPoll) {
        guard let index = repositories.firstIndex(where: { $0.id == repoID }) else {
            logger.error("Repo \(repoID) not found")
            return
        }

        if let branch = resolved.activeBranch {
            repositories[index].activeBranch = branch
        }

        switch resolved.result {
        case .noChanges:
            logger.info("\(self.repositories[index].name) — no changes")
            repositories[index].lastCheckedDate = Date()
            repositories[index].status = .idle

        case .syncedSilently(let localHash, let remoteHash):
            logger.info("\(self.repositories[index].name) — synced silently (local=\(localHash ?? "nil") remote=\(remoteHash))")
            repositories[index].lastCheckedDate = Date()
            repositories[index].lastRemoteHash = remoteHash
            repositories[index].lastLocalHeadHash = localHash
            repositories[index].status = .idle
            saveRepositories()

        case .newCommits(let commits, let fromHash, let toHash):
            logger.info("\(self.repositories[index].name) — \(commits.count) commits")
            repositories[index].lastCheckedDate = Date()
            repositories[index].lastRemoteHash = toHash
            repositories[index].lastLocalHeadHash = fromHash
            repositories[index].status = .hasChanges(count: commits.count)
            saveRepositories()
            summarize(repoIndex: index, commits: commits, fromHash: fromHash, toHash: toHash)

        case .error(let message):
            logger.error("\(self.repositories[index].name) — poll error: \(message)")
            repositories[index].status = .error(message)
        }
    }

    // MARK: - Summarization

    private func summarize(repoIndex: Int, commits: [CommitInfo], fromHash: String, toHash: String) {
        // Defer summarization if on battery and setting is enabled
        if settings.deferLLMToBattery && !power.isOnACPower {
            return
        }

        let repo = repositories[repoIndex]
        repositories[repoIndex].status = .summarizing

        // Fold any prior unread summaries for this repo into the new one so
        // the user only has one catch-up summary to read.
        let unreadPrior = historyStore.summaries(for: repo.id)
            .filter { !$0.isRead }
            .sorted { $0.generatedAt < $1.generatedAt }   // oldest first

        let combinedCommits = mergeCommits(priorUnread: unreadPrior, fresh: commits)
        let effectiveFromHash = unreadPrior.first?.fromHash ?? fromHash

        Task {
            let service = currentLLMService()
            do {
                let diffStat = try? await gitCLI?.diff(range: "\(effectiveFromHash)..\(toHash)", in: repo.path)
                let summary = try await service.summarize(
                    commits: combinedCommits,
                    diff: diffStat,
                    repositoryName: repo.name
                )

                let diffSummary = DiffSummary(
                    repositoryID: repo.id,
                    provider: settings.selectedLLMProvider,
                    summary: summary,
                    commits: combinedCommits,
                    fromHash: effectiveFromHash,
                    toHash: toHash
                )

                if let idx = repositories.firstIndex(where: { $0.id == repo.id }) {
                    repositories[idx].latestSummary = diffSummary
                    repositories[idx].status = .idle
                }
                for prior in unreadPrior {
                    historyStore.delete(prior.id)
                }
                historyStore.add(diffSummary)
                sendNotification(repoName: repo.name, commitCount: combinedCommits.count, summary: summary, repoID: repo.id, summaryID: diffSummary.id)
            } catch {
                logger.error("\(repo.name) — summary failed: \(error.localizedDescription)")
                if let idx = repositories.firstIndex(where: { $0.id == repo.id }) {
                    repositories[idx].status = .error("Summary failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func mergeCommits(priorUnread: [DiffSummary], fresh: [CommitInfo]) -> [CommitInfo] {
        guard !priorUnread.isEmpty else { return fresh }

        var seen = Set<String>()
        var merged: [CommitInfo] = []
        for summary in priorUnread {
            for commit in summary.commits where seen.insert(commit.hash).inserted {
                merged.append(commit)
            }
        }
        for commit in fresh where seen.insert(commit.hash).inserted {
            merged.append(commit)
        }

        // Match git log ordering (newest first) and cap at the user's limit.
        merged.sort { $0.timestamp > $1.timestamp }
        let limit = settings.maxCommitsToSummarize
        if merged.count > limit {
            merged = Array(merged.prefix(limit))
        }
        return merged
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

    private func setupScheduleObserver() {
        NotificationCenter.default.addObserver(
            forName: .pollingScheduleChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            restartMonitoring()
            if !isPaused, let git = gitCLI, connectivity.isConnected {
                remotePoller.handleMissedSchedules(gitCLI: git, repositories: repositories)
            }
        }
    }

    private func restartMonitoring() {
        remotePoller.stop()
        startPolling()
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
