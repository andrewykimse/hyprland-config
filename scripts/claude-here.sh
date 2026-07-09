#!/usr/bin/env bash

dir="$HOME"
active_pid=$(hyprctl activewindow -j | jq -r '.pid // empty')

if [[ -n "$active_pid" ]]; then
    # Find the deepest child shell process
    shell_pid=$(pgrep -P "$active_pid" -a 2>/dev/null | grep -E '(bash|zsh|fish|nu)' | head -1 | awk '{print $1}')
    if [[ -n "$shell_pid" ]]; then
        cwd=$(readlink "/proc/$shell_pid/cwd" 2>/dev/null)
        [[ -d "$cwd" ]] && dir="$cwd"
    fi
fi

exec ghostty --working-directory="$dir" -e claude
