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
    private static func shellEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let existing = env["PATH"] {
            env["PATH"] = "\(pathPrefix):\(existing)"
        } else {
            env["PATH"] = "\(pathPrefix):/usr/bin:/bin"
        }
        return env
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
                let process = Process()
                let pipe = Pipe()

                process.standardOutput = pipe
                process.standardError = pipe
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", command]
                process.environment = shellEnvironment()

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                // Arm a timeout watchdog so a hung process never blocks forever.
                let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler {
                    if process.isRunning {
                        process.terminate()                 // SIGTERM
                        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                        }
                    }
                }
                timer.resume()

                process.waitUntilExit()
                timer.cancel()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            }
        }
    }

    /// Execute a shell command synchronously (use sparingly – never on the main thread).
    @discardableResult
    static func runSync(_ command: String, timeout: TimeInterval = defaultTimeout) -> String {
        let process = Process()
        let pipe = Pipe()

        process.standardOutput = pipe
        process.standardError = pipe
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.environment = shellEnvironment()

        do {
            try process.run()
        } catch {
            return ""
        }

        // Arm a timeout watchdog.
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler {
            if process.isRunning {
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
        timer.resume()

        process.waitUntilExit()
        timer.cancel()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
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
