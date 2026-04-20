import Foundation
import os

enum PollResult {
    case noChanges
    case syncedSilently(localHash: String?, remoteHash: String)
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

        if settings.pollingMode == .interval || settings.pollingMode == .both {
            let interval = TimeInterval(settings.pollIntervalMinutes * 60)
            if now.timeIntervalSince(appLastActive) >= interval {
                checkNow(gitCLI: gitCLI, repositories: repositories)
                return
            }
        }

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

            // Reset cached hashes when the monitored branch changed
            let branchChanged = repo.activeBranch != nil && repo.activeBranch != effectiveBranch
            let lastRemote = branchChanged ? nil : repo.lastRemoteHash
            let lastLocal = branchChanged ? nil : repo.lastLocalHeadHash

            // Local tip for the monitored branch (nil if the branch doesn't
            // exist locally yet — e.g., fresh clone without it checked out).
            let localBranchHash = try? await gitCLI.revParse(effectiveBranch, in: directory)

            // Fast path: nothing moved on either side since last poll.
            if lastLocal == localBranchHash, lastRemote == remoteHash {
                return ResolvedPoll(result: .noChanges, activeBranch: effectiveBranch)
            }

            // First poll (or branch switch): silently baseline the hashes
            // without summarizing or notifying.
            if lastLocal == nil, lastRemote == nil {
                return ResolvedPoll(
                    result: .syncedSilently(localHash: localBranchHash, remoteHash: remoteHash),
                    activeBranch: effectiveBranch
                )
            }

            // Something moved — fetch new objects so localBranchHash..remoteHash is computable.
            try await gitCLI.fetch(remote: repo.remoteName, in: directory)

            // Without a local counterpart there's nothing to diff against;
            // baseline silently.
            guard let localBranchHash else {
                return ResolvedPoll(
                    result: .syncedSilently(localHash: nil, remoteHash: remoteHash),
                    activeBranch: effectiveBranch
                )
            }

            let maxCount = AppSettings.shared.maxCommitsToSummarize
            let logOutput = try await gitCLI.log(
                range: "\(localBranchHash)..\(remoteHash)",
                in: directory,
                maxCount: maxCount
            )
            let commits = GitLogParser.parse(logOutput)

            if commits.isEmpty {
                // Remote hash moved but local already contains the remote tip
                // (user pulled, or remote rewound) — no unpulled work.
                return ResolvedPoll(
                    result: .syncedSilently(localHash: localBranchHash, remoteHash: remoteHash),
                    activeBranch: effectiveBranch
                )
            }

            return ResolvedPoll(
                result: .newCommits(
                    commits: commits,
                    fromHash: localBranchHash,
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
