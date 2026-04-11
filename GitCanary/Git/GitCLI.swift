import Foundation

enum GitError: LocalizedError {
    case binaryNotFound(String)
    case notARepository(String)
    case commandFailed(String, Int32)
    case timeout
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let path): "Git not found at \(path)"
        case .notARepository(let path): "\(path) is not a git repository"
        case .commandFailed(let message, let code): "Git failed (\(code)): \(message)"
        case .timeout: "Git operation timed out"
        case .parseError(let message): "Failed to parse git output: \(message)"
        }
    }
}

struct GitOutput {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

struct RemoteRef: Equatable {
    let hash: String
    let ref: String

    var branchName: String {
        if ref.hasPrefix("refs/heads/") {
            return String(ref.dropFirst("refs/heads/".count))
        }
        return ref
    }
}

actor GitCLI {
    let binaryPath: String

    init(binaryPath: String) {
        self.binaryPath = binaryPath
    }

    static func findGitBinary() -> String? {
        let candidates = ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Try `which git`
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["git"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path, FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        } catch {}
        return nil
    }

    static func isAvailable(at path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    func run(_ arguments: [String], in directory: String, timeout: TimeInterval = 30) async throws -> GitOutput {
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            throw GitError.binaryNotFound(binaryPath)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: directory)

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            var didResume = false
            let lock = NSLock()

            func resume(with result: Result<GitOutput, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }

            let timeoutWork = DispatchWorkItem {
                process.terminate()
                resume(with: .failure(GitError.timeout))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

            process.terminationHandler = { _ in
                timeoutWork.cancel()
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let output = GitOutput(
                    stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                    stderr: String(data: stderrData, encoding: .utf8) ?? "",
                    exitCode: process.terminationStatus
                )
                resume(with: .success(output))
            }

            do {
                try process.run()
            } catch {
                timeoutWork.cancel()
                resume(with: .failure(error))
            }
        }
    }

    func isGitRepository(at path: String) async throws -> Bool {
        let output = try await run(["rev-parse", "--is-inside-work-tree"], in: path)
        return output.exitCode == 0 && output.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    func lsRemote(remote: String, in directory: String) async throws -> [RemoteRef] {
        let output = try await run(["ls-remote", "--heads", remote], in: directory)
        guard output.exitCode == 0 else {
            throw GitError.commandFailed(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines), output.exitCode)
        }

        return output.stdout
            .split(separator: "\n")
            .compactMap { line -> RemoteRef? in
                let parts = line.split(separator: "\t", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                return RemoteRef(hash: String(parts[0]), ref: String(parts[1]))
            }
    }

    func fetch(remote: String, in directory: String) async throws {
        let output = try await run(["fetch", remote, "--prune"], in: directory, timeout: 60)
        guard output.exitCode == 0 else {
            throw GitError.commandFailed(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines), output.exitCode)
        }
    }

    func log(range: String, in directory: String, maxCount: Int = 50) async throws -> String {
        let output = try await run([
            "log",
            "--pretty=format:COMMIT|%H|%an|%ae|%at|%s",
            "--numstat",
            "--max-count=\(maxCount)",
            range,
        ], in: directory)
        guard output.exitCode == 0 else {
            throw GitError.commandFailed(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines), output.exitCode)
        }
        return output.stdout
    }

    func diff(range: String, in directory: String, maxLines: Int = 500) async throws -> String {
        let output = try await run([
            "diff",
            "--stat",
            range,
        ], in: directory)
        guard output.exitCode == 0 else {
            throw GitError.commandFailed(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines), output.exitCode)
        }
        return output.stdout
    }

    func revParse(_ ref: String, in directory: String) async throws -> String {
        let output = try await run(["rev-parse", ref], in: directory)
        guard output.exitCode == 0 else {
            throw GitError.commandFailed(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines), output.exitCode)
        }
        return output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func currentBranch(in directory: String) async throws -> String {
        let output = try await run(["branch", "--show-current"], in: directory)
        guard output.exitCode == 0 else {
            throw GitError.commandFailed(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines), output.exitCode)
        }
        return output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func remotes(in directory: String) async throws -> [String] {
        let output = try await run(["remote"], in: directory)
        guard output.exitCode == 0 else {
            throw GitError.commandFailed(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines), output.exitCode)
        }
        return output.stdout
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
