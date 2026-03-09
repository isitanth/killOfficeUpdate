import Foundation

struct ShellResult {
    let output: String
    let exitCode: Int32
}

enum ShellExecutor {

    static func run(_ command: String, args: [String] = []) -> ShellResult {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ShellResult(output: error.localizedDescription, exitCode: -1)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return ShellResult(output: output, exitCode: process.terminationStatus)
    }

    static func shell(_ command: String) -> ShellResult {
        run("/bin/zsh", args: ["-c", command])
    }

    static func runWithAdmin(_ command: String) -> ShellResult {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return run("/usr/bin/osascript", args: [
            "-e",
            "do shell script \"\(escaped)\" with administrator privileges"
        ])
    }
}
