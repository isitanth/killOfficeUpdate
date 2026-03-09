# Cleanup Feature Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a single "Clean Up" button below the log viewer that truncates the log file, deletes temp files, and clears the log viewer display.

**Architecture:** Add a `cleanUp()` method to the existing `AppViewModel` MVVM pattern, then add a compact button to `ContentView` below the log viewer card. No new files needed — two existing files modified.

**Tech Stack:** SwiftUI, Foundation (FileManager), existing ShellExecutor

---

### Task 1: Add `cleanUp()` method to AppViewModel

**Files:**
- Modify: `KillOfficeUpdateApp/KillOfficeUpdateApp/AppViewModel.swift:303` (insert before closing brace)

**Step 1: Add the cleanUp method**

Insert a new MARK section after the `disable()` method (after line 303), before the final `}`:

```swift
    // MARK: - Clean Up

    func cleanUp() {
        guard !isBusy else { return }
        isBusy = true
        statusMessage = "Cleaning up..."

        // 1. Truncate log file (not delete — watchdog may still be writing)
        if FileManager.default.fileExists(atPath: logFilePath.path) {
            try? "".write(to: logFilePath, atomically: true, encoding: .utf8)
        }

        // 2. Delete temp files (silently skip if missing)
        let tmpStdout = "/tmp/killmau.stdout.log"
        let tmpStderr = "/tmp/killmau.stderr.log"
        if FileManager.default.fileExists(atPath: tmpStdout) {
            try? FileManager.default.removeItem(atPath: tmpStdout)
        }
        if FileManager.default.fileExists(atPath: tmpStderr) {
            try? FileManager.default.removeItem(atPath: tmpStderr)
        }

        // 3. Clear log viewer
        logEntries = []

        // 4. Finalize
        statusMessage = "Cleaned up successfully"
        isBusy = false
    }
```

**Step 2: Verify it builds**

Run: `xcodebuild -project KillOfficeUpdateApp/KillOfficeUpdateApp.xcodeproj -scheme KillOfficeUpdateApp build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add KillOfficeUpdateApp/KillOfficeUpdateApp/AppViewModel.swift
git commit -m "feat: add cleanUp() method to AppViewModel"
```

---

### Task 2: Add "Clean Up" button to ContentView

**Files:**
- Modify: `KillOfficeUpdateApp/KillOfficeUpdateApp/ContentView.swift:10-11` (insert between `logViewer` and `statusBar`)

**Step 1: Add the cleanUpButton view**

In `ContentView`, insert `cleanUpButton` between `logViewer` and `statusBar` in the VStack body (line 11):

Change the body VStack from:
```swift
        VStack(spacing: 20) {
            statusHeader
            actionButtons
            logViewer
            statusBar
        }
```

To:
```swift
        VStack(spacing: 20) {
            statusHeader
            actionButtons
            logViewer
            cleanUpButton
            statusBar
        }
```

**Step 2: Add the cleanUpButton computed property**

Insert a new MARK section after the `logViewer` property (after line 108), before the `statusBar` section:

```swift
    // MARK: - Clean Up Button

    private var cleanUpButton: some View {
        HStack {
            Spacer()
            Button {
                viewModel.cleanUp()
            } label: {
                Label("Clean Up", systemImage: "trash.circle")
                    .font(.caption)
            }
            .controlSize(.small)
            .disabled(!viewModel.isInstalled || viewModel.isBusy)
        }
    }
```

**Step 3: Adjust window height if needed**

In `ContentView`, change the frame height from 520 to 550 (line 14):

```swift
        .frame(width: 400, height: 550)
```

Also update `KillOfficeUpdateApp.swift` line 10 to match:

```swift
        .defaultSize(width: 400, height: 550)
```

**Step 4: Verify it builds**

Run: `xcodebuild -project KillOfficeUpdateApp/KillOfficeUpdateApp.xcodeproj -scheme KillOfficeUpdateApp build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 5: Commit**

```bash
git add KillOfficeUpdateApp/KillOfficeUpdateApp/ContentView.swift
git add KillOfficeUpdateApp/KillOfficeUpdateApp/KillOfficeUpdateApp.swift
git commit -m "feat: add Clean Up button below log viewer"
```

---

### Task 3: Manual smoke test

**Step 1: Run the app**

Open in Xcode and run, or:
```bash
xcodebuild -project KillOfficeUpdateApp/KillOfficeUpdateApp.xcodeproj -scheme KillOfficeUpdateApp build
open KillOfficeUpdateApp/build/Release/KillOfficeUpdateApp.app
```

**Step 2: Verify button states**

- [ ] "Clean Up" button is **disabled** when not installed
- [ ] "Clean Up" button is **enabled** when installed (regardless of enable/disable state)
- [ ] "Clean Up" button is **disabled** when any other action is in progress (`isBusy`)

**Step 3: Verify cleanup action**

- [ ] Click "Clean Up" → log viewer clears immediately
- [ ] Status message shows "Cleaned up successfully"
- [ ] `~/.local/log/killmau.log` exists but is empty
- [ ] `/tmp/killmau.stdout.log` is deleted (if it existed)
- [ ] `/tmp/killmau.stderr.log` is deleted (if it existed)
- [ ] New watchdog entries appear in the log viewer after a few seconds (if watchdog is running)

**Step 4: Verify layout**

- [ ] Button appears below the log viewer card, right-aligned
- [ ] Button looks secondary/compact (smaller than main action grid)
- [ ] No clipping or overflow — everything fits in the window
