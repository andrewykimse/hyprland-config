# Desktop entries for the app launcher: power actions, toggles, and the
# screenshot/record helpers.
{ config, lib, hyprScripts, ... }:

let
  cfg = config.hyprland-config;
in
{
  config = lib.mkIf cfg.enable {
    xdg.desktopEntries = {
      shutdown = {
        name = "Shutdown";
        exec = "systemctl poweroff";
        icon = "system-shutdown";
        categories = [ "System" ];
      };
      reboot = {
        name = "Reboot";
        exec = "systemctl reboot";
        icon = "system-reboot";
        categories = [ "System" ];
      };
      suspend = {
        name = "Suspend";
        exec = "systemctl suspend";
        icon = "system-suspend";
        categories = [ "System" ];
      };
      lock = {
        name = "Lock Screen";
        exec = cfg.lockCommand;
        icon = "system-lock-screen";
        categories = [ "System" ];
      };
      logout = {
        name = "Logout";
        exec = "hyprctl dispatch exit";
        icon = "system-log-out";
        categories = [ "System" ];
      };
      restart-wifi = {
        name = "Restart WiFi";
        exec = "systemctl restart NetworkManager";
        icon = "network-wireless";
        categories = [ "System" ];
      };
      toggle-bluetooth = {
        name = "Toggle Bluetooth";
        exec = "rfkill toggle bluetooth";
        icon = "bluetooth";
        categories = [ "System" ];
      };
      screenshot-area = {
        name = "Screenshot (Area)";
        exec = "${hyprScripts.screenshot-area}";
        icon = "accessories-screenshot";
        categories = [ "Utility" ];
      };
      screenshot-full = {
        name = "Screenshot (Full)";
        exec = "${hyprScripts.screenshot-full}";
        icon = "accessories-screenshot";
        categories = [ "Utility" ];
      };
      record-area = {
        name = "Record (Area)";
        exec = "${hyprScripts.record-area}";
        icon = "media-record";
        categories = [ "Utility" ];
      };
      record-full = {
        name = "Record (Full)";
        exec = "${hyprScripts.record-full}";
        icon = "media-record";
        categories = [ "Utility" ];
      };
      record-stop = {
        name = "Record (Stop)";
        exec = "${hyprScripts.record-stop}";
        icon = "media-playback-stop";
        categories = [ "Utility" ];
      };
    };
  };
}
