# Shell helpers that must be Nix-built because they need specific store paths in
# their closure. Plain-bash helpers live in ../scripts/ instead and need no Nix
# change to add.
{ config, lib, pkgs, wf-recorder, ... }:

{
  _module.args.hyprScripts = {
    screenshot-area = pkgs.writeShellScript "screenshot-area" ''
      grim -g "$(slurp)" - | wl-copy
    '';

    screenshot-full = pkgs.writeShellScript "screenshot-full" ''
      grim - | wl-copy
    '';

    record-area = pkgs.writeShellScript "record-area" ''
      mkdir -p "$HOME/Videos"
      exec ${wf-recorder}/bin/wf-recorder -g "$(slurp)" \
        -f "$HOME/Videos/$(date +%Y-%m-%d-%H%M%S).mp4"
    '';

    # wf-recorder prompts interactively when several outputs exist, which hangs
    # when launched from a menu, so pick the focused one explicitly.
    record-full = pkgs.writeShellScript "record-full" ''
      mkdir -p "$HOME/Videos"
      output=$(hyprctl -j activeworkspace | ${pkgs.jq}/bin/jq -r .monitor)
      exec ${wf-recorder}/bin/wf-recorder -o "$output" \
        -f "$HOME/Videos/$(date +%Y-%m-%d-%H%M%S).mp4"
    '';

    record-stop = pkgs.writeShellScript "record-stop" ''
      pkill -INT -x wf-recorder
    '';

    new-browser-window = pkgs.writeShellScript "new-browser-window" ''
      desktop=$(${pkgs.xdg-utils}/bin/xdg-settings get default-web-browser)
      desktop_file=$(find /run/current-system/sw/share/applications $HOME/.local/share/applications $HOME/.nix-profile/share/applications /usr/share/applications -name "$desktop" 2>/dev/null | head -1)
      binary=$(${pkgs.gnugrep}/bin/grep -m1 '^Exec=' "$desktop_file" | ${pkgs.gnused}/bin/sed 's/^Exec=//;s/ %.//g')
      exec ''${binary:-xdg-open} --new-window
    '';
  };
}
