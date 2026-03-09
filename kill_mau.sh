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
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
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
