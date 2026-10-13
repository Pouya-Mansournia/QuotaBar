import Foundation

struct CLIResult: Sendable, Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum CLIError: Error, Equatable, Sendable {
    case timedOut
    case launchFailed(String)
}

protocol CLIExecuting: Sendable {
    func execute(executable: URL, arguments: [String], timeout: Duration) async throws -> CLIResult
}

/// Runs a local executable directly — never through a shell — with a hard timeout.
struct CLIExecutor: CLIExecuting {
    /// Prepended to PATH for the child process. GUI apps inherit a minimal
    /// PATH, and tools such as `claude` are scripts that need to find `node`.
    var extraPathDirectories: [String] = CLILocator.defaultSearchDirectories()

    func execute(executable: URL, arguments: [String], timeout: Duration) async throws -> CLIResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        let inheritedPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = (extraPathDirectories + [inheritedPath]).joined(separator: ":")
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let handle = ProcessHandle(process: process)

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: CLIResult.self) { group in
                group.addTask { try await handle.run() }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw CLIError.timedOut
                }
                defer { group.cancelAll() }
                do {
                    // The group always holds two tasks, so next() cannot be nil here.
                    return try await group.next()!
                } catch {
                    handle.terminate()
                    throw error
                }
            }
        } onCancel: {
            handle.terminate()
        }
    }
}

/// Owns a `Process` across the concurrency boundary. `Process` itself is not
/// Sendable; access is confined to `run()` plus thread-safe terminate calls.
private final class ProcessHandle: @unchecked Sendable {
    private let process: Process

    init(process: Process) {
        self.process = process
    }

    func run() async throws -> CLIResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [process] in
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: CLIError.launchFailed(error.localizedDescription))
                    return
                }

                // Drain stderr on a second thread so a chatty process cannot
                // fill one pipe while we block reading the other.
                let stderrBuffer = DataBuffer()
                let stderrDone = DispatchSemaphore(value: 0)
                DispatchQueue.global(qos: .utility).async {
                    stderrBuffer.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    stderrDone.signal()
                }
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                stderrDone.wait()
                process.waitUntilExit()

                continuation.resume(returning: CLIResult(
                    exitCode: process.terminationStatus,
                    stdout: String(decoding: stdoutData, as: UTF8.self),
                    stderr: String(decoding: stderrBuffer.data, as: UTF8.self)
                ))
            }
        }
    }

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
        // Escalate if the process ignores SIGTERM.
        let pid = process.processIdentifier
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [process] in
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }
}

private final class DataBuffer: @unchecked Sendable {
    var data = Data()
}
