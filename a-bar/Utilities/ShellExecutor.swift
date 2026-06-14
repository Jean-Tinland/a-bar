import Foundation

/// Utility for executing shell commands
enum ShellExecutor {

    /// Default timeout for shell commands (10 seconds).
    /// Prevents hung processes from blocking the GCD thread pool indefinitely,
    /// which is the primary cause of the app becoming unresponsive.
    private static let defaultTimeout: TimeInterval = 10

    /// Shared PATH prefix prepended to every child process.
    private static let pathPrefix = "/usr/local/bin:/opt/homebrew/bin"

    /// Build an environment dictionary with a reliable PATH.
    static func shellEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let existing = env["PATH"] {
            env["PATH"] = "\(pathPrefix):\(existing)"
        } else {
            env["PATH"] = "\(pathPrefix):/usr/bin:/bin"
        }
        return env
    }

    private static func makeProcess(command: String, stdout: Any?, stderr: Any?) -> Process {
        let process = Process()
        process.standardOutput = stdout
        process.standardError = stderr
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.environment = shellEnvironment()
        return process
    }

    private static func scheduleTimeoutWatchdog(for process: Process, timeout: TimeInterval) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler {
            if process.isRunning {
                process.terminate()  // SIGTERM
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
        timer.resume()
        return timer
    }

    private static func readString(from pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Execute a shell command and return the output.
    ///
    /// A per-command `timeout` (seconds) prevents runaway processes from
    /// exhausting the cooperative thread pool.  The process is killed with
    /// SIGTERM (then SIGKILL) when the deadline expires.
    @discardableResult
    static func run(_ command: String, timeout: TimeInterval = defaultTimeout) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let pipe = Pipe()
                let process = makeProcess(command: command, stdout: pipe, stderr: pipe)

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let timer = scheduleTimeoutWatchdog(for: process, timeout: timeout)
                defer { timer.cancel() }

                process.waitUntilExit()
                continuation.resume(returning: readString(from: pipe))
            }
        }
    }

    /// The result of running a custom widget script.
    struct WidgetRunResult {
        /// Raw stdout output from the script.
        let stdout: String
        /// Raw stderr output from the script (empty on success).
        let stderr: String
        /// Process exit code. 0 means success.
        let exitCode: Int32

        var succeeded: Bool { exitCode == 0 }
    }

    /// Run a widget script with stdout and stderr captured separately.
    ///
    /// Unlike `run(_:)`, this method never throws. Errors (process launch
    /// failures, non-zero exit codes) are encoded in the returned result so
    /// widgets can display them without crashing the bar.
    static func runWidget(_ command: String, timeout: TimeInterval = defaultTimeout) async -> WidgetRunResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let process = makeProcess(command: command, stdout: stdoutPipe, stderr: stderrPipe)

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: WidgetRunResult(
                        stdout: "",
                        stderr: "Could not start script: \(error.localizedDescription)",
                        exitCode: -1
                    ))
                    return
                }

                let timer = scheduleTimeoutWatchdog(for: process, timeout: timeout)
                defer { timer.cancel() }

                process.waitUntilExit()
                let stdout = readString(from: stdoutPipe)
                let stderr = readString(from: stderrPipe)

                continuation.resume(returning: WidgetRunResult(
                    stdout: stdout,
                    stderr: stderr,
                    exitCode: process.terminationStatus
                ))
            }
        }
    }

    /// Execute a shell command synchronously (use sparingly – never on the main thread).
    @discardableResult
    static func runSync(_ command: String, timeout: TimeInterval = defaultTimeout) -> String {
        let pipe = Pipe()
        let process = makeProcess(command: command, stdout: pipe, stderr: pipe)

        do {
            try process.run()
        } catch {
            return ""
        }

        let timer = scheduleTimeoutWatchdog(for: process, timeout: timeout)
        defer { timer.cancel() }

        process.waitUntilExit()
        return readString(from: pipe)
    }
    
    /// Run command in user's terminal app
    static func runInTerminal(_ command: String, terminal: String = "Terminal") {
        let script: String
        
        switch terminal {
        case "iTerm2":
            script = """
            tell application "iTerm"
                activate
                set newWindow to (create window with default profile)
                tell current session of newWindow
                    write text "\(command)"
                end tell
            end tell
            """
        default:
            script = """
            tell application "Terminal"
                activate
                do script "\(command)"
            end tell
            """
        }
        
        Task {
            _ = try? await run("osascript -e '\(script)'")
        }
    }
}
