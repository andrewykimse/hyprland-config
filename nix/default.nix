# Home-manager module for the Hyprland desktop. Owns everything Hyprland-related
# so that this repo is self-contained: editing a script or keybind here takes
# effect without touching the consuming dotfiles repo.
{ config, lib, pkgs, ... }:

let
  cfg = config.hyprland-config;
in
{
  imports = [
    ./args.nix
    ./packages.nix
    ./scripts.nix
    ./desktop.nix
    ./services.nix
  ];

  options.hyprland-config = {
    enable = lib.mkEnableOption "Hyprland configuration";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.hyprland;
      description = "Hyprland package. Override with a nixGL- or system-wrapped derivation on non-NixOS hosts.";
    };

    monitors = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = [
        { output = "eDP-1"; mode = "preferred"; position = "auto"; scale = 2; }
        { output = "";      mode = "preferred"; position = "auto"; scale = 1; }
      ];
      description = "Monitor layout, in hyprland settings.monitor form.";
    };

    mod = lib.mkOption {
      type = lib.types.str;
      default = "SUPER";
      description = "Primary modifier key for keybinds.";
    };

    terminal = lib.mkOption {
      type = lib.types.str;
      default = "ghostty";
      description = "Terminal command. Must accept --working-directory, --class and -e.";
    };

    lockCommand = lib.mkOption {
      type = lib.types.str;
      default = "hyprlock";
      description = "Screen lock command. Used by both the lock keybind and hypridle.conf; needs an absolute path on hosts without hyprlock on PATH.";
    };

    wallpaperDir = lib.mkOption {
      type = lib.types.str;
      default = "$HOME/sources/dotfiles/wallpapers";
      description = "Wallpaper source directory, exported to scripts as HYPR_WALLPAPER_DIR. Unexpanded shell syntax is intentional: it is consumed by bash, not Nix.";
    };

    extraEnv = lib.mkOption {
      type = lib.types.listOf lib.types.anything;
      default = [ ];
      description = "Additional hyprland settings.env entries, in { _args = [ name value ]; } form.";
    };

    extraLua = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Host-specific Lua appended to hyprland.lua.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Populated by later tasks.
  };
}
