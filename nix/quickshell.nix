# The Quickshell desktop shell: a patched build of the Ricelin rice plus the
# hyprsphere window-switcher overlay.
#
# Ricelin is consumed as a source tree and patched at build time rather than
# forked, so upstream fixes arrive with a flake input bump. Everything this repo
# overrides lives in ../quickshell/ as a plain .qml file, so changing the rice
# means editing QML here -- no Nix change needed.
{ ricelin, hyprsphere }:

{ config, lib, pkgs, ... }:

let
  cfg = config.hyprland-config;
  qcfg = cfg.quickshell;

  # nixGL-wrapped hosts must wrap BOTH binaries: upstream pkgs.quickshell ships
  # `quickshell` and the shorter `qs`, and the Ricelin configs plus our own
  # scripts invoke `qs`. Wrapping only one silently breaks every
  # `qs -c ... ipc call` -- and hl.dsp.exec_cmd discards the error, so the
  # keybind just does nothing. Doing the wrapping here means a host says "use
  # nixGL" and cannot get the binary set wrong.
  wrapped =
    if qcfg.nixGL == null then qcfg.package
    else pkgs.runCommand "quickshell-nixgl" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
      mkdir -p $out/bin
      for bin in quickshell qs; do
        makeWrapper ${qcfg.nixGL} $out/bin/$bin \
          --add-flags "${qcfg.package}/bin/$bin"
      done
    '';

  qs = wrapped;

  override = name: path: pkgs.writeText name (builtins.readFile path);

  draculaTheme       = override "Theme.qml"      ../quickshell/Theme.qml;
  pillOverride       = override "Pill.qml"       ../quickshell/pill/Pill.qml;
  glyphIconOverride  = override "GlyphIcon.qml"  ../quickshell/pill/GlyphIcon.qml;
  batterySurface     = override "Battery.qml"    ../quickshell/pill/Battery.qml;
  devicesOverride    = override "Devices.qml"    ../quickshell/pill/Singletons/Devices.qml;
  mixerOverride      = override "Mixer.qml"      ../quickshell/pill/Mixer.qml;
  workspacesOverride = override "Workspaces.qml" ../quickshell/pill/Workspaces.qml;
  shellOverride      = override "shell.qml"      ../quickshell/pill/shell.qml;

  # Patch the Ricelin quickshell config:
  #   1. Replace all Theme.qml files with the Dracula-adapted version
  #   2. Remap the hardcoded ~/Ricelin/wallpapers fallback to wallpaperDir.
  #      Only the *fallback* is rewritten: Walls.qml prefers Flags.wallpaperDir,
  #      which is user-mutable state persisted by Flags.qml's JsonAdapter, so
  #      substituting that would fight the user's own setting.
  #   3. Replace pill/Pill.qml, pill/GlyphIcon.qml and pill/Mixer.qml with our
  #      battery-percentage/power-profile/internal-backlight-augmented
  #      versions, pill/Singletons/Devices.qml with a version that adds
  #      brightnessctl-backed backlight control, pill/Workspaces.qml with a
  #      version that recognizes the eDP-1 internal panel, pill/shell.qml with
  #      a version where peek/pin can pull the pill back into view even while
  #      a window is fullscreen, and add the new pill/Battery.qml surface
  quickshellConfig = pkgs.runCommand "quickshell-ricelin-config" {
    nativeBuildInputs = [ pkgs.gnused pkgs.python3 ];
  } ''
    cp -r ${ricelin}/configs/quickshell $out
    chmod -R u+w $out
    find $out -name "Theme.qml" -exec cp ${draculaTheme} {} \;
    sed -i 's|/Ricelin/wallpapers|${qcfg.ricelinWallpaperPath}|g' $out/pill/Singletons/Walls.qml
    cp ${pillOverride} $out/pill/Pill.qml
    cp ${glyphIconOverride} $out/pill/GlyphIcon.qml
    cp ${batterySurface} $out/pill/Battery.qml
    cp ${devicesOverride} $out/pill/Singletons/Devices.qml
    cp ${mixerOverride} $out/pill/Mixer.qml
    cp ${workspacesOverride} $out/pill/Workspaces.qml
    cp ${shellOverride} $out/pill/shell.qml
    mkdir -p $out/hyprsphere
    cp ${hyprsphere}/shell.qml $out/hyprsphere/shell.qml
    chmod u+w $out/hyprsphere/shell.qml
    sed -i 's|"\$HOME/.local/share/applications/\*.desktop|"\$HOME/.nix-profile/share/applications/*.desktop \$HOME/.local/share/applications/*.desktop|' $out/hyprsphere/shell.qml
    # hyprctl dispatch with Lua dispatcher syntax needs hyprctl eval + hl.dispatch() wrapper
    sed -i 's|"hyprctl", "dispatch",|"hyprctl", "eval",|g' $out/hyprsphere/shell.qml
    sed -i "s|'hl\.dsp\.\(.*\)']);|'hl.dispatch(hl.dsp.\1)']);|g" $out/hyprsphere/shell.qml
    # Resolve named icons (e.g. "steam") to their highest-res file path so QML
    # uses file:// and scales smoothly, instead of image://icon/ which doesn't
    # do size fallback in quickshell's provider.
    cat > $out/hyprsphere/resolve-icon.sh << 'RESOLVE_EOF'
#!/usr/bin/env bash
ic="$1"
[ -z "$ic" ] && exit 1
case "$ic" in /*) [ -f "$ic" ] && echo "$ic" && exit 0 ;; esac
for sz in 512x512 256x256 128x128 scalable 64x64 48x48 32x32; do
  for base in "$HOME/.nix-profile/share/icons" /run/current-system/sw/share/icons; do
    for ext in png svg; do
      p="$base/hicolor/$sz/apps/$ic.$ext"
      [ -f "$p" ] && echo "$p" && exit 0
    done
  done
done
echo "$ic"
RESOLVE_EOF
    chmod +x $out/hyprsphere/resolve-icon.sh
    python3 - $out/hyprsphere/shell.qml << 'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()
old = '"grep -E \'^(Name=|Icon=|StartupWMClass=|Exec=)\' \\"$f\\" 2>/dev/null; " +'
new = (
    '"grep -E \'^(Name=|StartupWMClass=|Exec=)\' \\"$f\\" 2>/dev/null; " +\n'
    '            "ic=$(grep -m1 \'^Icon=\' \\"$f\\" 2>/dev/null | cut -d= -f2-); '
    'if [ -n \\"$ic\\" ]; then '
    'r=$($HOME/.config/quickshell/hyprsphere/resolve-icon.sh \\"$ic\\"); '
    'echo \\"Icon=$r\\"; fi; " +'
)
assert old in content, "Pattern not found in shell.qml!"
content = content.replace(old, new, 1)
with open(path, 'w') as f:
    f.write(content)
PYEOF
    cp -r ${hyprsphere}/lib $out/hyprsphere/lib
    cp ${../quickshell/hyprsphere.json} $out/hyprsphere/hyprsphere.json
  '';
in
{
  options.hyprland-config.quickshell = {
    enable = lib.mkEnableOption "the Ricelin-based Quickshell desktop shell";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.quickshell;
      description = "Quickshell package. Set nixGL instead of overriding this to wrap for non-NixOS hosts.";
    };

    nixGL = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "\${nixgl.packages.x86_64-linux.nixGLDefault}/bin/nixGL";
      description = ''
        Path to a nixGL binary to wrap Quickshell with, for hosts without a
        system GL driver in the store. Null means use the package unwrapped.
        Both `quickshell` and `qs` are wrapped.
      '';
    };

    ricelinWallpaperPath = lib.mkOption {
      type = lib.types.str;
      default = "/sources/dotfiles/wallpapers";
      description = ''
        Replacement for Ricelin's hardcoded `~/Ricelin/wallpapers` fallback,
        as a $HOME-relative path with a leading slash. Only the fallback is
        patched; a wallpaper folder set in the pill's own settings takes
        precedence and is left alone.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && qcfg.enable) {
    home.packages = with pkgs; [
      qs
      cliphist
      wl-clipboard
      ddcutil
      awww
      imagemagick
      jq
      inter
      noto-fonts-cjk-sans
      qt6Packages.qt5compat
    ];

    fonts.fontconfig.enable = true;

    # Launch the hyprsphere overlay at Hyprland startup. Needs this module's
    # wrapped quickshell and qt5compat's QML import path, both of which are
    # local facts, so it is contributed here rather than by the consumer.
    hyprland-config.extraLua = ''
      hl.on("hyprland.start", function()
        hl.exec_cmd("sh -c 'QML2_IMPORT_PATH=${pkgs.qt6Packages.qt5compat}/lib/qt-6/qml ${qs}/bin/quickshell -c hyprsphere'")
      end)
    '';

    xdg.configFile."quickshell".source = quickshellConfig;
  };
}
