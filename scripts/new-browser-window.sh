#!/usr/bin/env bash

desktop=$(xdg-settings get default-web-browser)
binary=$(grep -m1 '^Exec=' $(find /usr/share/applications /home/*/.local/share/applications /home/*/.nix-profile/share/applications /run/current-system/sw/share/applications -name "$desktop" 2>/dev/null | head -1) 2>/dev/null | sed 's/^Exec=//;s/ %.//g')

exec ${binary:-xdg-open} --new-window
