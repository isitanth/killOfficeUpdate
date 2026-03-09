# KillOfficeUpdate GUI App Design

## Overview

A native SwiftUI macOS 26 app with Liquid Glass design that provides a graphical interface for managing the Microsoft Office update blocker. Regular window app (not menu bar). All logic reimplemented in Swift — shell scripts remain as a CLI alternative.

## Architecture

**Pattern:** MVVM — one view, one view model.

**Files:**

```
KillOfficeUpdate/
├── KillOfficeUpdateApp.swift      # @main entry point
├── ContentView.swift              # Main window UI (Liquid Glass)
├── AppViewModel.swift             # State + all system logic
└── ShellExecutor.swift            # Thin wrapper for Process + osascript sudo
```

**ViewModel state:**

- `isInstalled: Bool` — watchdog script exists at `~/.local/bin/kill_mau.sh`
- `isEnabled: Bool` — LaunchAgent loaded (`launchctl list | grep killmau`)
- `isRunning: Bool` — watchdog process alive (`pgrep -f kill_mau`)
- `logEntries: [String]` — recent lines from `~/.local/log/killmau.log`
- `statusMessage: String` — user feedback

## Actions

| Action    | What it does                                                                                                                        |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Install   | Kills MAU processes, disables MS agents (sudo via osascript), writes watchdog to `~/.local/bin/`, creates + loads LaunchAgent plist |
| Uninstall | Unloads LaunchAgent, kills watchdog, removes files, re-enables MS agents                                                           |
| Enable    | `launchctl load -w` the existing plist                                                                                              |
| Disable   | `launchctl unload -w` the plist, kills watchdog process                                                                             |

## UI Layout

Compact fixed-size window (~400x520pt), single pane, no navigation.

```
┌──────────────────────────────────────┐
│  ░░░░░░ Liquid Glass Window ░░░░░░  │
│                                      │
│     ◉  Microsoft Update Blocker     │
│        ● Active  /  ○ Inactive      │
│     (large status icon + label)      │
│                                      │
│  ┌────────────────────────────────┐  │
│  │  glass card                    │  │
│  │  [  Install  ]  [ Uninstall ] │  │
│  │  [  Enable   ]  [  Disable  ] │  │
│  └────────────────────────────────┘  │
│                                      │
│  ┌────────────────────────────────┐  │
│  │  glass card - Log Viewer      │  │
│  │  12:03:01 Killed MAU (pid 42) │  │
│  │  12:03:04 Killed MAU (pid 51) │  │
│  │  12:03:07 No processes found  │  │
│  │  ...scrollable...             │  │
│  └────────────────────────────────┘  │
│                                      │
│  Status: Installed and running       │
└──────────────────────────────────────┘
```

**Liquid Glass specifics:**

- Window uses `.windowStyle(.automatic)` for default glass treatment on macOS 26
- Action buttons in 2x2 grid with `.glassEffect()` modifier
- Log viewer in `List` with `.glassEffect()` container
- Status icon: SF Symbol `checkmark.shield` (active, green) / `xmark.shield` (inactive, red)

**Button state logic:**

| State                  | Install    | Uninstall  | Enable     | Disable    |
| ---------------------- | ---------- | ---------- | ---------- | ---------- |
| Not installed          | **active** | disabled   | disabled   | disabled   |
| Installed + enabled    | disabled   | **active** | disabled   | **active** |
| Installed + disabled   | disabled   | **active** | **active** | disabled   |

## System Interaction

**ShellExecutor** wraps `Process` (Foundation):

- `run(_ command: String, args: [String]) -> (output: String, exitCode: Int32)` — regular commands
- `runWithAdmin(_ command: String) -> (output: String, exitCode: Int32)` — privileged commands via `osascript -e 'do shell script "..." with administrator privileges'`

**Status polling:**

- On launch: check `isInstalled` / `isEnabled` / `isRunning`
- `Timer` refreshes status every 5 seconds (lightweight `pgrep` + `launchctl list`)
- Log file watched via `DispatchSource.makeFileSystemObjectSource` for real-time updates

**Embedded watchdog:**

- `kill_mau.sh` content stored as a Swift string constant
- Written to `~/.local/bin/kill_mau.sh` on install
- App is fully self-contained

## Error Handling

- Each action returns success/failure; `statusMessage` shows errors
- Admin password cancellation shows "Admin access required" — no retry
- Missing files (partial install) shows "Repair" suggestion

## Sudo Handling

Uses `osascript` to prompt the standard macOS admin password dialog:

```swift
osascript -e 'do shell script "..." with administrator privileges'
```

Used only during install (to unload system-level MS agent) and uninstall (to re-enable it).
