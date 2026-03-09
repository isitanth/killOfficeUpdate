# KillOfficeUpdate GUI App — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a native SwiftUI macOS 26 app with Liquid Glass design that manages the Microsoft Office update blocker (install, uninstall, enable, disable) with a log viewer.

**Architecture:** MVVM with 4 Swift files — `ShellExecutor` wraps `Process` for shell commands and `osascript` for sudo, `AppViewModel` manages all state and system logic, `ContentView` renders the Liquid Glass UI, and the `@main` app struct configures the window.

**Tech Stack:** Swift, SwiftUI, macOS 26 SDK, Liquid Glass APIs (`.glassEffect()`), Foundation `Process`, `DispatchSource` for file watching.

**Design doc:** `docs/plans/2026-03-09-gui-app-design.md`

---

### Task 1: Create Xcode Project

**Files:**
- Create: `KillOfficeUpdateApp/KillOfficeUpdateApp.xcodeproj` (via Xcode)

**Step 1: Create new Xcode project**

In Xcode:
1. File > New > Project
2. macOS > App
3. Product Name: `KillOfficeUpdateApp`
4. Organization Identifier: `com.user`
5. Interface: SwiftUI
6. Language: Swift
7. Deployment Target: macOS 26.0
8. Save inside `/Users/anthonychambet/Downloads/killOfficeUpdate/`

This creates the project with a default `ContentView.swift` and app entry point.

**Step 2: Verify it builds**

Run: `xcodebuild -project KillOfficeUpdateApp/KillOfficeUpdateApp.xcodeproj -scheme KillOfficeUpdateApp build`
Expected: BUILD SUCCEEDED

---

### Task 2: Implement ShellExecutor

**Files:**
- Create: `KillOfficeUpdateApp/KillOfficeUpdateApp/ShellExecutor.swift`

**Step 1: Create ShellExecutor.swift**

```swift
import Foundation

struct ShellResult {
    let output: String
    let exitCode: Int32
}

enum ShellExecutor {

    /// Run a command with arguments, returns output and exit code
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
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ShellResult(output: output, exitCode: process.terminationStatus)
    }

    /// Run a shell command string via /bin/zsh
    static func shell(_ command: String) -> ShellResult {
        run("/bin/zsh", args: ["-c", command])
    }

    /// Run a command with administrator privileges via osascript
    static func runWithAdmin(_ command: String) -> ShellResult {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        return run("/usr/bin/osascript", args: ["-e", script])
    }
}
```

**Step 2: Verify it builds**

Run: `xcodebuild -project KillOfficeUpdateApp/KillOfficeUpdateApp.xcodeproj -scheme KillOfficeUpdateApp build`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add KillOfficeUpdateApp/KillOfficeUpdateApp/ShellExecutor.swift
git commit -m "feat: add ShellExecutor for Process and osascript sudo"
```

---

### Task 3: Implement AppViewModel

**Files:**
- Create: `KillOfficeUpdateApp/KillOfficeUpdateApp/AppViewModel.swift`

**Step 1: Create AppViewModel.swift**

```swift
import Foundation
import Combine

@MainActor
final class AppViewModel: ObservableObject {

    // MARK: - Constants

    private let installDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin")
    private let scriptName = "kill_mau.sh"
    private let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents")
    private let plistName = "com.user.killmau.plist"
    private let logFilePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/log/killmau.log")

    private var scriptPath: URL { installDir.appendingPathComponent(scriptName) }
    private var plistPath: URL { launchAgentsDir.appendingPathComponent(plistName) }

    // MARK: - Published State

    @Published var isInstalled = false
    @Published var isEnabled = false
    @Published var isRunning = false
    @Published var logEntries: [String] = []
    @Published var statusMessage = ""
    @Published var isBusy = false

    private var timer: Timer?
    private var logSource: DispatchSourceFileSystemObject?

    // MARK: - Embedded Watchdog Script

    private let watchdogScript = """
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

    mkdir -p "$(dirname "$LOG_FILE")"

    log() {
        printf '[%s] %s\\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
    }

    log "Watchdog started (PID $$)"

    while true; do
        for target in "${TARGETS[@]}"; do
            pids=$(pgrep -f "$target" 2>/dev/null)
            if [[ -n "$pids" ]]; then
                while IFS= read -r pid; do
                    kill -9 "$pid" 2>/dev/null && log "Killed ${target} (PID ${pid})"
                done <<< "$pids"
            fi
        done
        sleep "$POLL_INTERVAL"
    done
    """

    // MARK: - LaunchAgent Plist

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
            <string>/tmp/killmau.stdout.log</string>
            <key>StandardErrorPath</key>
            <string>/tmp/killmau.stderr.log</string>
        </dict>
        </plist>
        """
    }

    // MARK: - Lifecycle

    init() {
        refreshStatus()
        loadLogEntries()
        startPolling()
        watchLogFile()
    }

    deinit {
        timer?.invalidate()
        logSource?.cancel()
    }

    // MARK: - Status

    func refreshStatus() {
        isInstalled = FileManager.default.fileExists(atPath: scriptPath.path)
        isEnabled = ShellExecutor.shell("launchctl list 2>/dev/null | grep -q com.user.killmau && echo yes || echo no").output == "yes"
        isRunning = ShellExecutor.shell("pgrep -f kill_mau.sh >/dev/null 2>&1 && echo yes || echo no").output == "yes"
        updateStatusMessage()
    }

    private func updateStatusMessage() {
        if !isInstalled {
            statusMessage = "Not installed"
        } else if isEnabled && isRunning {
            statusMessage = "Active — blocking Microsoft updates"
        } else if isInstalled && !isEnabled {
            statusMessage = "Installed but disabled"
        } else {
            statusMessage = "Installed — starting up..."
        }
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }
    }

    // MARK: - Log File

    func loadLogEntries() {
        guard FileManager.default.fileExists(atPath: logFilePath.path),
              let content = try? String(contentsOf: logFilePath, encoding: .utf8) else {
            logEntries = []
            return
        }
        logEntries = content.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .suffix(100)
            .reversed()
    }

    private func watchLogFile() {
        let path = logFilePath.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.loadLogEntries()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        logSource = source
    }

    // MARK: - Actions

    func install() {
        guard !isBusy else { return }
        isBusy = true
        statusMessage = "Installing..."

        Task {
            // 1. Kill running MAU processes
            ShellExecutor.shell("pkill -9 -f 'Microsoft AutoUpdate' 2>/dev/null; true")
            ShellExecutor.shell("pkill -9 -f 'Microsoft Update Assistant' 2>/dev/null; true")

            // 2. Disable Microsoft's user-level LaunchAgent
            let msAgentPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents/com.microsoft.update.agent.plist")
            if FileManager.default.fileExists(atPath: msAgentPath.path) {
                ShellExecutor.shell("launchctl unload -w '\(msAgentPath.path)' 2>/dev/null; true")
            }

            // 3. Disable system-level helper (requires admin)
            let sysHelper = "/Library/LaunchAgents/com.microsoft.autoupdate.helper.plist"
            if FileManager.default.fileExists(atPath: sysHelper) {
                let result = ShellExecutor.runWithAdmin("launchctl unload -w '\(sysHelper)'")
                if result.exitCode != 0 && !result.output.contains("Could not find") {
                    statusMessage = "Admin access required to fully disable updates"
                }
            }

            // 4. Write watchdog script
            do {
                try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
                try watchdogScript.write(to: scriptPath, atomically: true, encoding: .utf8)
                ShellExecutor.shell("chmod +x '\(scriptPath.path)'")
            } catch {
                statusMessage = "Failed to write watchdog: \(error.localizedDescription)"
                isBusy = false
                return
            }

            // 5. Write and load LaunchAgent plist
            do {
                try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
                try plistContent.write(to: plistPath, atomically: true, encoding: .utf8)
                ShellExecutor.shell("launchctl unload '\(plistPath.path)' 2>/dev/null; true")
                let loadResult = ShellExecutor.shell("launchctl load -w '\(plistPath.path)'")
                if loadResult.exitCode != 0 {
                    statusMessage = "Failed to load LaunchAgent: \(loadResult.output)"
                    isBusy = false
                    return
                }
            } catch {
                statusMessage = "Failed to write LaunchAgent: \(error.localizedDescription)"
                isBusy = false
                return
            }

            // 6. Create log dir so file watcher can start
            ShellExecutor.shell("mkdir -p '\(logFilePath.deletingLastPathComponent().path)'")

            refreshStatus()
            watchLogFile()
            statusMessage = "Installed successfully"
            isBusy = false
        }
    }

    func uninstall() {
        guard !isBusy else { return }
        isBusy = true
        statusMessage = "Uninstalling..."

        Task {
            // 1. Unload LaunchAgent
            if FileManager.default.fileExists(atPath: plistPath.path) {
                ShellExecutor.shell("launchctl unload '\(plistPath.path)' 2>/dev/null; true")
                try? FileManager.default.removeItem(at: plistPath)
            }

            // 2. Kill watchdog
            ShellExecutor.shell("pkill -f kill_mau.sh 2>/dev/null; true")

            // 3. Remove script
            try? FileManager.default.removeItem(at: scriptPath)

            // 4. Re-enable Microsoft's agent
            let msAgentPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents/com.microsoft.update.agent.plist")
            if FileManager.default.fileExists(atPath: msAgentPath.path) {
                ShellExecutor.shell("launchctl load -w '\(msAgentPath.path)' 2>/dev/null; true")
            }

            refreshStatus()
            statusMessage = "Uninstalled — Microsoft updates re-enabled"
            isBusy = false
        }
    }

    func enable() {
        guard !isBusy, isInstalled else { return }
        isBusy = true
        statusMessage = "Enabling..."

        let result = ShellExecutor.shell("launchctl load -w '\(plistPath.path)'")
        if result.exitCode == 0 {
            statusMessage = "Enabled"
        } else {
            statusMessage = "Failed to enable: \(result.output)"
        }
        refreshStatus()
        isBusy = false
    }

    func disable() {
        guard !isBusy, isInstalled else { return }
        isBusy = true
        statusMessage = "Disabling..."

        ShellExecutor.shell("launchctl unload -w '\(plistPath.path)' 2>/dev/null; true")
        ShellExecutor.shell("pkill -f kill_mau.sh 2>/dev/null; true")
        refreshStatus()
        statusMessage = "Disabled — updates can run"
        isBusy = false
    }
}
```

**Step 2: Verify it builds**

Run: `xcodebuild -project KillOfficeUpdateApp/KillOfficeUpdateApp.xcodeproj -scheme KillOfficeUpdateApp build`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add KillOfficeUpdateApp/KillOfficeUpdateApp/AppViewModel.swift
git commit -m "feat: add AppViewModel with install/uninstall/enable/disable logic"
```

---

### Task 4: Implement ContentView with Liquid Glass

**Files:**
- Modify: `KillOfficeUpdateApp/KillOfficeUpdateApp/ContentView.swift`

**Step 1: Replace default ContentView with Liquid Glass UI**

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        VStack(spacing: 20) {
            // MARK: - Status Header
            statusHeader

            // MARK: - Action Buttons
            actionButtons

            // MARK: - Log Viewer
            logViewer

            // MARK: - Status Bar
            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
        }
        .padding()
        .frame(width: 400, height: 520)
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: viewModel.isRunning ? "checkmark.shield.fill" : "xmark.shield.fill")
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(viewModel.isRunning ? .green : .red)
                .contentTransition(.symbolEffect(.replace))

            Text("Microsoft Update Blocker")
                .font(.headline)

            Text(viewModel.isRunning ? "Active" : "Inactive")
                .font(.subheadline)
                .foregroundStyle(viewModel.isRunning ? .green : .secondary)
        }
        .padding(.top, 8)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                actionButton(
                    title: "Install",
                    icon: "arrow.down.circle",
                    action: viewModel.install,
                    disabled: viewModel.isInstalled || viewModel.isBusy
                )
                actionButton(
                    title: "Uninstall",
                    icon: "trash.circle",
                    action: viewModel.uninstall,
                    disabled: !viewModel.isInstalled || viewModel.isBusy
                )
            }
            GridRow {
                actionButton(
                    title: "Enable",
                    icon: "play.circle",
                    action: viewModel.enable,
                    disabled: !viewModel.isInstalled || viewModel.isEnabled || viewModel.isBusy
                )
                actionButton(
                    title: "Disable",
                    icon: "pause.circle",
                    action: viewModel.disable,
                    disabled: !viewModel.isInstalled || !viewModel.isEnabled || viewModel.isBusy
                )
            }
        }
        .padding()
        .glassEffect(.regular.interactive, in: .rect(cornerRadius: 16))
    }

    private func actionButton(title: String, icon: String, action: @escaping () -> Void, disabled: Bool) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .disabled(disabled)
    }

    // MARK: - Log Viewer

    private var logViewer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Recent Activity", systemImage: "doc.text")
                    .font(.subheadline.bold())
                Spacer()
                Button("Refresh") {
                    viewModel.loadLogEntries()
                }
                .controlSize(.small)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if viewModel.logEntries.isEmpty {
                        Text("No log entries yet")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(viewModel.logEntries, id: \.self) { entry in
                            Text(entry)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(8)
            }
            .frame(height: 160)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

#Preview {
    ContentView()
}
```

**Step 2: Verify it builds**

Run: `xcodebuild -project KillOfficeUpdateApp/KillOfficeUpdateApp.xcodeproj -scheme KillOfficeUpdateApp build`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add KillOfficeUpdateApp/KillOfficeUpdateApp/ContentView.swift
git commit -m "feat: add ContentView with Liquid Glass UI"
```

---

### Task 5: Configure App Entry Point & Window

**Files:**
- Modify: `KillOfficeUpdateApp/KillOfficeUpdateApp/KillOfficeUpdateAppApp.swift` (Xcode's default name)

**Step 1: Update the @main app struct**

```swift
import SwiftUI

@main
struct KillOfficeUpdateApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 400, height: 520)
    }
}
```

**Step 2: Verify it builds**

Run: `xcodebuild -project KillOfficeUpdateApp/KillOfficeUpdateApp.xcodeproj -scheme KillOfficeUpdateApp build`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add KillOfficeUpdateApp/KillOfficeUpdateApp/KillOfficeUpdateAppApp.swift
git commit -m "feat: configure window size and resizability"
```

---

### Task 6: Build, Run, and Verify

**Step 1: Full clean build**

Run: `xcodebuild -project KillOfficeUpdateApp/KillOfficeUpdateApp.xcodeproj -scheme KillOfficeUpdateApp clean build`
Expected: BUILD SUCCEEDED

**Step 2: Launch and manually verify**

Open the app in Xcode and run (Cmd+R). Verify:
- Window renders at ~400x520pt with Liquid Glass translucency
- Status shows "Not installed" with red shield icon
- Only Install button is enabled
- Other three buttons are disabled
- Log viewer shows "No log entries yet"

**Step 3: Test Install flow**

- Click Install
- Admin password dialog appears (for system-level MS agent)
- After completion: shield turns green, status shows "Active"
- Enable/Disable buttons update correctly
- Log viewer populates as watchdog starts killing processes

**Step 4: Test Disable/Enable**

- Click Disable -> shield turns red, status updates
- Click Enable -> shield turns green, watchdog restarts

**Step 5: Test Uninstall**

- Click Uninstall -> status returns to "Not installed"
- Only Install button is enabled again

**Step 6: Final commit**

```bash
git add -A
git commit -m "feat: complete KillOfficeUpdate macOS GUI app"
```
