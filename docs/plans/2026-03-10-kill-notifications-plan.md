# Kill Notifications Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add toggleable macOS native notifications when the watchdog kills Microsoft AutoUpdate processes.

**Architecture:** The watchdog shell script checks for a flag file before sending `osascript` notifications. The SwiftUI app manages the flag file via a Toggle. All new paths are injectable for testability, following the existing pattern.

**Tech Stack:** Swift 6, SwiftUI, macOS 26, launchd, osascript

---

### Task 1: Add notify flag path to ViewModel

**Files:**
- Modify: `KillOfficeUpdateApp/KillOfficeUpdateApp/AppViewModel.swift:9-16` (add constant)
- Modify: `KillOfficeUpdateApp/KillOfficeUpdateApp/AppViewModel.swift:98-124` (add init param)

**Step 1: Add the `notifyFlagPath` property and `isNotifyEnabled` state**

In `AppViewModel.swift`, add to the constants block (after `tmpStderrPath`):

```swift
let notifyFlagPath: String
```

Add to the published state block (after `isBusy`):

```swift
@Published var isNotifyEnabled: Bool = false
```

**Step 2: Add init parameter with default**

Add parameter to init (after `tmpStderrPath`):

```swift
notifyFlagPath: String = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".local/etc/killmau-notify").path,
```

Add assignment in init body (after `self.tmpStderrPath = tmpStderrPath`):

```swift
self.notifyFlagPath = notifyFlagPath
```

**Step 3: Verify existing tests still pass**

Run: `xcodebuild test -project KillOfficeUpdateApp/KillOfficeUpdateApp.xcodeproj -scheme KillOfficeUpdateAppTests -destination 'platform=macOS' -quiet 2>&1`

Expected: All 13 tests pass (new parameter has a default, so no breakage).

**Step 4: Commit**

```bash
git add KillOfficeUpdateApp/KillOfficeUpdateApp/AppViewModel.swift
git commit -m "feat: add notifyFlagPath constant and isNotifyEnabled state"
```

---

### Task 2: Implement toggleNotifications() with TDD

**Files:**
- Modify: `KillOfficeUpdateApp/KillOfficeUpdateApp/AppViewModel.swift` (add method)
- Modify: `KillOfficeUpdateApp/KillOfficeUpdateAppTests/AppViewModelCleanUpTests.swift` (add tests)

**Step 1: Write failing tests**

Add these tests to `AppViewModelCleanUpTests.swift` (or create a new section at the bottom). The `makeViewModel()` helper already creates ViewModels with `tmpDir` paths — add `notifyFlagPath` to it:

Update `makeViewModel()`:

```swift
private var notifyFlagPath: String!

// In setUp(), after stderrPath:
notifyFlagPath = tmpDir.appendingPathComponent("killmau-notify").path
```

Update `makeViewModel()` to pass the new param:

```swift
private func makeViewModel() -> AppViewModel {
    AppViewModel(
        installDir: tmpDir,
        logFilePath: logFilePath,
        tmpStdoutPath: stdoutPath,
        tmpStderrPath: stderrPath,
        notifyFlagPath: notifyFlagPath,
        performSetup: false
    )
}
```

Add new test methods:

```swift
// MARK: - Toggle notifications

func test_toggleNotifications_createsFlag() {
    let vm = makeViewModel()
    vm.isInstalled = true
    vm.isNotifyEnabled = false

    vm.toggleNotifications()

    XCTAssertTrue(FileManager.default.fileExists(atPath: notifyFlagPath),
                  "Flag file should be created when toggling on")
    XCTAssertTrue(vm.isNotifyEnabled)
}

func test_toggleNotifications_deletesFlag() {
    FileManager.default.createFile(atPath: notifyFlagPath, contents: nil)
    let vm = makeViewModel()
    vm.isInstalled = true
    vm.isNotifyEnabled = true

    vm.toggleNotifications()

    XCTAssertFalse(FileManager.default.fileExists(atPath: notifyFlagPath),
                   "Flag file should be deleted when toggling off")
    XCTAssertFalse(vm.isNotifyEnabled)
}

func test_toggleNotifications_blockedWhenNotInstalled() {
    let vm = makeViewModel()
    vm.isInstalled = false
    vm.isNotifyEnabled = false

    vm.toggleNotifications()

    XCTAssertFalse(FileManager.default.fileExists(atPath: notifyFlagPath),
                   "Should not create flag when not installed")
    XCTAssertFalse(vm.isNotifyEnabled)
}

func test_toggleNotifications_createsParentDirectory() {
    // Use a nested path that doesn't exist yet
    let nestedPath = tmpDir.appendingPathComponent("sub/dir/killmau-notify").path
    let vm = AppViewModel(
        installDir: tmpDir,
        logFilePath: logFilePath,
        tmpStdoutPath: stdoutPath,
        tmpStderrPath: stderrPath,
        notifyFlagPath: nestedPath,
        performSetup: false
    )
    vm.isInstalled = true
    vm.isNotifyEnabled = false

    vm.toggleNotifications()

    XCTAssertTrue(FileManager.default.fileExists(atPath: nestedPath),
                  "Should create parent directories")
    XCTAssertTrue(vm.isNotifyEnabled)
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project KillOfficeUpdateApp/KillOfficeUpdateApp.xcodeproj -scheme KillOfficeUpdateAppTests -destination 'platform=macOS' -quiet 2>&1`

Expected: FAIL — `toggleNotifications()` does not exist yet.

**Step 3: Implement toggleNotifications()**

Add to `AppViewModel.swift` after the `cleanUp()` method:

```swift
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
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project KillOfficeUpdateApp/KillOfficeUpdateApp.xcodeproj -scheme KillOfficeUpdateAppTests -destination 'platform=macOS' -quiet 2>&1`

Expected: All tests pass (13 old + 4 new = 17).

**Step 5: Commit**

```bash
git add KillOfficeUpdateApp/KillOfficeUpdateApp/AppViewModel.swift KillOfficeUpdateApp/KillOfficeUpdateAppTests/AppViewModelCleanUpTests.swift
git commit -m "feat: implement toggleNotifications with TDD"
```

---

### Task 3: Read flag file state in refreshStatus()

**Files:**
- Modify: `KillOfficeUpdateApp/KillOfficeUpdateApp/AppViewModel.swift:133-145` (refreshStatus)
- Modify: `KillOfficeUpdateApp/KillOfficeUpdateAppTests/AppViewModelCleanUpTests.swift` (add tests)

**Step 1: Write failing tests**

```swift
// MARK: - Notify flag reading

func test_refreshStatus_readsNotifyFlagEnabled() {
    FileManager.default.createFile(atPath: notifyFlagPath, contents: nil)
    let vm = makeViewModel()
    vm.isNotifyEnabled = false

    vm.refreshStatus()

    XCTAssertTrue(vm.isNotifyEnabled, "Should read flag file as enabled")
}

func test_refreshStatus_readsNotifyFlagDisabled() {
    // No flag file exists
    let vm = makeViewModel()
    vm.isNotifyEnabled = true

    vm.refreshStatus()

    XCTAssertFalse(vm.isNotifyEnabled, "Should read absent flag as disabled")
}
```

**Step 2: Run tests to verify they fail**

Expected: FAIL — `refreshStatus()` doesn't read the flag file yet.

**Step 3: Add flag file check to refreshStatus()**

In `refreshStatus()`, add after the existing `isRunning` check (before `updateStatusMessage()`):

```swift
isNotifyEnabled = FileManager.default.fileExists(atPath: notifyFlagPath)
```

**Step 4: Run tests to verify they pass**

Expected: All 19 tests pass.

**Step 5: Commit**

```bash
git add KillOfficeUpdateApp/KillOfficeUpdateApp/AppViewModel.swift KillOfficeUpdateApp/KillOfficeUpdateAppTests/AppViewModelCleanUpTests.swift
git commit -m "feat: read notify flag state in refreshStatus"
```

---

### Task 4: Update watchdog script with notification support

**Files:**
- Modify: `KillOfficeUpdateApp/KillOfficeUpdateApp/AppViewModel.swift:35-67` (watchdogScript)

**Step 1: Update the watchdogScript string**

Replace the existing `watchdogScript` value with:

```swift
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
```

Key changes:
- Added `NOTIFY_FLAG` variable
- Added `notify()` function that checks flag file before `osascript`
- Changed `kill -9 ... && log` to `if kill -9 ...; then log; notify; fi` for cleaner flow

**Step 2: Run existing tests to verify nothing broke**

Run: `xcodebuild test -project KillOfficeUpdateApp/KillOfficeUpdateApp.xcodeproj -scheme KillOfficeUpdateAppTests -destination 'platform=macOS' -quiet 2>&1`

Expected: All 19 tests pass (script string is not tested by unit tests, but compilation must succeed).

**Step 3: Commit**

```bash
git add KillOfficeUpdateApp/KillOfficeUpdateApp/AppViewModel.swift
git commit -m "feat: add notification support to watchdog script"
```

**Important:** Users who already have the app installed must click **Uninstall** then **Install** again for the new script to take effect (since the script is written to disk during install).

---

### Task 5: Add Toggle to ContentView

**Files:**
- Modify: `KillOfficeUpdateApp/KillOfficeUpdateApp/ContentView.swift`

**Step 1: Add the notifications toggle**

Add a new computed property after `cleanUpButton`:

```swift
// MARK: - Notifications Toggle

private var notificationsToggle: some View {
    Toggle(isOn: Binding(
        get: { viewModel.isNotifyEnabled },
        set: { _ in viewModel.toggleNotifications() }
    )) {
        Label("Kill Notifications", systemImage: "bell.badge")
            .font(.caption)
    }
    .controlSize(.small)
    .toggleStyle(.switch)
    .disabled(!viewModel.isInstalled || viewModel.isBusy)
}
```

**Step 2: Add it to the body VStack**

In the `body`, add `notificationsToggle` between `cleanUpButton` and `statusBar`:

```swift
VStack(spacing: 20) {
    statusHeader
    actionButtons
    logViewer
    cleanUpButton
    notificationsToggle
    statusBar
}
```

**Step 3: Bump window height**

Change the frame height from 550 to 580 to accommodate the new toggle:

```swift
.frame(width: 400, height: 580)
```

Also update `KillOfficeUpdateApp.swift` to match: `.defaultSize(width: 400, height: 580)`.

**Step 4: Build and verify**

Run: `xcodebuild test -project KillOfficeUpdateApp/KillOfficeUpdateApp.xcodeproj -scheme KillOfficeUpdateAppTests -destination 'platform=macOS' -quiet 2>&1`

Expected: All 19 tests pass, build succeeds.

**Step 5: Commit**

```bash
git add KillOfficeUpdateApp/KillOfficeUpdateApp/ContentView.swift KillOfficeUpdateApp/KillOfficeUpdateApp/KillOfficeUpdateApp.swift
git commit -m "feat: add kill notifications toggle to UI"
```

---

### Task 6: Final verification

**Step 1: Run full test suite**

Run: `xcodebuild test -project KillOfficeUpdateApp/KillOfficeUpdateApp.xcodeproj -scheme KillOfficeUpdateAppTests -destination 'platform=macOS' -quiet 2>&1`

Expected: All 19 tests pass.

**Step 2: Build release**

Run: `xcodebuild -project KillOfficeUpdateApp/KillOfficeUpdateApp.xcodeproj -scheme KillOfficeUpdateApp -configuration Release -derivedDataPath build -quiet 2>&1`

Expected: Build succeeded.

**Step 3: Clean up build artifacts**

```bash
rm -rf build/
```

**Step 4: Push**

```bash
git push origin main
```
