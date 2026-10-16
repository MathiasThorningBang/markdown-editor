import AppKit

/// Check for Updates. The app is built from a clone of the repo, and
/// `build.sh` stamps the clone's path and commit into Info.plist, so updating
/// is `git pull` and the same build again, then a relaunch.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    enum State: Equatable {
        case idle, checking, upToDate, available(Int), updating, failed(String)
    }

    @Published private(set) var state = State.idle

    private let repo = Bundle.main.object(forInfoDictionaryKey: "NMSourceRepository") as? String
    private let commit = Bundle.main.object(forInfoDictionaryKey: "NMSourceCommit") as? String

    /// False for a build without the stamp (`swift run`, or a clone without git).
    var canUpdate: Bool { repo != nil && commit != nil }

    var hasUpdate: Bool {
        if case .available = state { true } else { false }
    }

    /// Fetches main and counts the commits this build doesn't have. A quiet
    /// check (at launch) stays silent when offline or nothing is new.
    func check(quietly: Bool = false) {
        guard let repo, let commit, state != .checking, state != .updating else { return }
        state = .checking
        Task {
            do {
                try await Self.run("git fetch --quiet origin main", in: repo)
                let count = Int(try await Self.run("git rev-list --count \(commit)..origin/main", in: repo)
                    .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                state = count > 0 ? .available(count) : .upToDate
                if !quietly {
                    AppModel.shared.session.showToast(count > 0 ? "Update available" : "Up to date")
                }
            } catch {
                state = quietly ? .idle : .failed(error.localizedDescription)
            }
        }
    }

    /// Pulls main, builds the same variant as this app and relaunches it.
    func update() {
        guard let repo, state != .updating, state != .checking else { return }
        state = .updating
        Task {
            do {
                // Fast-forward main only, so local work on another branch is never touched.
                let branch = try await Self.run("git rev-parse --abbrev-ref HEAD", in: repo)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard branch == "main" else {
                    throw Failure("\(repo) is on the branch \(branch). Switch it to main to update.")
                }
                #if Kokoro
                let build = "KOKORO=1 ./build.sh"
                #else
                let build = "./build.sh"
                #endif
                // Like the README's update command, the agent skills too if they're installed.
                let skills = "if [ -d ~/.claude/skills/md-editor ]; then cp -R skills/md-editor skills/md-canvas ~/.claude/skills/; fi"
                try await Self.run("git pull --ff-only --quiet origin main && \(build) && \(skills)", in: repo)
                relaunch()
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Opens the freshly installed app once this one has quit. If quitting is
    /// cancelled (unsaved changes), it opens whenever the app does quit.
    private func relaunch() {
        let script = "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; open \"$0\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }

    /// Runs a command in the user's login shell, as from Terminal. Output goes
    /// to a file, not a pipe: a build prints more than a pipe holds.
    @discardableResult
    nonisolated private static func run(_ command: String, in directory: String) async throws -> String {
        let log = FileManager.default.temporaryDirectory.appending(path: "MarkdownEditor-update-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: log) }
        let handle = try FileHandle(forWritingTo: log)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        try? handle.close()
        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        guard process.terminationStatus == 0 else {
            // The last lines say what went wrong (a git message or a compiler error).
            let lines = output.split(separator: "\n").suffix(3).joined(separator: " ")
            throw Failure(lines.isEmpty ? "\(command) failed." : lines)
        }
        return output
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
