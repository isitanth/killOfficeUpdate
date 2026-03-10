# KillOfficeUpdate

A macOS app that kills Microsoft AutoUpdate on sight.

A background watchdog polls every 3 seconds, catches `Microsoft AutoUpdate` and `Microsoft Update Assistant`, and `kill -9`s them before they can nag you. Works even when the app is closed.

## Install

1. Download the DMG from [GitHub Releases](https://github.com/isitanth/killOfficeUpdate/releases).
2. Drag the app to Applications.
3. Right-click the app, then click **Open** (required once to bypass Gatekeeper, the app is unsigned).
4. Click **Install** inside the app.

That's it. The watchdog runs in the background via launchd and survives reboots.

## What it does

On install, the app:

- Writes a watchdog shell script to `~/.local/bin/kill_mau.sh`
- Registers a LaunchAgent (`~/Library/LaunchAgents/com.user.killmau.plist`) that keeps the script alive
- Disables Microsoft's own update agent if present
- Kills any running Microsoft AutoUpdate processes immediately

Kill notifications (native macOS) can be toggled on in the app.

## Uninstall

Click **Uninstall** in the app. It removes the script, plist, logs, temp files, and re-enables the Microsoft update agent. Clean.

## Build from source

Requires Xcode and macOS 15+.

```sh
git clone https://github.com/isitanth/killOfficeUpdate.git
cd killOfficeUpdate/KillOfficeUpdateApp
xcodebuild -project KillOfficeUpdateApp.xcodeproj -scheme KillOfficeUpdateApp -configuration Release
```

To run tests:

```sh
xcodebuild test -project KillOfficeUpdateApp.xcodeproj -scheme KillOfficeUpdateAppTests -destination 'platform=macOS'
```

To cut a release (tags, builds DMG, publishes to GitHub):

```sh
./scripts/release.sh 1.1.0
```

## License

MIT
