import Foundation
import os

enum PollResult {
    case noChanges
    case newCommits(commits: [CommitInfo], fromHash: String, toHash: String)
    case error(String)
}

@Observable
final class RemotePoller {
    private var intervalTimer: Timer?
    private var scheduleTimer: Timer?
    private let settings = AppSettings.shared

    private let logger = Logger(subsystem: "com.jordiboehme.GitCanary", category: "RemotePoller")
    private(set) var lastError: String?
    private(set) var nextScheduledCheck: Date?

    var onPollResult: ((UUID, PollResult) -> Void)?

    func start(gitCLI: GitCLI, repositories: [Repository]) {
        stop()
        setupTimers(gitCLI: gitCLI, repositories: repositories)
    }

    func stop() {
        intervalTimer?.invalidate()
        intervalTimer = nil
        scheduleTimer?.invalidate()
        scheduleTimer = nil
    }

    func checkNow(gitCLI: GitCLI, repositories: [Repository]) {
        Task {
            await pollAll(gitCLI: gitCLI, repositories: repositories)
        }
    }

    func handleMissedSchedules(gitCLI: GitCLI, repositories: [Repository]) {
        let now = Date()
        let appLastActive = UserDefaults.standard.object(forKey: "lastActiveDate") as? Date ?? now

        for schedule in settings.scheduledChecks {
            if schedule.lastMissedDate(since: appLastActive, now: now) != nil {
                checkNow(gitCLI: gitCLI, repositories: repositories)
                return
            }
        }
    }

    // MARK: - Private

    private func setupTimers(gitCLI: GitCLI, repositories: [Repository]) {
        let mode = settings.pollingMode

        if mode == .interval || mode == .both {
            let interval = TimeInterval(settings.pollIntervalMinutes * 60)
            intervalTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task { await self.pollAll(gitCLI: gitCLI, repositories: repositories) }
            }
        }

        if mode == .scheduled || mode == .both {
            scheduleNextCheck(gitCLI: gitCLI, repositories: repositories)
        }
    }

    private func scheduleNextCheck(gitCLI: GitCLI, repositories: [Repository]) {
        scheduleTimer?.invalidate()

        let now = Date()
        let nextDates = settings.scheduledChecks.compactMap { $0.nextFireDate(after: now) }
        guard let soonest = nextDates.min() else {
            nextScheduledCheck = nil
            return
        }

        nextScheduledCheck = soonest
        let delay = soonest.timeIntervalSince(now)

        scheduleTimer = Timer.scheduledTimer(withTimeInterval: max(delay, 1), repeats: false) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.pollAll(gitCLI: gitCLI, repositories: repositories)
                self.markScheduleExecuted(at: soonest)
                self.scheduleNextCheck(gitCLI: gitCLI, repositories: repositories)
            }
        }
    }

    private func markScheduleExecuted(at date: Date) {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)

        for i in settings.scheduledChecks.indices {
            if settings.scheduledChecks[i].hour == hour && settings.scheduledChecks[i].minute == minute {
                settings.scheduledChecks[i].lastExecutedDate = Date()
            }
        }
    }

    private func pollAll(gitCLI: GitCLI, repositories: [Repository]) async {
        UserDefaults.standard.set(Date(), forKey: "lastActiveDate")

        for repo in repositories where repo.isEnabled {
            let result = await poll(repo, gitCLI: gitCLI)
            onPollResult?(repo.id, result)
        }
    }

    func poll(_ repo: Repository, gitCLI: GitCLI) async -> PollResult {
        logger.info("Polling \(repo.name) (\(repo.remoteName)/\(repo.trackingBranch))")
        do {
            let directory: String
            if let bookmarkData = repo.bookmarkData {
                let url = try BookmarkManager.resolveBookmark(bookmarkData)
                guard url.startAccessingSecurityScopedResource() else {
                    logger.error("\(repo.name) — cannot access repository (security scope)")
                    return .error("Cannot access repository")
                }
                defer { url.stopAccessingSecurityScopedResource() }
                directory = url.path
            } else {
                directory = repo.path
            }

            // Lightweight check: ls-remote
            let refs = try await gitCLI.lsRemote(remote: repo.remoteName, in: directory)
            let remoteRef = refs.first { $0.branchName == repo.trackingBranch }
            guard let remoteHash = remoteRef?.hash else {
                logger.error("\(repo.name) — branch \(repo.trackingBranch) not found on \(repo.remoteName)")
                return .error("Branch \(repo.trackingBranch) not found on \(repo.remoteName)")
            }

            // Compare with last known hash
            if let lastHash = repo.lastRemoteHash, lastHash == remoteHash {
                return .noChanges
            }

            // Fetch new objects
            try await gitCLI.fetch(remote: repo.remoteName, in: directory)

            // Get commit log
            let maxCount = AppSettings.shared.maxCommitsToSummarize
            let range: String
            let fromHash: String

            if let lastHash = repo.lastRemoteHash {
                // Incremental: only new commits since last check
                range = "\(lastHash)..\(remoteHash)"
                fromHash = lastHash
            } else {
                // First check: get recent commits from the branch
                range = "\(repo.remoteName)/\(repo.trackingBranch)"
                fromHash = ""
            }

            let logOutput = try await gitCLI.log(
                range: range,
                in: directory,
                maxCount: maxCount
            )
            let commits = GitLogParser.parse(logOutput)

            if commits.isEmpty {
                return .noChanges
            }

            return .newCommits(
                commits: commits,
                fromHash: fromHash.isEmpty ? (commits.last?.hash ?? remoteHash) : fromHash,
                toHash: remoteHash
            )

        } catch {
            logger.error("\(repo.name) — poll failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
            return .error(error.localizedDescription)
        }
    }
}
