import Foundation
import Combine

@MainActor
final class AppViewModel: ObservableObject {

    // MARK: - Configuration

    let installDir: URL
    let scriptName: String
    let launchAgentsDir: URL
    let plistName: String
    let logFilePath: URL
    let tmpStdoutPath: String
    let tmpStderrPath: String
    let notifyFlagPath: String

    var scriptPath: URL { installDir.appendingPathComponent(scriptName) }
    var plistPath: URL { launchAgentsDir.appendingPathComponent(plistName) }

    // MARK: - Published State

    @Published var isInstalled: Bool = false
    @Published var isEnabled: Bool = false
    @Published var isRunning: Bool = false
    @Published var logEntries: [String] = []
    @Published var statusMessage: String = "Checking..."
    @Published var isBusy: Bool = false
    @Published var isNotifyEnabled: Bool = false

    // MARK: - Polling / Log watching

    nonisolated(unsafe) private var pollingTimer: Timer?

    // MARK: - Embedded Content

    let watchdogScript: String = """
#!/bin/zsh
#
# kill_mau.sh — Watchdog that kills Microsoft AutoUpdate on sight
#

TARGETS=(
    "Microsoft AutoUpdate"
    "Microsoft Update Assistant"
)
POLL_INTERVAL=3
LOG_FILE="${HOME}/.local/log/killmau.log"
NOTIFY_FLAG="${HOME}/.local/etc/killmau-notify"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    printf '[%s] %s\\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

notify() {
    if [[ -f "$NOTIFY_FLAG" ]]; then
        osascript -e "display notification \\"$1\\" with title \\"KillOfficeUpdate\\"" 2>/dev/null
    fi
}

log "Watchdog started (PID $$)"

while true; do
    for target in "${TARGETS[@]}"; do
        pids=$(pgrep -f "$target" 2>/dev/null)
        if [[ -n "$pids" ]]; then
            while IFS= read -r pid; do
                if kill -9 "$pid" 2>/dev/null; then
                    log "Killed ${target} (PID ${pid})"
                    notify "Killed ${target} (PID ${pid})"
                fi
            done <<< "$pids"
        fi
    done
    sleep "$POLL_INTERVAL"
done
"""

    private var plistContent: String {
        """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.killmau</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>\(scriptPath.path)</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>\(tmpStdoutPath)</string>
    <key>StandardErrorPath</key>
    <string>\(tmpStderrPath)</string>
</dict>
</plist>
"""
    }

    // MARK: - Lifecycle

    init(
        installDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin"),
        scriptName: String = "kill_mau.sh",
        launchAgentsDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents"),
        plistName: String = "com.user.killmau.plist",
        logFilePath: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/log/killmau.log"),
        tmpStdoutPath: String = "/tmp/killmau.stdout.log",
        tmpStderrPath: String = "/tmp/killmau.stderr.log",
        notifyFlagPath: String = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/etc/killmau-notify").path,
        performSetup: Bool = true
    ) {
        self.installDir = installDir
        self.scriptName = scriptName
        self.launchAgentsDir = launchAgentsDir
        self.plistName = plistName
        self.logFilePath = logFilePath
        self.tmpStdoutPath = tmpStdoutPath
        self.tmpStderrPath = tmpStderrPath
        self.notifyFlagPath = notifyFlagPath

        if performSetup {
            refreshStatus()
            loadLogEntries()
            startPolling()
        }
    }

    deinit {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - Status

    func refreshStatus() {
        isInstalled = FileManager.default.fileExists(atPath: scriptPath.path)
            && FileManager.default.fileExists(atPath: plistPath.path)

        let launchctlResult = ShellExecutor.shell("launchctl list com.user.killmau 2>/dev/null")
        isEnabled = launchctlResult.exitCode == 0

        let pgrepResult = ShellExecutor.shell("pgrep -f '[k]ill_mau'")
        isRunning = pgrepResult.exitCode == 0
            && !pgrepResult.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        isNotifyEnabled = FileManager.default.fileExists(atPath: notifyFlagPath)

        // Auto-update on-disk script if it differs from the embedded version
        if isInstalled,
           let onDisk = try? String(contentsOf: scriptPath, encoding: .utf8),
           onDisk != watchdogScript {
            try? watchdogScript.write(to: scriptPath, atomically: true, encoding: .utf8)
        }

        updateStatusMessage()
    }

    private func updateStatusMessage() {
        if !isInstalled {
            statusMessage = "Not installed"
        } else if isInstalled && isEnabled && isRunning {
            statusMessage = "Active \u{2014} blocking Microsoft updates"
        } else if isInstalled && !isEnabled {
            statusMessage = "Installed but disabled"
        } else {
            statusMessage = "Installed \u{2014} starting up..."
        }
    }

    // MARK: - Polling

    func startPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatus()
                self?.loadLogEntries()
            }
        }
    }

    // MARK: - Log

    func loadLogEntries() {
        guard FileManager.default.fileExists(atPath: logFilePath.path) else {
            logEntries = []
            return
        }
        do {
            let content = try String(contentsOf: logFilePath, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
            let lastHundred = Array(lines.suffix(100))
            logEntries = lastHundred.reversed()
        } catch {
            logEntries = []
        }
    }

    // MARK: - Install

    func install() {
        guard !isBusy else { return }
        isBusy = true
        statusMessage = "Installing..."

        // 1. Kill running Microsoft AutoUpdate processes
        _ = ShellExecutor.shell("pkill -9 \"Microsoft AutoUpdate\" 2>/dev/null; true")
        _ = ShellExecutor.shell("pkill -9 \"Microsoft Update Assistant\" 2>/dev/null; true")

        // 2. Unload user-level Microsoft auto-update agent if it exists
        let msAgentPlist = launchAgentsDir.appendingPathComponent(
            "com.microsoft.update.agent.plist"
        ).path
        if FileManager.default.fileExists(atPath: msAgentPlist) {
            _ = ShellExecutor.shell("launchctl unload -w \"\(msAgentPlist)\" 2>/dev/null; true")
        }

        // 3. Unload system-level Microsoft helper if it exists
        let systemHelper = "/Library/LaunchAgents/com.microsoft.autoupdate.helper.plist"
        if FileManager.default.fileExists(atPath: systemHelper) {
            _ = ShellExecutor.runWithAdmin(
                "launchctl unload -w \"\(systemHelper)\" 2>/dev/null; true"
            )
        }

        // 4. Write watchdog script and make executable
        do {
            try FileManager.default.createDirectory(
                at: installDir,
                withIntermediateDirectories: true
            )
            try watchdogScript.write(to: scriptPath, atomically: true, encoding: .utf8)
            let chmodResult = ShellExecutor.shell("chmod +x \"\(scriptPath.path)\"")
            if chmodResult.exitCode != 0 {
                statusMessage = "Failed to set script permissions."
                isBusy = false
                return
            }
        } catch {
            statusMessage = "Failed to write script: \(error.localizedDescription)"
            isBusy = false
            return
        }

        // 5. Write LaunchAgent plist
        do {
            try FileManager.default.createDirectory(
                at: launchAgentsDir,
                withIntermediateDirectories: true
            )
            try plistContent.write(to: plistPath, atomically: true, encoding: .utf8)
        } catch {
            statusMessage = "Failed to write plist: \(error.localizedDescription)"
            isBusy = false
            return
        }

        // 6. Load LaunchAgent (unload first to handle reinstall/update)
        _ = ShellExecutor.shell("launchctl unload \"\(plistPath.path)\" 2>/dev/null; true")
        let loadResult = ShellExecutor.shell("launchctl load -w \"\(plistPath.path)\"")
        if loadResult.exitCode != 0 {
            statusMessage = "Failed to load LaunchAgent: \(loadResult.output)"
            isBusy = false
            return
        }

        // 7. Ensure log directory exists
        let logDir = logFilePath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: logDir,
            withIntermediateDirectories: true
        )

        // 8. Finalize
        refreshStatus()
        loadLogEntries()
        statusMessage = "Installed and running."
        isBusy = false
    }

    // MARK: - Uninstall

    func uninstall() {
        guard !isBusy else { return }
        isBusy = true
        statusMessage = "Uninstalling..."

        // 1. Unload LaunchAgent (with -w to write disabled override) and delete plist
        _ = ShellExecutor.shell("launchctl unload -w \"\(plistPath.path)\" 2>/dev/null; true")
        try? FileManager.default.removeItem(at: plistPath)

        // 2. Kill running watchdog
        _ = ShellExecutor.shell("pkill -f '[k]ill_mau.sh' 2>/dev/null; true")

        // 3. Delete script file
        try? FileManager.default.removeItem(at: scriptPath)

        // 4. Clean up leftover files (log, temp files, notify flag)
        try? FileManager.default.removeItem(at: logFilePath)
        try? FileManager.default.removeItem(atPath: tmpStdoutPath)
        try? FileManager.default.removeItem(atPath: tmpStderrPath)
        try? FileManager.default.removeItem(atPath: notifyFlagPath)
        logEntries = []

        // 5. Re-enable Microsoft auto-update agent
        let msAgentPlist = launchAgentsDir.appendingPathComponent(
            "com.microsoft.update.agent.plist"
        ).path
        if FileManager.default.fileExists(atPath: msAgentPlist) {
            _ = ShellExecutor.shell("launchctl load -w \"\(msAgentPlist)\" 2>/dev/null; true")
        }

        // 6. Finalize
        refreshStatus()
        statusMessage = "Uninstalled."
        isBusy = false
    }

    // MARK: - Enable / Disable

    func enable() {
        guard !isBusy, isInstalled else { return }
        isBusy = true
        statusMessage = "Enabling..."

        _ = ShellExecutor.shell("launchctl load -w \"\(plistPath.path)\"")
        refreshStatus()

        isBusy = false
    }

    func disable() {
        guard !isBusy, isInstalled else { return }
        isBusy = true
        statusMessage = "Disabling..."

        _ = ShellExecutor.shell("launchctl unload -w \"\(plistPath.path)\" 2>/dev/null; true")
        _ = ShellExecutor.shell("pkill -f '[k]ill_mau.sh' 2>/dev/null; true")
        refreshStatus()

        isBusy = false
    }

    // MARK: - Notifications

    func toggleNotifications() {
        guard isInstalled else { return }

        if isNotifyEnabled {
            // Disable: delete flag file
            try? FileManager.default.removeItem(atPath: notifyFlagPath)
            isNotifyEnabled = false
        } else {
            // Enable: create parent dir + flag file
            let parentDir = (notifyFlagPath as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(
                atPath: parentDir,
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: notifyFlagPath, contents: nil)
            isNotifyEnabled = true
        }
    }

    // MARK: - Clean Up

    func cleanUp() {
        guard !isBusy, isInstalled else { return }
        isBusy = true
        statusMessage = "Cleaning up..."

        // 1. Truncate log file (not delete — watchdog may still be writing)
        if FileManager.default.fileExists(atPath: logFilePath.path) {
            try? "".write(to: logFilePath, atomically: false, encoding: .utf8)
        }

        // 2. Delete temp files (silently skip if missing)
        try? FileManager.default.removeItem(atPath: tmpStdoutPath)
        try? FileManager.default.removeItem(atPath: tmpStderrPath)

        // 3. Clear log viewer
        logEntries = []

        // 4. Finalize
        refreshStatus()
        statusMessage = "Cleaned up successfully"
        isBusy = false
    }
}
