#!/bin/bash

# <xbar.title>Claude Code Usage</xbar.title>
# <xbar.version>v2.0</xbar.version>
# <xbar.author>man</xbar.author>
# <xbar.desc>Displays Claude Code session usage in menu bar</xbar.desc>
# <xbar.dependencies>bash,tmux</xbar.dependencies>

# Load nvm if available
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Find claude
CLAUDE_BIN=$(which claude 2>/dev/null)
if [ -z "$CLAUDE_BIN" ]; then
    echo "?%"
    exit 1
fi

fetch_usage() {
    LOG_FILE="/tmp/claude_usage_$$.txt"
    SESSION="swiftbar-claude-$$"

    tmux kill-session -t "$SESSION" 2>/dev/null
    tmux new-session -d -s "$SESSION" "script -q $LOG_FILE $CLAUDE_BIN"

    sleep 8

    tmux send-keys -t "$SESSION" "/usage"
    sleep 0.3
    tmux send-keys -t "$SESSION" C-m

    sleep 5

    tmux send-keys -t "$SESSION" Escape
    sleep 0.3
    tmux send-keys -t "$SESSION" "/exit"
    sleep 0.3
    tmux send-keys -t "$SESSION" C-m

    sleep 2
    tmux kill-session -t "$SESSION" 2>/dev/null

    USAGE=$(cat "$LOG_FILE" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -A1 "Current session" | grep "% used" | grep -oE '[0-9]+%' | head -1)
    rm -f "$LOG_FILE"

    echo "${USAGE:-?%}"
}

USAGE=$(fetch_usage)
echo "$USAGE used"

echo "---"
echo "Session: $USAGE used"
echo "---"
echo "Refresh | refresh=true"
