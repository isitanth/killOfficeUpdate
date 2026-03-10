# Kill Notifications Design

**Goal:** Prove the daemon works when the app is closed by sending macOS native notifications each time the watchdog kills a Microsoft AutoUpdate process, with a toggleable opt-in.

## Architecture

Two changes to the watchdog shell script:
1. **Kill notifications** — after each successful `kill -9`, send a macOS notification via `osascript`, gated on a flag file (`~/.local/etc/killmau-notify`)
2. **Restart detection** — the existing "Watchdog started (PID $$)" log line already serves as restart evidence when it appears more than once. No script change needed.

One change to the SwiftUI app:
1. **Notification toggle** — a `Toggle` in the UI that creates/deletes the flag file, with `isNotifyEnabled` published state in ViewModel

## Notification Format

```bash
osascript -e 'display notification "Killed Microsoft AutoUpdate (PID 1234)" with title "KillOfficeUpdate"'
```

## Flag File

- Path: `~/.local/etc/killmau-notify`
- Exists = notifications enabled, absent = disabled
- Content irrelevant (presence check only)
- Default: off (user opts in)

## Script Changes

In the kill loop, after a successful `kill -9`:

```bash
if [[ -f "${HOME}/.local/etc/killmau-notify" ]]; then
    osascript -e "display notification \"Killed ${target} (PID ${pid})\" with title \"KillOfficeUpdate\"" 2>/dev/null
fi
```

## UI Changes

A `Toggle("Kill Notifications", isOn: ...)` row inside the action buttons glass card, below Enable/Disable. Calls a new `toggleNotifications()` method on the ViewModel that creates or deletes the flag file.

## ViewModel Changes

- New property: `@Published var isNotifyEnabled: Bool`
- New constant: `notifyFlagDir` and `notifyFlagPath` (injectable for testing)
- `refreshStatus()` also reads the flag file state
- New method: `toggleNotifications()` — creates parent dir + flag file, or deletes it

## Testing

- Unit tests for `toggleNotifications()` using temp directories (same pattern as cleanUp tests)
- Manual verification: install, enable notifications, wait for a kill, confirm banner appears
