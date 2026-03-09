# Cleanup Feature Design

## Summary

Add a single "Clean Up" button to the UI that truncates the log file, deletes temp files, and clears the log viewer. Positioned as a secondary action below the log viewer card.

## UI Layout

The button sits below the log viewer card, styled as a compact secondary action.

```
┌─────────────────────────────┐
│  Status Header              │
│  [2x2 Action Button Grid]  │
│  [Log Viewer Card]          │
│  [Clean Up]  ← new button   │
│  Status Bar                 │
└─────────────────────────────┘
```

- **SF Symbol:** `trash.circle` or similar cleanup metaphor
- **Style:** Compact, secondary (`.borderless` or small Liquid Glass capsule)
- **Disabled when:** `isBusy` or `!isInstalled`

## Cleanup Logic (`cleanUp()` in AppViewModel)

1. Set `isBusy = true`
2. Truncate `~/.local/log/killmau.log` to empty (not delete — the watchdog keeps writing to it)
3. Delete `/tmp/killmau.stdout.log` if it exists (skip silently if missing)
4. Delete `/tmp/killmau.stderr.log` if it exists (skip silently if missing)
5. Clear `logEntries` array to empty the log viewer
6. Set `statusMessage` to "Cleaned up successfully"
7. Set `isBusy = false`

## Key Decisions

- **Truncate, don't delete** the main log — the running watchdog has a file handle open; deleting could cause it to write to a ghost file.
- **No admin required** — all target files are in `~/.local/` and `/tmp/`, both user-writable.
- **No confirmation dialog** — the data is low-value logs; a status message provides sufficient feedback.
- **No error for missing temp files** — they may already be gone.

## Button State

- Disabled when `isBusy` (like all other actions)
- Disabled when `!isInstalled` — nothing to clean up
- Enabled when installed but disabled/not running — user may still want to clear old logs

## Integration

- The 5-second polling timer calls `loadLogEntries()` on next tick, finds an empty log, keeps view clear — no special handling needed.
- The watchdog (if running) writes fresh entries to the truncated file; new log lines appear naturally.
- Window may need a small height bump (~+30pt) if the button doesn't fit; try without resizing first.
