#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
INSTALL_DIR="${HOME}/.local/bin"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
PLIST_NAME="com.user.killmau.plist"
SCRIPT_NAME="kill_mau.sh"

echo "=== killOfficeUpdate Installer ==="
echo ""

# Step 1: Kill any running MAU
echo "[1/4] Killing running Microsoft AutoUpdate..."
pkill -9 -f "Microsoft AutoUpdate" 2>/dev/null && echo "  Killed." || echo "  Not running."
pkill -9 -f "Microsoft Update Assistant" 2>/dev/null && echo "  Killed Update Assistant." || echo "  Update Assistant not running."

# Step 2: Disable Microsoft's own LaunchAgents
echo "[2/4] Disabling Microsoft update LaunchAgents..."
if [[ -f "${HOME}/Library/LaunchAgents/com.microsoft.update.agent.plist" ]]; then
    launchctl unload -w "${HOME}/Library/LaunchAgents/com.microsoft.update.agent.plist" 2>/dev/null \
        && echo "  Disabled com.microsoft.update.agent" \
        || echo "  Already disabled."
fi
if [[ -f "/Library/LaunchAgents/com.microsoft.autoupdate.helper.plist" ]]; then
    echo "  Disabling system-level helper (requires sudo)..."
    sudo launchctl unload -w "/Library/LaunchAgents/com.microsoft.autoupdate.helper.plist" 2>/dev/null \
        && echo "  Disabled com.microsoft.autoupdate.helper" \
        || echo "  Already disabled."
fi

# Step 3: Install watchdog script
echo "[3/4] Installing watchdog script..."
mkdir -p "$INSTALL_DIR"
cp "${SCRIPT_DIR}/${SCRIPT_NAME}" "${INSTALL_DIR}/${SCRIPT_NAME}"
chmod +x "${INSTALL_DIR}/${SCRIPT_NAME}"
echo "  Installed to ${INSTALL_DIR}/${SCRIPT_NAME}"

# Step 4: Install and load LaunchAgent
echo "[4/4] Installing LaunchAgent..."
mkdir -p "$LAUNCH_AGENTS_DIR"

cat > "${LAUNCH_AGENTS_DIR}/${PLIST_NAME}" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.killmau</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>${INSTALL_DIR}/${SCRIPT_NAME}</string>
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
EOF

launchctl unload "${LAUNCH_AGENTS_DIR}/${PLIST_NAME}" 2>/dev/null || true
launchctl load -w "${LAUNCH_AGENTS_DIR}/${PLIST_NAME}"
echo "  LaunchAgent loaded."

echo ""
echo "Done! Microsoft AutoUpdate will be killed on sight."
echo "Watchdog logs: ~/.local/log/killmau.log"
