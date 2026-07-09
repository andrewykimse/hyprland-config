#!/usr/bin/env bash

dir="$HOME"
window_json=$(hyprctl activewindow -j)
title=$(echo "$window_json" | jq -r '.title // empty')

# Ghostty sets the window title to the CWD of the active tab/split
if [[ "$title" == "~/"* ]]; then
    expanded="${title/#\~/$HOME}"
    [[ -d "$expanded" ]] && dir="$expanded"
elif [[ "$title" == "/"* && -d "$title" ]]; then
    dir="$title"
fi

exec ghostty --working-directory="$dir" -e claude
