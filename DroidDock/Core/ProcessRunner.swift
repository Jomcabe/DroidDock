import Foundation

/// Result of a finished child process.
struct ProcessResult {
    let exitCode: Int32
    let stdoutData: Data
    let stderrData: Data

    var succeeded: Bool { exitCode == 0 }
    var stdout: String { String(decoding: stdoutData, as: UTF8.self) }
    var stderr: String { String(decoding: stderrData, as: UTF8.self) }

    /// Trimmed stdout, convenient for single-value command output.
    var trimmedStdout: String { stdout.trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum ProcessRunnerError: LocalizedError {
    case launchFailed(String)
    case nonZeroExit(code: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let why):
            return "Failed to launch process: \(why)"
        case .nonZeroExit(let code, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "Process exited with status \(code)\(detail.isEmpty ? "" : ": \(detail)")"
        }
    }
}

/// Thin async wrapper around `Foundation.Process`.
///
/// `run(...)` collects stdout/stderr to completion, draining both pipes on
/// separate threads so a chatty child can't deadlock on a full pipe buffer
/// (important for binary-heavy output like `screencap -p`). `launch(...)`
/// returns a configured, running `Process` for long-lived children (scrcpy)
/// that the caller manages and terminates.
enum ProcessRunner {

    /// Run to completion and capture output. Optionally throws on non-zero exit.
    @discardableResult
    static func run(
        _ executableURL: URL,
        arguments: [String],
        environment extraEnvironment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        throwsOnFailure: Bool = false
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = configuredProcess(
                    executableURL: executableURL,
                    arguments: arguments,
                    extraEnvironment: extraEnvironment,
                    currentDirectory: currentDirectory
                )
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ProcessRunnerError.launchFailed(error.localizedDescription))
                    return
                }

                // Drain both pipes concurrently to avoid buffer deadlocks.
                var outData = Data()
                var errData = Data()
                let group = DispatchGroup()
                let ioQueue = DispatchQueue(label: "com.droiddock.process.io", attributes: .concurrent)

                group.enter()
                ioQueue.async {
                    outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                ioQueue.async {
                    errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                process.waitUntilExit()
                group.wait()

                let result = ProcessResult(
                    exitCode: process.terminationStatus,
                    stdoutData: outData,
                    stderrData: errData
                )

                if throwsOnFailure && !result.succeeded {
                    continuation.resume(throwing: ProcessRunnerError.nonZeroExit(
                        code: result.exitCode, stderr: result.stderr))
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// Configure and start a long-lived process. Output is sent to the null
    /// device by default (scrcpy is noisy); pass `inheritOutput: true` to debug.
    /// The caller owns the returned `Process` and is responsible for termination.
    @discardableResult
    static func launch(
        _ executableURL: URL,
        arguments: [String],
        environment extraEnvironment: [String: String]? = nil,
        inheritOutput: Bool = false,
        terminationHandler: ((Process) -> Void)? = nil
    ) throws -> Process {
        let process = configuredProcess(
            executableURL: executableURL,
            arguments: arguments,
            extraEnvironment: extraEnvironment,
            currentDirectory: nil
        )
        if !inheritOutput {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = terminationHandler

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }
        return process
    }

    // MARK: - Internals

    private static func configuredProcess(
        executableURL: URL,
        arguments: [String],
        extraEnvironment: [String: String]?,
        currentDirectory: URL?
    ) -> Process {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }

        if let extraEnvironment {
            var env = ProcessInfo.processInfo.environment
            for (key, value) in extraEnvironment { env[key] = value }
            process.environment = env
        }
        return process
    }
}
