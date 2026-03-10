# Changelog

## v1.1.1

### Changes
- Added application screenshot to README
- Removed legacy shell scripts (bundled in app binary)
- Added README with install, build, and uninstall instructions

## v1.1.0

### New Features
- **Kill Notifications** — opt-in macOS native notifications when the watchdog kills a Microsoft AutoUpdate process. Toggle on/off from the app UI.
- **Auto-update watchdog script** — when the app ships a newer version of the watchdog script, it is automatically updated on disk without requiring uninstall/reinstall.

### Bug Fixes
- Fixed `isRunning` status falsely reporting active when no watchdog was running (pgrep self-match)
- Fixed `isInstalled` only checking the script file — now requires both script and plist to exist, preventing stuck UI states
- Fixed `launchctl unload` in uninstall missing the `-w` flag — the daemon could survive a reboot if plist deletion failed
- Fixed uninstall leaving behind log file, temp files, and notification flag on disk
- Fixed install failing with "already loaded" error on reinstall — now safely unloads before loading
- Fixed unreliable `launchctl list | grep` status check — now queries the exact service label

## v1.0.0

### Initial Release
- macOS app to block Microsoft AutoUpdate
- Install/Uninstall watchdog daemon via LaunchAgent
- Enable/Disable toggle for the daemon
- Live log viewer with recent activity
- Clean Up button to clear logs and temp files
- Unsigned distribution via DMG + GitHub Releases
