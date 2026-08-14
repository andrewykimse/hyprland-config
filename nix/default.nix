# Home-manager module for the Hyprland desktop. Owns everything Hyprland-related
# so that this repo is self-contained: editing a script or keybind here takes
# effect without touching the consuming dotfiles repo.
{ config, lib, pkgs, hyprScripts, ... }:

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
    wayland.windowManager.hyprland = {
      enable = true;
      package = cfg.package;
      configType = "lua";
      settings = {
        # These four become `local` declarations in the generated Lua preamble.
        # Only values Nix must compute belong here; repo scripts resolve at
        # runtime from ~/.config/hypr/scripts instead, so adding one needs no
        # Nix change. hyprland.lua asserts each of these is set.
        mod      = { _var = cfg.mod; };
        terminal = { _var = cfg.terminal; };
        lock     = { _var = cfg.lockCommand; };
        browser  = { _var = "${hyprScripts.new-browser-window}"; };
        monitor  = cfg.monitors;
        env      = cfg.extraEnv ++ [
          { _args = [ "HYPR_WALLPAPER_DIR" cfg.wallpaperDir ]; }
        ];
      };
      extraConfig = builtins.readFile ../hypr/hyprland.lua
        + lib.optionalString (cfg.extraLua != "") "\n${cfg.extraLua}";
    };

    xdg.configFile."hypr/hyprland.conf" = { text = "# See hyprland.lua"; force = true; };
    xdg.configFile."hypr/hyprpaper.conf".source = ../hypr/hyprpaper.conf;
    xdg.configFile."hypr/hyprlock.conf".source = ../hypr/hyprlock.conf;

    # Generated rather than copied so lockCommand can be substituted: hosts
    # without hyprlock on PATH need an absolute store path. Previously each such
    # host duplicated this whole file, which meant edits to hypr/hypridle.conf
    # silently did nothing there.
    xdg.configFile."hypr/hypridle.conf".text =
      builtins.replaceStrings [ "hyprlock" ] [ cfg.lockCommand ]
        (builtins.readFile ../hypr/hypridle.conf);

    xdg.configFile."hypr/scripts" = {
      source = ../scripts;
      recursive = true;
    };
  };
}
