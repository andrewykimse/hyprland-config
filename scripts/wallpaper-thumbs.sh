#!/usr/bin/env bash
set -euo pipefail
WP_DIR="${HYPR_WALLPAPER_DIR:-$HOME/sources/dotfiles/wallpapers}"
THUMB_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ricelin-wp-thumbs"
mkdir -p "$THUMB_DIR"
for thumb in "$THUMB_DIR"/*.png; do
  [ -f "$thumb" ] || continue
  src="$WP_DIR/$(basename "${thumb%.png}")"
  [ -f "$src" ] || rm -f "$thumb"
done
while IFS= read -r -d $'\0' img; do
  name="$(basename "$img")"
  thumb="$THUMB_DIR/${name}.png"
  [ -f "$thumb" ] && continue
  convert \
    -thumbnail 512x512^ -gravity center -extent 512x512 \
    "$img" "$thumb" 2>/dev/null || true
done < <(find "$WP_DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.png" \) -print0 2>/dev/null || true)
