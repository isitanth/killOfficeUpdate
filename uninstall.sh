#!/bin/zsh
set -euo pipefail

INSTALL_DIR="${HOME}/.local/bin"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
PLIST_NAME="com.user.killmau.plist"
SCRIPT_NAME="kill_mau.sh"
LOG_FILE="${HOME}/.local/log/killmau.log"

echo "=== killOfficeUpdate Uninstaller ==="
echo ""

# Step 1: Unload LaunchAgent
echo "[1/4] Unloading LaunchAgent..."
if [[ -f "${LAUNCH_AGENTS_DIR}/${PLIST_NAME}" ]]; then
    launchctl unload "${LAUNCH_AGENTS_DIR}/${PLIST_NAME}" 2>/dev/null \
        && echo "  Unloaded." \
        || echo "  Was not loaded."
    rm "${LAUNCH_AGENTS_DIR}/${PLIST_NAME}"
    echo "  Removed plist."
else
    echo "  Not installed."
fi

# Step 2: Kill watchdog if running
echo "[2/4] Stopping watchdog..."
pkill -f "kill_mau.sh" 2>/dev/null && echo "  Stopped." || echo "  Not running."

# Step 3: Remove script
echo "[3/4] Removing watchdog script..."
if [[ -f "${INSTALL_DIR}/${SCRIPT_NAME}" ]]; then
    rm "${INSTALL_DIR}/${SCRIPT_NAME}"
    echo "  Removed."
else
    echo "  Not found."
fi

# Step 4: Re-enable Microsoft LaunchAgents
echo "[4/4] Re-enabling Microsoft update agents..."
if [[ -f "${HOME}/Library/LaunchAgents/com.microsoft.update.agent.plist" ]]; then
    launchctl load -w "${HOME}/Library/LaunchAgents/com.microsoft.update.agent.plist" 2>/dev/null \
        && echo "  Re-enabled com.microsoft.update.agent" \
        || echo "  Failed (may need manual fix)."
fi

echo ""
echo "Uninstalled. Microsoft AutoUpdate can run again."
if [[ -f "$LOG_FILE" ]]; then
    echo "Log file kept at: $LOG_FILE (delete manually if unwanted)"
fi
