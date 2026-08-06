#!/usr/bin/env bash
set -euo pipefail
THUMB_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cliphist-thumbs"
mkdir -p "$THUMB_DIR"
mapfile -t current_ids < <(cliphist list 2>/dev/null | awk -F'\t' '{print $1}')
for thumb in "$THUMB_DIR"/*.png; do
  [ -f "$thumb" ] || continue
  id="$(basename "${thumb%.png}")"
  found=0
  for cid in "${current_ids[@]}"; do [ "$cid" = "$id" ] && found=1 && break; done
  [ "$found" = "0" ] && rm -f "$thumb"
done
while IFS=$'\t' read -r id preview; do
  [[ "$preview" =~ ^\[\[\ binary\ data\ .*\.(png|jpg|jpeg|gif|bmp|webp) ]] || continue
  thumb="$THUMB_DIR/${id}.png"
  [ -f "$thumb" ] && continue
  printf '%s' "$id" | cliphist decode 2>/dev/null \
    | convert - \
      -thumbnail 256x256^ -gravity center -extent 256x256 \
      "$thumb" 2>/dev/null || true
done < <(cliphist list 2>/dev/null)
