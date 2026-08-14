#!/usr/bin/env bash
set -euo pipefail
CMD="${1:-random}"
WALL_PATH="${2:-}"
STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/ricelin-wallpaper"
_apply() {
  awww img "$1" \
    --transition-type wave \
    --transition-fps 60 \
    --transition-duration 1
  mkdir -p "$(dirname "$STATE_FILE")"
  printf '%s\n' "$1" > "$STATE_FILE"
}
case "$CMD" in
  set)
    [ -n "$WALL_PATH" ] || { echo "Usage: wallpaper.sh set <path>" >&2; exit 1; }
    _apply "$WALL_PATH"
    ;;
  random)
    img=$(find "${HYPR_WALLPAPER_DIR:-$HOME/sources/dotfiles/wallpapers}" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.png" \) 2>/dev/null | shuf -n 1)
    [ -n "$img" ] && _apply "$img"
    ;;
  *) echo "Unknown command: $CMD" >&2; exit 1 ;;
esac
