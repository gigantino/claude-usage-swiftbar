#!/bin/bash

# <xbar.title>Claude Usage</xbar.title>
# <xbar.version>v2.1</xbar.version>
# <xbar.author>man</xbar.author>
# <xbar.desc>Displays Claude Code session usage in menu bar</xbar.desc>
# <xbar.dependencies>bash,tmux</xbar.dependencies>

CONFIG_FILE="$HOME/.claude-usage-config"
CACHE_FILE="$HOME/.claude-usage-cache"
LOCK_FILE="/tmp/claude-usage-fetch.lock"

# Default settings
SHOW_TIME=true
SHOW_ICON=true

# Load settings
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

# Load cache
USAGE="?%"
RESET_MINS=""
CACHE_TIME=0
[ -f "$CACHE_FILE" ] && source "$CACHE_FILE"

# Calculate time remaining dynamically
TIME_LEFT=""
if [ -n "$RESET_MINS" ]; then
    NOW_MINS=$((10#$(date +%H) * 60 + 10#$(date +%M)))
    if [ $RESET_MINS -gt $NOW_MINS ]; then
        DIFF=$((RESET_MINS - NOW_MINS))
    else
        DIFF=$((1440 - NOW_MINS + RESET_MINS))
    fi
    HOURS=$((DIFF / 60))
    MINS=$((DIFF % 60))
    if [ $HOURS -gt 0 ] && [ $MINS -gt 0 ]; then
        TIME_LEFT="${HOURS}h ${MINS}m left"
    elif [ $HOURS -gt 0 ]; then
        TIME_LEFT="${HOURS}h left"
    else
        TIME_LEFT="${MINS}m left"
    fi
fi

# Handle toggle commands
if [ "$1" = "toggle-time" ]; then
    SHOW_TIME=$( [ "$SHOW_TIME" = "true" ] && echo "false" || echo "true" )
    echo -e "SHOW_TIME=$SHOW_TIME\nSHOW_ICON=$SHOW_ICON" > "$CONFIG_FILE"
    exit 0
fi
if [ "$1" = "toggle-icon" ]; then
    SHOW_ICON=$( [ "$SHOW_ICON" = "true" ] && echo "false" || echo "true" )
    echo -e "SHOW_TIME=$SHOW_TIME\nSHOW_ICON=$SHOW_ICON" > "$CONFIG_FILE"
    exit 0
fi

# Background fetch function
fetch_usage() {
    SESSION="swiftbar-claude-$$"

    # Cleanup function - always remove lock and kill session
    cleanup() {
        rm -f "$LOCK_FILE"
        tmux kill-session -t "$SESSION" 2>/dev/null
    }

    # Check lock - use PID-based check (if process is dead, lock is stale)
    if [ -f "$LOCK_FILE" ]; then
        LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null)
        if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
            exit 0
        fi
        rm -f "$LOCK_FILE"
    fi

    # Create lock with our PID
    echo $$ > "$LOCK_FILE"
    trap cleanup EXIT

    # Kill any orphaned sessions from previous runs
    tmux list-sessions 2>/dev/null | grep "swiftbar-claude" | cut -d: -f1 | xargs -I{} tmux kill-session -t {} 2>/dev/null

    # Build PATH with common locations (without sourcing nvm.sh which is slow)
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

    # Add NVM paths if they exist (find any installed node version)
    if [ -d "$HOME/.nvm/versions/node" ]; then
        NVM_NODE=$(ls -t "$HOME/.nvm/versions/node" 2>/dev/null | head -1)
        [ -n "$NVM_NODE" ] && export PATH="$HOME/.nvm/versions/node/$NVM_NODE/bin:$PATH"
    fi

    # Find claude
    CLAUDE_BIN=$(which claude 2>/dev/null)
    [ -z "$CLAUDE_BIN" ] && exit 1

    tmux kill-session -t "$SESSION" 2>/dev/null
    tmux new-session -d -s "$SESSION" "$CLAUDE_BIN" || exit 1

    # Wait for claude to start
    sleep 4

    # Check if trust prompt is showing
    PANE_CHECK=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null)
    if echo "$PANE_CHECK" | grep -q "Yes, I trust this folder"; then
        tmux send-keys -t "$SESSION" "1"
        sleep 0.3
        tmux send-keys -t "$SESSION" C-m
        sleep 4
    fi

    # Send /usage command
    tmux send-keys -t "$SESSION" "/usage"
    sleep 0.3
    tmux send-keys -t "$SESSION" C-m
    sleep 4

    # Capture pane output
    CLEAN=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null)

    tmux send-keys -t "$SESSION" Escape
    sleep 0.3
    tmux send-keys -t "$SESSION" "/exit"
    sleep 0.3
    tmux send-keys -t "$SESSION" C-m
    sleep 1
    tmux kill-session -t "$SESSION" 2>/dev/null

    NEW_USAGE=$(echo "$CLEAN" | grep -A1 "Current session" | grep "% used" | grep -oE '[0-9]+%' | head -1)
    RESET_TIME=$(echo "$CLEAN" | grep -A2 "Current session" | grep "Resets" | sed 's/Resets //' | head -1)

    # Parse reset time to minutes since midnight
    NEW_RESET_MINS=""
    if [ -n "$RESET_TIME" ]; then
        TIME_PART=$(echo "$RESET_TIME" | grep -oE '[0-9]+:[0-9]+[ap]m|[0-9]+[ap]m' | head -1)
        RESET_HOUR=$(echo "$TIME_PART" | grep -oE '^[0-9]+')
        RESET_MIN=$(echo "$TIME_PART" | grep -oE ':[0-9]+' | tr -d ':')
        [ -z "$RESET_MIN" ] && RESET_MIN=0

        if echo "$TIME_PART" | grep -qi "pm"; then
            [ "$RESET_HOUR" -ne 12 ] && RESET_HOUR=$((RESET_HOUR + 12))
        elif echo "$TIME_PART" | grep -qi "am"; then
            [ "$RESET_HOUR" -eq 12 ] && RESET_HOUR=0
        fi

        NEW_RESET_MINS=$((10#$RESET_HOUR * 60 + 10#$RESET_MIN))
    fi

    # Save cache
    echo -e "USAGE=\"${NEW_USAGE:-?%}\"\nRESET_MINS=\"$NEW_RESET_MINS\"\nCACHE_TIME=$(date +%s)" > "$CACHE_FILE"
}

# Check if fetch needed (cache older than 25s)
NOW=$(date +%s)
CACHE_AGE=$((NOW - CACHE_TIME))
if [ $CACHE_AGE -gt 25 ]; then
    fetch_usage &
fi

# Output immediately from cache
ICON=""
[ "$SHOW_ICON" = "true" ] && ICON="✳ "

if [ "$SHOW_TIME" = "true" ] && [ -n "$TIME_LEFT" ]; then
    echo "${ICON}${USAGE} used, $TIME_LEFT"
else
    echo "${ICON}${USAGE} used"
fi

echo "---"
echo "Session: ${USAGE} used"
[ -n "$TIME_LEFT" ] && echo "Resets in: $TIME_LEFT"
echo "---"
[ "$SHOW_ICON" = "true" ] && echo "✓ Show icon | bash='$0' param1=toggle-icon terminal=false refresh=true" || echo "Show icon | bash='$0' param1=toggle-icon terminal=false refresh=true"
[ "$SHOW_TIME" = "true" ] && echo "✓ Show time | bash='$0' param1=toggle-time terminal=false refresh=true" || echo "Show time | bash='$0' param1=toggle-time terminal=false refresh=true"
echo "---"
echo "Refresh | refresh=true"
