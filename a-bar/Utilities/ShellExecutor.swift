import Foundation

/// Utility for executing shell commands
enum ShellExecutor {
    
    /// Execute a shell command and return the output
    @discardableResult
    static func run(_ command: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                
                process.standardOutput = pipe
                process.standardError = pipe
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", command]
                
                // Ensure proper PATH environment for built apps
                var env = ProcessInfo.processInfo.environment
                if let existingPath = env["PATH"] {
                    env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:\(existingPath)"
                } else {
                    env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
                }
                process.environment = env
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else {
                        // Some commands return non-zero but still produce useful output
                        continuation.resume(returning: output)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Execute a shell command synchronously (use sparingly)
    @discardableResult
    static func runSync(_ command: String) -> String {
        let process = Process()
        let pipe = Pipe()
        
        process.standardOutput = pipe
        process.standardError = pipe
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        
        // Ensure proper PATH environment for built apps
        var env = ProcessInfo.processInfo.environment
        if let existingPath = env["PATH"] {
            env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:\(existingPath)"
        } else {
            env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        }
        process.environment = env
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
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
