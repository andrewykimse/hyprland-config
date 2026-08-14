# Packages and portal registration for the Hyprland desktop.
{ config, lib, pkgs, wf-recorder, ... }:

let
  cfg = config.hyprland-config;
in
{
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      hyprpaper
      hypridle
      hyprpolkitagent
      hyprmoncfg
      grim
      slurp
      wl-clipboard
      cliphist
      brightnessctl
      playerctl
      pavucontrol
    ] ++ [ wf-recorder ];

    # Registers hyprland.portal in the profile's portal dir and points the frontend
    # at it, so ScreenCast (screen recording and sharing) has a backend.
    xdg.portal = {
      enable = true;
      extraPortals = [
        config.wayland.windowManager.hyprland.finalPortalPackage
        pkgs.xdg-desktop-portal-gtk
      ];
      config.common = {
        default = [ "hyprland" "gtk" ];
        "org.freedesktop.impl.portal.ScreenCast" = [ "hyprland" ];
        "org.freedesktop.impl.portal.Screenshot" = [ "hyprland" ];
      };
    };
  };
}
