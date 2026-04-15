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

    var onPollResult: ((UUID, ResolvedPoll) -> Void)?

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
            let resolved = await poll(repo, gitCLI: gitCLI)
            onPollResult?(repo.id, resolved)
        }
    }

    struct ResolvedPoll {
        let result: PollResult
        let activeBranch: String?
    }

    func poll(_ repo: Repository, gitCLI: GitCLI) async -> ResolvedPoll {
        logger.info("Polling \(repo.name) (\(repo.remoteName)/\(repo.trackingBranch)) mode=\(repo.branchMode.rawValue)")
        do {
            let directory: String
            if let bookmarkData = repo.bookmarkData {
                let url = try BookmarkManager.resolveBookmark(bookmarkData)
                guard url.startAccessingSecurityScopedResource() else {
                    logger.error("\(repo.name) — cannot access repository (security scope)")
                    return ResolvedPoll(result: .error("Cannot access repository"), activeBranch: nil)
                }
                defer { url.stopAccessingSecurityScopedResource() }
                directory = url.path
            } else {
                directory = repo.path
            }

            // Lightweight check: ls-remote
            let refs = try await gitCLI.lsRemote(remote: repo.remoteName, in: directory)

            // Resolve effective branch
            let effectiveBranch: String
            switch repo.branchMode {
            case .fixed:
                effectiveBranch = repo.trackingBranch
            case .auto:
                effectiveBranch = await resolveAutoBranch(
                    repo: repo, refs: refs, gitCLI: gitCLI, directory: directory
                )
            }

            let remoteRef = refs.first { $0.branchName == effectiveBranch }
            guard let remoteHash = remoteRef?.hash else {
                logger.error("\(repo.name) — branch \(effectiveBranch) not found on \(repo.remoteName)")
                return ResolvedPoll(
                    result: .error("Branch \(effectiveBranch) not found on \(repo.remoteName)"),
                    activeBranch: effectiveBranch
                )
            }

            // Reset lastRemoteHash when the monitored branch changed
            let branchChanged = repo.activeBranch != nil && repo.activeBranch != effectiveBranch
            let lastHash = branchChanged ? nil : repo.lastRemoteHash

            // Compare with last known hash
            if let lastHash, lastHash == remoteHash {
                return ResolvedPoll(result: .noChanges, activeBranch: effectiveBranch)
            }

            // Fetch new objects
            try await gitCLI.fetch(remote: repo.remoteName, in: directory)

            // Get commit log
            let maxCount = AppSettings.shared.maxCommitsToSummarize
            let range: String
            let fromHash: String

            if let lastHash {
                range = "\(lastHash)..\(remoteHash)"
                fromHash = lastHash
            } else {
                range = "\(repo.remoteName)/\(effectiveBranch)"
                fromHash = ""
            }

            let logOutput = try await gitCLI.log(
                range: range,
                in: directory,
                maxCount: maxCount
            )
            let commits = GitLogParser.parse(logOutput)

            if commits.isEmpty {
                return ResolvedPoll(result: .noChanges, activeBranch: effectiveBranch)
            }

            return ResolvedPoll(
                result: .newCommits(
                    commits: commits,
                    fromHash: fromHash.isEmpty ? (commits.last?.hash ?? remoteHash) : fromHash,
                    toHash: remoteHash
                ),
                activeBranch: effectiveBranch
            )

        } catch {
            logger.error("\(repo.name) — poll failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
            return ResolvedPoll(result: .error(error.localizedDescription), activeBranch: nil)
        }
    }

    private func resolveAutoBranch(
        repo: Repository, refs: [RemoteRef], gitCLI: GitCLI, directory: String
    ) async -> String {
        // 1. Try current local branch
        if let current = try? await gitCLI.currentBranch(in: directory),
           !current.isEmpty,
           refs.contains(where: { $0.branchName == current })
        {
            return current
        }

        // 2. Fall back to stored tracking branch
        if refs.contains(where: { $0.branchName == repo.trackingBranch }) {
            return repo.trackingBranch
        }

        // 3. Fall back to remote's default branch
        if let defaultBranch = try? await gitCLI.defaultBranch(remote: repo.remoteName, in: directory),
           refs.contains(where: { $0.branchName == defaultBranch })
        {
            return defaultBranch
        }

        // 4. Last resort: use stored tracking branch (will produce an error)
        return repo.trackingBranch
    }
}
