#!/bin/bash

# <xbar.title>Claude Usage</xbar.title>
# <xbar.version>v2.0</xbar.version>
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
TIME_LEFT=""
CACHE_TIME=0
[ -f "$CACHE_FILE" ] && source "$CACHE_FILE"

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
    # Don't run if already fetching
    [ -f "$LOCK_FILE" ] && exit 0
    touch "$LOCK_FILE"

    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

    CLAUDE_BIN=$(which claude 2>/dev/null)
    [ -z "$CLAUDE_BIN" ] && rm -f "$LOCK_FILE" && exit 1

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

    CLEAN=$(cat "$LOG_FILE" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
    NEW_USAGE=$(echo "$CLEAN" | grep -A1 "Current session" | grep "% used" | grep -oE '[0-9]+%' | head -1)
    RESET_TIME=$(echo "$CLEAN" | grep -A2 "Current session" | grep "Resets" | sed 's/Resets //' | head -1)
    rm -f "$LOG_FILE"

    # Calculate time remaining
    NEW_TIME_LEFT=""
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

        NOW_MINS=$((10#$(date +%H) * 60 + 10#$(date +%M)))
        RESET_MINS=$((10#$RESET_HOUR * 60 + 10#$RESET_MIN))

        if [ $RESET_MINS -gt $NOW_MINS ]; then
            DIFF=$((RESET_MINS - NOW_MINS))
        else
            DIFF=$((1440 - NOW_MINS + RESET_MINS))
        fi

        HOURS=$((DIFF / 60))
        MINS=$((DIFF % 60))

        if [ $HOURS -gt 0 ] && [ $MINS -gt 0 ]; then
            NEW_TIME_LEFT="${HOURS}h ${MINS}m left"
        elif [ $HOURS -gt 0 ]; then
            NEW_TIME_LEFT="${HOURS}h left"
        else
            NEW_TIME_LEFT="${MINS}m left"
        fi
    fi

    # Save cache
    echo -e "USAGE=\"${NEW_USAGE:-?%}\"\nTIME_LEFT=\"$NEW_TIME_LEFT\"\nCACHE_TIME=$(date +%s)" > "$CACHE_FILE"
    rm -f "$LOCK_FILE"
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
