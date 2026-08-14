# Hyprland Config Decoupling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move all Hyprland-related Nix out of `dotfiles/modules/hyprland.nix` into `hyprland-config` as an exported home-manager module, so adding a script or keybind needs no Nix change.

**Architecture:** `hyprland-config/flake.nix` grows to export `homeManagerModules.default` (following the `neovim-config` precedent). The module lives in `nix/`, split by responsibility. `hypr/hyprland.lua` becomes self-contained: repo scripts resolve at runtime from `~/.config/hypr/scripts`, and the few genuinely Nix-computed values are asserted so a missing one fails loudly instead of silently dropping a keybind.

**Tech Stack:** Nix flakes, home-manager modules, Hyprland's Lua config format (`hyprlang`-alternative Lua backend via `configType = "lua"`), bash.

**Spec:** `docs/superpowers/specs/2026-08-14-hyprland-config-decoupling-design.md`

## Global Constraints

- Work on branch `decouple-hyprland-config` in `/home/akim7/sources/hyprland-config`. The spec is already committed there as `d1e4dce`.
- **This repo has no test framework and no CI.** The verification cycle is: `nix flake check`, then build the host activation package, then `diff` the generated output against the currently-live config. That diff **is** the test. Do not invent a test framework.
- `dotfiles` pins this repo by remote ref (`git+ssh://git@github.com/andrewykimse/hyprland-config`), so local edits are invisible to a `nix build` unless `--override-input hyprland-config path:/home/akim7/sources/hyprland-config` is passed. **Every build command in this plan uses that flag.** Do not push to make a build work.
- **Every build also needs `--impure`.** The `nixgl` input reads `builtins.currentTime` (`nixGL.nix:224`) to force rebuilds, which pure evaluation rejects with `error: attribute 'currentTime' missing`. This is pre-existing and unrelated to our changes — the baseline build fails the same way without it.
- Current live host is `akim7@akim7-work-desktop`; current home-manager generation is **96**. Rollback is `home-manager switch --rollback`.
- Nix is purely functional: `nix build` produces `./result` and mutates nothing. Only `home-manager switch` touches the live session. **No task in this plan runs `home-manager switch`** — that is deferred to the user in Task 8.
- Do not touch `dotfiles/modules/quickshell.nix`. It reads 9 files from `hyprland-config/quickshell/` and is explicitly out of scope.
- Do not unify the duplicated screenshot/record logic. Move it verbatim. Out of scope per spec.
- `hyprlandWrapped` (work) and `hyprlandSystem` (work-desktop) stay in `dotfiles`. They are host facts.
- Preserve every comment when moving code. The comments explain non-obvious things (the `ffmpeg_6` pin, the `monitors.lua` seeding rationale, the btop font-size workaround) and are the most valuable part of what is moving.

---

## File Structure

**In `hyprland-config` (create):**

| File | Responsibility |
|---|---|
| `nix/default.nix` | The home-manager module: declares `options.hyprland-config`, wires `wayland.windowManager.hyprland`, imports the four below. |
| `nix/packages.nix` | `home.packages`, `xdg.portal`, the `wf-recorder` ffmpeg pin. |
| `nix/scripts.nix` | Nix-built shell helpers (`new-browser-window`, screenshot/record) that need store paths in their closure. |
| `nix/desktop.nix` | The 13 `xdg.desktopEntries`. |
| `nix/services.nix` | `hyprmoncfgd` systemd unit + the `monitors.lua` seed activation script. |

**In `hyprland-config` (modify):**

| File | Change |
|---|---|
| `flake.nix` | Export `homeManagerModules.default`; add `flake-utils` input. |
| `hypr/hyprland.lua` | Assert prologue; `scripts` local moved to top; lines 190-191 use runtime paths. |
| `scripts/wallpaper.sh` | `$HYPR_WALLPAPER_DIR` with fallback. |
| `scripts/wallpaper-thumbs.sh` | `$HYPR_WALLPAPER_DIR` with fallback. |

**In `dotfiles` (modify):**

| File | Change |
|---|---|
| `modules/hyprland.nix` | **Delete.** |
| `hosts/work/home.nix` | Import the flake module; convert 5 overrides to options; delete duplicated `hypridle.conf`. |
| `hosts/work-desktop/home.nix` | Import the flake module; convert 3 overrides to options. |
| `hosts/firelink/home.nix` | Import the flake module; convert 3 overrides to options. |

`dotfiles/flake.nix` needs **no change**: it already passes `hyprland-config`
via `extraSpecialArgs` for all three Hyprland hosts (`inherit ... hyprland-config`
on the `firelink`, `work-laptop`, and `work-desktop` entries), which is how the
current `modules/hyprland.nix` receives it. Only the `flake.lock` revision bump
matters, and that is deferred (see Task 7 Step 10).

Why this split: `nix/default.nix` owns the option interface and nothing else, so the public contract is readable in one file. The other four are grouped by what a reader would look for ("where do desktop entries come from?"), not by technical layer.

---

## Task 1: Establish the baseline

No code changes. This captures the "known good" state that every later `diff` compares against. Without it, later tasks have nothing to verify against and the plan's whole test strategy collapses.

**Files:**
- Create: `/tmp/hypr-baseline/` (scratch, not committed)

**Interfaces:**
- Consumes: nothing.
- Produces: `/tmp/hypr-baseline/hyprland.lua`, `/tmp/hypr-baseline/binds.txt`, `/tmp/hypr-baseline/generated/` — the reference outputs. Later tasks diff against these exact paths.

- [ ] **Step 1: Snapshot the live generated config**

```bash
mkdir -p /tmp/hypr-baseline
cp ~/.config/hypr/hyprland.lua /tmp/hypr-baseline/hyprland.lua
for f in hypridle.conf hyprlock.conf hyprpaper.conf; do
  cp ~/.config/hypr/$f /tmp/hypr-baseline/$f
done
ls -la /tmp/hypr-baseline/
```

Expected: four files present.

- [ ] **Step 2: Record the live bind table — this is the original bug's fingerprint**

```bash
hyprctl binds -j | jq 'length' > /tmp/hypr-baseline/bind-count.txt
hyprctl binds -j | jq -r '.[] | "\(.modmask)\t\(.key)"' | sort > /tmp/hypr-baseline/binds.txt
cat /tmp/hypr-baseline/bind-count.txt
grep -P '^6[45]\tE$' /tmp/hypr-baseline/binds.txt
```

Expected: count is `62`. The grep shows **only** `65	E` (SUPER+SHIFT+E). The absence of `64	E` is the bug — plain SUPER+E never registered.

- [ ] **Step 3: Build the current host config from the unmodified pin**

```bash
cd ~/sources/dotfiles
nix build --impure --no-link --print-out-paths \
  .#homeConfigurations."akim7@akim7-work-desktop".activationPackage \
  > /tmp/hypr-baseline/activation-path.txt
cat /tmp/hypr-baseline/activation-path.txt
```

Expected: one `/nix/store/...-home-manager-generation` path. This proves the baseline builds *before* we change anything — so if a later build breaks, we know it was us.

- [ ] **Step 4: Snapshot the generated tree from that build**

```bash
cp -rL "$(cat /tmp/hypr-baseline/activation-path.txt)/home-files/.config/hypr" \
  /tmp/hypr-baseline/generated
ls /tmp/hypr-baseline/generated/
```

Expected: `hyprland.lua`, `hypridle.conf`, `hyprlock.conf`, `hyprpaper.conf`, `scripts/`.

- [ ] **Step 5: Confirm the baseline build matches the live session**

```bash
diff /tmp/hypr-baseline/generated/hyprland.lua /tmp/hypr-baseline/hyprland.lua \
  && echo "BASELINE CLEAN: build matches live session"
```

Expected: `BASELINE CLEAN`. If this differs, **stop** — the live session is out of sync with the flake (someone switched without committing), and every later diff would be measured against a moving target. Report to the user instead of proceeding.

- [ ] **Step 6: No commit** — this task creates only scratch files in `/tmp`. Nothing to commit.

---

## Task 2: Export a home-manager module skeleton from the flake

Smallest change that makes `hyprland-config` a module provider. Deliberately does nothing yet — it only has to *evaluate*, so we prove the flake plumbing before piling config into it.

**Files:**
- Modify: `hyprland-config/flake.nix`
- Create: `hyprland-config/nix/default.nix`

**Interfaces:**
- Consumes: nothing.
- Produces: `homeManagerModules.default` — a home-manager module taking `{ config, lib, pkgs, ... }`. Declares `options.hyprland-config` with: `enable` (bool), `package` (package), `monitors` (listOf attrs), `mod` (str), `terminal` (str), `lockCommand` (str), `wallpaperDir` (str), `extraEnv` (listOf anything), `extraLua` (lines). All later tasks add to this same option set and read `cfg = config.hyprland-config`.

- [ ] **Step 1: Write the flake with the module export**

Note `homeManagerModules` is **not** system-namespaced, so it sits outside `eachDefaultSystem`. Putting it inside is the classic error here — home-manager consumes `homeManagerModules.default` directly, and a system-keyed attrset there fails with a confusing "value is a set while a module was expected".

Write `flake.nix`:

```nix
{
  description = "Hyprland configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    # Not system-namespaced: home-manager consumes this module directly and
    # resolves pkgs from the importing configuration.
    homeManagerModules.default = import ./nix/default.nix;
  };
}
```

- [ ] **Step 2: Write the module skeleton with the full option interface**

Write `nix/default.nix`:

```nix
# Home-manager module for the Hyprland desktop. Owns everything Hyprland-related
# so that this repo is self-contained: editing a script or keybind here takes
# effect without touching the consuming dotfiles repo.
{ config, lib, pkgs, ... }:

let
  cfg = config.hyprland-config;
in
{
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
```

- [ ] **Step 3: Verify the flake evaluates and the module is exported**

```bash
cd ~/sources/hyprland-config
nix flake check 2>&1 | tail -5
nix eval .#homeManagerModules.default --apply 'm: builtins.typeOf m'
```

Expected: `nix flake check` reports no errors. The eval prints `"lambda"`.

- [ ] **Step 4: Verify the option interface evaluates under a real module system**

A flake check alone will not catch a malformed `mkOption`, because nothing has instantiated the module yet. Force instantiation:

```bash
cd ~/sources/hyprland-config
nix eval --impure --expr '
  let
    pkgs = import <nixpkgs> {};
    result = pkgs.lib.evalModules {
      modules = [
        { _module.args.pkgs = pkgs; }
        ./nix/default.nix
        { hyprland-config.enable = false; }
      ];
    };
  in builtins.attrNames result.config.hyprland-config
'
```

Expected: `[ "enable" "extraEnv" "extraLua" "lockCommand" "mod" "monitors" "package" "terminal" "wallpaperDir" ]`

- [ ] **Step 5: Commit**

```bash
cd ~/sources/hyprland-config
git add flake.nix nix/default.nix
git commit -m "$(cat <<'EOF'
export home-manager module skeleton

Declares the option interface that replaces the implicit cross-repo contract
with dotfiles. No config yet -- this only has to evaluate.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Move packages, portal, and services

Move the parts with no Lua interaction first. Verified beforehand that `pkgs.hyprmoncfg` is a plain nixpkgs attribute (no dotfiles overlay), so this evaluates standalone.

**Files:**
- Create: `hyprland-config/nix/packages.nix`
- Create: `hyprland-config/nix/services.nix`
- Modify: `hyprland-config/nix/default.nix`

**Interfaces:**
- Consumes: `options.hyprland-config` from Task 2.
- Produces: `_module.args.wf-recorder` (declared in `nix/default.nix`) — the ffmpeg_6-pinned derivation, shared so Task 4's record scripts use the identical build rather than overriding it a second time. Both `packages.nix` and `scripts.nix` take it as a function argument.

- [ ] **Step 0: Declare the shared `wf-recorder` pin in `nix/args.nix`**

**Corrected during execution.** This cannot go in `nix/default.nix`: the module
system rejects a top-level `_module` in any file that also declares
`options`/`config` (`error: Module ... has an unsupported attribute '_module'`),
and moving it inside `config` would make the argument unavailable while the
modules consuming it are still being evaluated. It gets its own file with no
`options`/`config` keys:

```nix
# Shared derivations passed to the other module files as arguments.
#
# This file deliberately contains only `_module.args` and no `options`/`config`
# keys: the module system rejects a top-level `_module` in any file that also
# declares those, and putting it inside `config` would make the argument
# unavailable while the modules that take it are still being evaluated.
{ pkgs, ... }:

{
  # wf-recorder 0.6.0 doesn't build against ffmpeg's default (9.0): it reads
  # AVCodec.sample_fmts, a field removed upstream. Pin ffmpeg_6 until
  # wf-recorder is patched for the new API. Shared so packages.nix (which
  # installs it) and scripts.nix (which calls it) use one identical build.
  _module.args.wf-recorder = pkgs.wf-recorder.override { ffmpeg = pkgs.ffmpeg_6; };
}
```

Then `nix/default.nix` imports `./args.nix` first in its `imports` list.

**Verification note:** `nix flake check` does NOT catch this class of error, and a
bare `lib.evalModules` cannot evaluate this module at all (`services.nix` needs
home-manager's `config.lib.dag` and `home.activation`). The real check is building
an actual host with the module imported but `enable = false`, which also proves
the `mkIf` guard makes it inert.

- [ ] **Step 1: Write `nix/packages.nix`**

Copied from `dotfiles/modules/hyprland.nix:4-7,38-65`, comments intact:

```nix
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
```

- [ ] **Step 2: Write `nix/services.nix`**

Copied from `dotfiles/modules/hyprland.nix:98-124`, comments intact:

```nix
# The hyprmoncfg monitor-profile daemon and its state file seeding.
{ config, lib, pkgs, ... }:

let
  cfg = config.hyprland-config;
in
{
  config = lib.mkIf cfg.enable {
    # hyprland.lua does `require("monitors")`, expecting hyprmoncfgd to have
    # written ~/.config/hypr/monitors.lua. Seed a stub with hyprmoncfg's own
    # "generated" header on first activation only, so the daemon's real writes
    # afterward are never clobbered by a home-manager switch.
    home.activation.seedHyprMonitorsLua = config.lib.dag.entryAfter [ "writeBoundary" ] ''
      monitorsLua="$HOME/.config/hypr/monitors.lua"
      if [ ! -e "$monitorsLua" ]; then
        $DRY_RUN_CMD install -Dm644 ${pkgs.writeText "monitors.lua" "-- Generated by hyprmoncfg\n"} "$monitorsLua"
      fi
    '';

    systemd.user.services.hyprmoncfgd = {
      Unit = {
        Description = "Hyprland monitor profile daemon (hyprmoncfgd)";
        After = [ "hyprland-session.target" ];
        PartOf = [ "hyprland-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.hyprmoncfg}/bin/hyprmoncfgd";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install = {
        WantedBy = [ "hyprland-session.target" ];
      };
    };
  };
}
```

- [ ] **Step 3: Wire both into `nix/default.nix`**

Add the `imports` list immediately after the opening `{` of the module body (before `options`):

```nix
{
  imports = [
    ./packages.nix
    ./services.nix
  ];

  options.hyprland-config = {
```

- [ ] **Step 4: Verify it still evaluates**

```bash
cd ~/sources/hyprland-config
nix flake check 2>&1 | tail -5 && echo "FLAKE OK"
```

Expected: `FLAKE OK`.

- [ ] **Step 5: Commit**

```bash
cd ~/sources/hyprland-config
git add nix/
git commit -m "$(cat <<'EOF'
move packages, portal and hyprmoncfgd into the module

Verbatim from dotfiles/modules/hyprland.nix. The wf-recorder ffmpeg_6 pin is
shared via _module.args so the record scripts reuse the same derivation.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Move nix-built scripts and desktop entries

**Files:**
- Create: `hyprland-config/nix/scripts.nix`
- Create: `hyprland-config/nix/desktop.nix`
- Modify: `hyprland-config/nix/default.nix`

**Interfaces:**
- Consumes: `wf-recorder` from Task 3's `_module.args`.
- Produces: `_module.args.hyprScripts` — an attrset with keys `new-browser-window`, `screenshot-area`, `screenshot-full`, `record-area`, `record-full`, `record-stop`, each a store path from `writeShellScript`. Task 5 reads `hyprScripts.new-browser-window` for the `browser` Lua var; `desktop.nix` reads the other five.

- [ ] **Step 1: Write `nix/scripts.nix`**

Verbatim from `dotfiles/modules/hyprland.nix:8-35`. These stay Nix-built (rather than becoming `scripts/*.sh` files) because each needs specific store paths in its closure — `xdg-utils`, `gnugrep`, `gnused`, the pinned `wf-recorder`.

```nix
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
```

- [ ] **Step 2: Write `nix/desktop.nix`**

Verbatim from `dotfiles/modules/hyprland.nix:126-199`, with the five `${script}` interpolations now reading from `hyprScripts`:

```nix
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
```

Note the one intentional change from verbatim: the `lock` entry's `exec` was the hardcoded string `"hyprlock"` and is now `cfg.lockCommand`. That is the fix for the work host, where bare `hyprlock` is not on the launcher's PATH.

- [ ] **Step 3: Wire both into `nix/default.nix`**

Extend the `imports` list:

```nix
  imports = [
    ./packages.nix
    ./scripts.nix
    ./desktop.nix
    ./services.nix
  ];
```

- [ ] **Step 4: Verify evaluation**

```bash
cd ~/sources/hyprland-config
nix flake check 2>&1 | tail -5 && echo "FLAKE OK"
```

Expected: `FLAKE OK`.

- [ ] **Step 5: Commit**

```bash
cd ~/sources/hyprland-config
git add nix/
git commit -m "$(cat <<'EOF'
move nix-built scripts and desktop entries into the module

Verbatim, except the lock desktop entry now uses cfg.lockCommand so hosts
without hyprlock on PATH get an absolute path.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Wire the Hyprland settings and generated configs

The heart of the module. This is where `hypridle.conf` stops being duplicated by the work host.

**Files:**
- Modify: `hyprland-config/nix/default.nix`

**Interfaces:**
- Consumes: `hyprScripts.new-browser-window` (Task 4), all options (Task 2).
- Produces: `wayland.windowManager.hyprland.settings` with exactly four Lua locals — `mod`, `terminal`, `lock`, `browser`. `claude_here` is deliberately **gone**; Task 6 makes `hyprland.lua` resolve scripts at runtime instead. Also produces the generated `~/.config/hypr/{hypridle,hyprlock,hyprpaper}.conf` and `~/.config/hypr/scripts/`.

- [ ] **Step 1: Replace the empty `config` block in `nix/default.nix`**

Replace `config = lib.mkIf cfg.enable { # Populated by later tasks. };` with:

```nix
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
```

Add `hyprScripts` to the module's argument list on the first line:

```nix
{ config, lib, pkgs, hyprScripts, ... }:
```

- [ ] **Step 2: Verify the hypridle substitution is exactly right**

`replaceStrings` is blunt — confirm it hits the intended 2 occurrences and nothing else. The file contains `hyprlock` on lines 2 and 8 only; critically, no *other* word in the file contains `hyprlock` as a substring.

```bash
cd ~/sources/hyprland-config
grep -n hyprlock hypr/hypridle.conf
nix eval --impure --raw --expr '
  builtins.replaceStrings [ "hyprlock" ] [ "/nix/store/XXX/bin/hyprlock" ]
    (builtins.readFile ./hypr/hypridle.conf)
'
```

Expected: grep shows exactly 2 matches (lines 2, 8). The eval output shows both replaced and the rest of the file untouched.

- [ ] **Step 3: Verify default (unsubstituted) output is byte-identical to the baseline**

With `lockCommand` at its `"hyprlock"` default, `replaceStrings` is a no-op, so the generated file must exactly match today's copied file. This is the check that proves we did not regress the two hosts that don't override it.

```bash
cd ~/sources/hyprland-config
diff <(nix eval --impure --raw --expr '
  builtins.replaceStrings [ "hyprlock" ] [ "hyprlock" ]
    (builtins.readFile ./hypr/hypridle.conf)
') /tmp/hypr-baseline/hypridle.conf && echo "HYPRIDLE IDENTICAL AT DEFAULT"
```

Expected: `HYPRIDLE IDENTICAL AT DEFAULT`.

Note: `/tmp/hypr-baseline/hypridle.conf` is the **work-desktop** host's file, which does not override `lockCommand` — so it should match the repo file as-is. (The work *laptop* is the host with the override; it is not the machine we build here.)

- [ ] **Step 4: Verify evaluation**

```bash
cd ~/sources/hyprland-config
nix flake check 2>&1 | tail -5 && echo "FLAKE OK"
```

Expected: `FLAKE OK`. It will *not* catch a broken `hyprland.lua` reference — that surfaces in Task 7's real build.

- [ ] **Step 5: Commit**

```bash
cd ~/sources/hyprland-config
git add nix/default.nix
git commit -m "$(cat <<'EOF'
wire hyprland settings and generated configs

Drops claude_here from the injected Lua locals -- the next commit makes
hyprland.lua resolve repo scripts at runtime instead.

hypridle.conf is now generated with lockCommand substituted, replacing the
work host's verbatim duplicate of the whole file. Verified byte-identical to
the previous output when lockCommand is at its default.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Make hyprland.lua self-contained

Fixes the original bug and its whole class.

**Files:**
- Modify: `hyprland-config/hypr/hyprland.lua:1-2` (prologue), `:190-191` (the binds), `:252` (dedupe the `scripts` local)
- Modify: `hyprland-config/scripts/wallpaper.sh:20`
- Modify: `hyprland-config/scripts/wallpaper-thumbs.sh:3`

**Interfaces:**
- Consumes: the four Lua locals from Task 5 (`mod`, `terminal`, `lock`, `browser`); `HYPR_WALLPAPER_DIR` from Task 5's `env`.
- Produces: a `hyprland.lua` with no undeclared globals. Later reads of `scripts` (the existing line 253-257 Quickshell binds) use the single top-level local this task introduces.

- [ ] **Step 1: Add the assert prologue at the very top of `hypr/hyprland.lua`**

Insert **above** the existing line 1 comment (`-- Monitor layout is managed by hyprmoncfg...`):

```lua
-- Values injected as Lua locals by the home-manager module (nix/default.nix).
-- Assert rather than let a nil silently drop the hl.bind that uses it: passing
-- nil to a dispatcher makes the whole hl.bind call fail, so the key just never
-- registers -- no error at config load, no log line, just a dead key.
assert(mod, "mod not set by hyprland-config module")
assert(terminal, "terminal not set by hyprland-config module")
assert(lock, "lock not set by hyprland-config module")
assert(browser, "browser not set by hyprland-config module")

-- Scripts in this repo resolve at runtime, so adding one needs no Nix change.
local scripts = os.getenv("HOME") .. "/.config/hypr/scripts"

```

- [ ] **Step 2: Point the two binds at runtime script paths**

Replace lines 190-191 (`claude_here` / `nvim_here`):

```lua
hl.bind(mod .. " + C", hl.dsp.exec_cmd(scripts .. "/claude-here.sh"))
hl.bind(mod .. " + E", hl.dsp.exec_cmd(scripts .. "/nvim-here.sh"))
```

- [ ] **Step 3: Remove the now-duplicate `scripts` local**

The file already declares `scripts` under the `-- Quickshell` heading. Step 1 hoisted it to the top, so delete the later one. Change:

```lua
-- Quickshell
local scripts = os.getenv("HOME") .. "/.config/hypr/scripts"
hl.bind(mod .. " + Space", hl.dsp.exec_cmd(scripts .. "/launcher.sh"))
```

to:

```lua
-- Quickshell
hl.bind(mod .. " + Space", hl.dsp.exec_cmd(scripts .. "/launcher.sh"))
```

Leaving both would shadow harmlessly but is exactly the kind of near-duplicate that drifts.

- [ ] **Step 4: Verify no undeclared globals remain, and the file loads**

First write the stub harness. `hyprland.lua` *executes* at load (it iterates
`hl.get_windows()` at line 57 and calls `remember_focus`), so a naive
`__index`-returns-function metatable is not enough — `get_windows` must return an
actual empty table. This harness was verified against the real file:

```bash
cd ~/sources/hyprland-config
cat > /tmp/lua-harness.lua <<'EOF'
-- Stub the hl API surface hyprland.lua touches at load time.
local function noop() end
local function stub_tbl()
  return setmetatable({}, {__index = function() return noop end})
end
hl = {
  on = noop, bind = noop, config = noop, curve = noop,
  animation = noop, define_submap = noop, dispatch = noop,
  exec_cmd = noop, env = noop,
  get_windows = function() return {} end,
  get_workspace_windows = function() return {} end,
  get_active_workspace = function() return { id = 1 } end,
}
hl.dsp = setmetatable({
  window = stub_tbl(), focus = noop, layout = noop, exec_cmd = noop,
  exit = noop, submap = noop,
}, {__index = function() return noop end})
package.preload["monitors"] = function() return {} end
EOF
```

Then check:

```bash
cd ~/sources/hyprland-config
# claude_here / nvim_here must be gone entirely
grep -n "claude_here\|nvim_here" hypr/hyprland.lua && echo "FAIL: stale var" || echo "OK: no stale vars"
# exactly one scripts local
grep -c 'local scripts = os.getenv' hypr/hyprland.lua
# load with all four values present
nix run nixpkgs#lua5_4 -- -e '
  dofile("/tmp/lua-harness.lua")
  mod="SUPER" terminal="ghostty" lock="hyprlock" browser="/bin/true"
  local f=assert(loadfile("hypr/hyprland.lua")) f()
  print("LUA PARSE+RUN OK")
'
```

Expected: `OK: no stale vars`, then `1`, then `LUA PARSE+RUN OK`.

`lua` is not installed on this host, hence `nix run nixpkgs#lua5_4`. A bare
`luac -p` is **not** sufficient — it catches syntax errors but not the nil-global
bug this task exists to prevent.

- [ ] **Step 5: Confirm the asserts actually fire**

The asserts are the safety net; an untested safety net is decoration. Omit one
value and require a raise:

```bash
cd ~/sources/hyprland-config
nix run nixpkgs#lua5_4 -- -e '
  dofile("/tmp/lua-harness.lua")
  mod="SUPER" terminal="ghostty" lock="hyprlock"   -- browser deliberately unset
  local ok,err=pcall(function() local f=assert(loadfile("hypr/hyprland.lua")) f() end)
  if ok then print("FAIL: missing browser did not raise") os.exit(1) end
  print("ASSERT FIRES: "..err)
'
```

Expected output (verified against a patched copy while writing this plan):

```
ASSERT FIRES: hypr/hyprland.lua:4: browser not set by hyprland-config module
```

This is the regression test for the original bug — under the old code, a missing
value produced silence and a dead key.

- [ ] **Step 6: Make the wallpaper scripts read the env var**

In `scripts/wallpaper-thumbs.sh` line 3:

```bash
WP_DIR="${HYPR_WALLPAPER_DIR:-$HOME/sources/dotfiles/wallpapers}"
```

In `scripts/wallpaper.sh` line 20, replace the hardcoded path inside the `find`:

```bash
    img=$(find "${HYPR_WALLPAPER_DIR:-$HOME/sources/dotfiles/wallpapers}" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.png" \) 2>/dev/null | shuf -n 1)
```

The fallback keeps both runnable when invoked outside a Hyprland session.

- [ ] **Step 7: Verify the scripts still pass a syntax check and honour the var**

```bash
cd ~/sources/hyprland-config
bash -n scripts/wallpaper.sh && bash -n scripts/wallpaper-thumbs.sh && echo "BASH SYNTAX OK"
HYPR_WALLPAPER_DIR=/tmp/wp-probe bash -x scripts/wallpaper-thumbs.sh 2>&1 | grep -m1 wp-probe
```

Expected: `BASH SYNTAX OK`, then a trace line containing `/tmp/wp-probe` — proving the override is read rather than ignored.

- [ ] **Step 8: Commit**

```bash
cd ~/sources/hyprland-config
git add hypr/hyprland.lua scripts/wallpaper.sh scripts/wallpaper-thumbs.sh
git commit -m "$(cat <<'EOF'
make hyprland.lua self-contained

Fixes SUPER+E, which silently never registered: it referenced nvim_here, a
_var that was never declared in dotfiles, and hl.dsp.exec_cmd(nil) makes the
whole hl.bind call fail with no error at config load.

Repo scripts now resolve at runtime from ~/.config/hypr/scripts, so adding one
needs no Nix change. The four remaining injected values are asserted, so a
missing one fails loudly at config load instead of dropping a keybind.

Wallpaper dir comes from HYPR_WALLPAPER_DIR with a fallback.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Switch the three hosts in dotfiles

**Files:**
- Delete: `dotfiles/modules/hyprland.nix`
- Modify: `dotfiles/hosts/work/home.nix` — line 1 signature, line 18 import, delete lines 23, 25-27, 29, 31-35, 37-40, 42-60
- Modify: `dotfiles/hosts/work-desktop/home.nix` — line 1 signature, line 13 import, delete lines 18, 20-23, 25-32
- Modify: `dotfiles/hosts/firelink/home.nix` — line 1 signature, line 4 import, delete lines 11-14, 16-21, 23-25

`dotfiles/flake.nix` is **not** modified — it already passes `hyprland-config`
through `extraSpecialArgs` for all three hosts.

Delete from the bottom up (highest line number first) so earlier deletions do not
shift the line numbers of later ones.

**Interfaces:**
- Consumes: `hyprland-config.homeManagerModules.default` and `options.hyprland-config` from Tasks 2-6.
- Produces: nothing downstream. Terminal task for the code changes.

- [ ] **Step 1: Add the module to each host's imports via the flake**

`hosts/*/home.nix` are imported as plain paths, so they receive `hyprland-config` through `extraSpecialArgs` (already passed for all three hosts). Change each host's function signature and imports.

In `hosts/work/home.nix` line 1, add `hyprland-config`:

```nix
{ config, pkgs, nixgl, hyprland-config, ... }:
```

and in its `imports` list, replace `../../modules/hyprland.nix` with:

```nix
    hyprland-config.homeManagerModules.default
```

- [ ] **Step 2: Convert the work host's overrides to options**

Delete these blocks from `hosts/work/home.nix` (bottom-up: 42-60, then 37-40, 31-35, 29, 25-27, 23):
- line 23 `wayland.windowManager.hyprland.package = hyprlandWrapped;`
- lines 25-27 the `extraConfig` `mkAfter` block
- line 29 the `settings.lock` `mkForce`
- lines 31-35 the `settings.monitor` `mkForce`
- lines 37-40 the `settings.env` list
- lines 42-60 the entire `xdg.configFile."hypr/hypridle.conf"` `mkForce` block

Keep the `hyprlandWrapped` `let` binding at lines 4-13 — it is still referenced,
now as the `package` option value.

Replace with a single block:

```nix
  hyprland-config = {
    enable      = true;
    package     = hyprlandWrapped;
    lockCommand = "${pkgs.hyprlock}/bin/hyprlock";
    extraLua    = ''hl.config({ input = { kb_options = "caps:escape" } })'';
    monitors = [
      { output = "desc:Apple Computer Inc StudioDisplay"; mode = "5120x2880@60"; position = "auto"; scale = 2; }
      { output = "desc:Dell Inc. DELL U3425WE";           mode = "3440x1440@60"; position = "auto"; scale = 1; }
      { output = ""; mode = "preferred"; position = "auto"; scale = 1; }
    ];
    extraEnv = [
      { _args = [ "PATH" "${config.home.homeDirectory}/.nix-profile/bin:/usr/local/bin:/usr/bin:/bin" ]; }
      { _args = [ "XDG_DATA_DIRS" "${config.home.homeDirectory}/.nix-profile/share:/usr/local/share:/usr/share" ]; }
    ];
  };
```

The deleted `hypridle.conf` block is now redundant: Task 5 generates it from `hypr/hypridle.conf` with `lockCommand` substituted, producing the same result without the duplication.

- [ ] **Step 3: Convert the work-desktop host**

`hosts/work-desktop/home.nix` line 1 → add `hyprland-config` to the signature. Replace `../../modules/hyprland.nix` (line 13) in imports with `hyprland-config.homeManagerModules.default`. Delete bottom-up: lines 25-32 (`env`), 20-23 (`monitor` mkForce), 18 (`package`). Keep the `hyprlandSystem` `let` binding at lines 4-8. Add:

```nix
  hyprland-config = {
    enable  = true;
    package = hyprlandSystem;
    monitors = [
      { output = "desc:Dell Inc. DELL U3425WE"; mode = "3440x1440@60"; position = "auto"; scale = 1; }
      { output = ""; mode = "preferred"; position = "auto"; scale = 1; }
    ];
    extraEnv = [
      { _args = [ "PATH" "${config.home.homeDirectory}/.nix-profile/bin:/usr/local/bin:/usr/bin:/bin" ]; }
      { _args = [ "XDG_DATA_DIRS" "${config.home.homeDirectory}/.nix-profile/share:/usr/local/share:/usr/share" ]; }
      { _args = [ "GBM_BACKEND" "nvidia-drm" ]; }
      { _args = [ "__GLX_VENDOR_LIBRARY_NAME" "nvidia" ]; }
      { _args = [ "LIBVA_DRIVER_NAME" "nvidia" ]; }
      { _args = [ "XDG_SESSION_TYPE" "wayland" ]; }
    ];
  };
```

- [ ] **Step 4: Convert the firelink host**

`hosts/firelink/home.nix` line 1 is `{ config, pkgs, ... }:` → becomes `{ config, pkgs, hyprland-config, ... }:`. Replace the import at line 4. Delete bottom-up: lines 23-25 (`extraConfig`), 16-21 (`env`), 11-14 (`monitor` mkForce). Add:

```nix
  hyprland-config = {
    enable = true;
    monitors = [
      { output = "desc:Apple Computer Inc StudioDisplay"; mode = "5120x2880@60"; position = "auto"; scale = 2; }
      { output = ""; mode = "preferred"; position = "auto"; scale = 1; }
    ];
    extraLua = ''hl.config({ cursor = { no_hardware_cursors = true } })'';
    extraEnv = [
      { _args = [ "XDG_DATA_DIRS" "${config.home.homeDirectory}/.nix-profile/share:/usr/local/share:/usr/share" ]; }
      { _args = [ "LIBVA_DRIVER_NAME" "nvidia" ]; }
      { _args = [ "GBM_BACKEND" "nvidia-drm" ]; }
      { _args = [ "__GLX_VENDOR_LIBRARY_NAME" "nvidia" ]; }
    ];
  };
```

firelink keeps `package` at the default (`pkgs.hyprland`) — it is the NixOS host and never overrode it.

- [ ] **Step 5: Delete the old module**

```bash
cd ~/sources/dotfiles
git rm modules/hyprland.nix
```

- [ ] **Step 6: Build all three hosts against the local checkout**

```bash
cd ~/sources/dotfiles
for h in "akim7@akim7-work-desktop" "akim7@akim7-work-laptop" "andrewkim@firelink"; do
  echo "=== $h ==="
  nix build --impure --no-link --print-out-paths \
    --override-input hyprland-config path:/home/akim7/sources/hyprland-config \
    ".#homeConfigurations.\"$h\".activationPackage" || echo "BUILD FAILED: $h"
done
```

Expected: three store paths, no `BUILD FAILED`. All three must build — a broken laptop or firelink config would only surface the next time you switched on that machine.

- [ ] **Step 7: THE GATE — diff generated Lua against the baseline**

```bash
cd ~/sources/dotfiles
nix build --impure -o /tmp/hypr-new \
  --override-input hyprland-config path:/home/akim7/sources/hyprland-config \
  .#homeConfigurations."akim7@akim7-work-desktop".activationPackage
diff /tmp/hypr-baseline/generated/hyprland.lua \
     /tmp/hypr-new/home-files/.config/hypr/hyprland.lua
```

Expected diff, and **nothing else**:
- `local claude_here = "..."` removed from the preamble
- `hl.env("HYPR_WALLPAPER_DIR", ...)` added
- the assert prologue and top-level `local scripts` added
- the two `hl.bind` lines for `+ C` / `+ E` changed to `scripts .. "/..."` form
- the `-- Quickshell` section's `local scripts` line removed

Any other change is a regression — investigate before continuing. In particular `hl.env(...)` ordering and the monitor lines must be unchanged.

- [ ] **Step 8: Verify the other generated configs are byte-identical**

```bash
for f in hypridle.conf hyprlock.conf hyprpaper.conf; do
  diff /tmp/hypr-baseline/generated/$f /tmp/hypr-new/home-files/.config/hypr/$f \
    && echo "$f IDENTICAL"
done
ls /tmp/hypr-new/home-files/.config/hypr/scripts/ | tr '\n' ' '
```

Expected: all three `IDENTICAL` (work-desktop does not override `lockCommand`, so the substitution is a no-op), and the scripts listing includes `nvim-here.sh`.

- [ ] **Step 9: Verify the work laptop gets its substituted hypridle**

The one host where `lockCommand` differs — confirm the substitution actually happened and the duplication is genuinely redundant now.

```bash
cd ~/sources/dotfiles
nix build --impure -o /tmp/hypr-laptop \
  --override-input hyprland-config path:/home/akim7/sources/hyprland-config \
  .#homeConfigurations."akim7@akim7-work-laptop".activationPackage
grep -c '/nix/store/.*/bin/hyprlock' /tmp/hypr-laptop/home-files/.config/hypr/hypridle.conf
grep 'local lock' /tmp/hypr-laptop/home-files/.config/hypr/hyprland.lua
```

Expected: `2` (both `hyprlock` occurrences became absolute store paths), and the `local lock` line shows an absolute `/nix/store/...` path.

- [ ] **Step 10: Commit both repos**

```bash
cd ~/sources/dotfiles
git add -A
git commit -m "$(cat <<'EOF'
consume hyprland-config's home-manager module

Deletes modules/hyprland.nix: all of it now lives in the hyprland-config repo,
which exports homeManagerModules.default. Hosts set typed options instead of
mkForce-ing internals.

Drops the work host's verbatim duplicate of hypridle.conf -- the module
generates it from the repo file with lockCommand substituted, so edits to
hypr/hypridle.conf now take effect there instead of being silently ignored.

Verified: all three hosts build, and generated hyprland.lua diffs against the
previous output only in the intended lines.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

Do **not** update `dotfiles/flake.lock` to a pushed `hyprland-config` revision yet — that requires pushing this branch, which is Task 8's decision point.

---

## Task 8: Hand off for live verification

An agent cannot confirm a keybind fires. This task stops and reports.

**Files:** none.

**Interfaces:**
- Consumes: verified builds from Task 7.
- Produces: nothing.

- [ ] **Step 1: Re-state what is verified vs unverified**

Report to the user, honestly separating the two:

**Verified by build + diff:** all three hosts evaluate and build; generated `hyprland.lua` differs only in the intended lines; `hypridle.conf`/`hyprlock.conf`/`hyprpaper.conf` byte-identical on work-desktop; `hypridle.conf` correctly substituted on the work laptop; `nvim-here.sh` present in the installed scripts dir; the Lua asserts fire when a value is missing.

**Not verified — needs a human:** that any key actually does the thing.

- [ ] **Step 2: Give the user the switch and rollback commands**

```bash
# switch (requires pushing the branch first, or keep using --override-input)
cd ~/sources/dotfiles
home-manager switch --impure --flake .#"akim7@akim7-work-desktop" \
  --override-input hyprland-config path:/home/akim7/sources/hyprland-config

# roll back to generation 96 if anything misbehaves
home-manager switch --rollback
```

- [ ] **Step 3: Give the post-switch check that proves the original bug is fixed**

```bash
hyprctl reload
hyprctl binds -j | jq 'length'                       # expect 63 (was 62)
hyprctl binds -j | jq -r '.[] | select(.key=="E") | "\(.modmask) \(.key)"'
# expect BOTH:  64 E  (SUPER+E, previously silently missing)
#               65 E  (SUPER+SHIFT+E, exit)
```

`64 E` appearing is direct proof the decoupling fixed the reported symptom.

- [ ] **Step 4: Ask the user to exercise the keybinds**

- `SUPER+E` → neovim in the focused terminal's cwd **(the original bug)**
- `SUPER+C` → claude in the focused terminal's cwd
- `SUPER+B` and `SUPER+W` → wallpaper random / picker (exercises `HYPR_WALLPAPER_DIR`)
- `SUPER+SHIFT+Return` → new browser window (exercises the `browser` injected var)
- `SUPER+Escape` → lock (exercises `lockCommand`)
- `SUPER+SHIFT+S`, `SUPER+SHIFT+W`, `SUPER+SHIFT+R` → record start/window/stop
- Launcher entries "Record (Full)" and "Lock Screen" (exercises `nix/desktop.nix`)
- On the work laptop specifically: leave it idle 5 min and confirm idle-lock fires

Wait for results. Report them as-is; do not claim success on the user's behalf.

- [ ] **Step 5: No commit.**

---

## Deferred follow-ups

Both are out of scope here, recorded so they are not lost:

1. **Unify the duplicated screenshot/record logic.** `hypr/hyprland.lua:209-232` (inline shell for keybinds — has `notify-send` feedback, "already recording" guard, `slurp -r` window picker) and `nix/scripts.nix` (for desktop entries — has the `ffmpeg_6`-pinned `wf-recorder`, focused-output fix). Neither is a superset; unifying changes behaviour in both directions, so it needs its own commit and its own verification.
2. **Migrate `dotfiles/modules/quickshell.nix`.** It reads 9 files from `hyprland-config/quickshell/` and needs `ricelin` + `hyprsphere` as inputs of this flake. Until then the goal "everything Hyprland-related lives here" is not fully met, and the `hyprsphere` startup line stays in dotfiles.
