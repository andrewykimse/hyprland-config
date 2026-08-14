# Decoupling Hyprland config from dotfiles

**Date:** 2026-08-14
**Status:** Approved, not yet implemented

## Problem

Everything Hyprland-related should live in `hyprland-config`. Today it is split
across two repos, and the split is invisible from inside either one.

`hyprland-config/flake.nix` exports nothing (`outputs = { self, nixpkgs }: { }`).
The repo is consumed purely as a source tree: `dotfiles/modules/hyprland.nix`
(200 lines) does all the Nix work, reaching in via `${hyprland-config}/...`
string paths.

Five identifiers used by `hypr/hyprland.lua` — `mod`, `terminal`, `lock`,
`claude_here`, `browser` — are not declared in that file. They are injected as a
Lua preamble by `dotfiles/modules/hyprland.nix:71-75`, where each `_var` entry
becomes a `local` line in the generated config.

### The bug that motivated this

`hypr/hyprland.lua:191` binds `SUPER+E` to `nvim_here`, following the
`claude_here` template on line 190. It silently does nothing.

Cause: no `nvim_here = { _var = ...; }` entry was ever added to
`dotfiles/modules/hyprland.nix`, so the generated config declares five locals and
`nvim_here` is nil. `hl.dsp.exec_cmd(nil)` makes the whole `hl.bind` call fail,
so Hyprland never registers the key.

Confirmed empirically — the live bind table contained no SUPER+E at all:

```
$ hyprctl binds -j | jq -r '.[] | select(.key=="E") | "\(.modmask) \(.key)"'
65 E        # SUPER+SHIFT+E = hl.dsp.exit() (hyprland.lua:181)
            # modmask 64 (plain SUPER) absent entirely
```

The `scripts/nvim-here.sh` file itself was fine: correct logic, present in the
pinned store path, exec bit set. Only the Nix-side declaration was missing.

The class of bug matters more than the instance: a missing `_var` produces **no
error at config load** — no log line, no failed bind report, just a dead key.

## Goals

1. All Hyprland-related Nix lives in `hyprland-config`.
2. Adding a script or keybind requires **no Nix change**.
3. A missing injected value fails **loudly** instead of silently dropping a bind.

## Non-goals (deferred, with reasons)

- **`dotfiles/modules/quickshell.nix` migration.** It reads 9 files out of
  `hyprland-config/quickshell/`, so the rice stays split after this pass. Moving
  it requires `ricelin` and `hyprsphere` as inputs of *this* flake — a separate
  chunk of work. Goal 1 is therefore not fully met until that follow-up.
- **The `hyprsphere` startup line** (`modules/hyprland.nix:83-85`) is
  Quickshell-flavoured and depends on `qs` from the quickshell module. It stays in
  dotfiles this round, wired through the new `extraLua` option.
- **Unifying the duplicated screenshot/record logic.** See "Known duplication".
- **`hyprlandWrapped`** (nixGL wrapper, `hosts/work/home.nix:4-13`) stays in
  dotfiles: it is a host fact about a non-NixOS machine, not a Hyprland-config
  fact.

## Architecture

`hyprland-config/flake.nix` grows to export `homeManagerModules.default`,
following the existing precedent in the sibling `neovim-config` repo
(`flake.nix:80`). `dotfiles` shrinks to an import plus host-specific values.

```
hyprland-config/
  flake.nix                 → homeManagerModules.default (+ nixpkgs, flake-utils)
  nix/
    default.nix             → the HM module: options + config, imports the below
    packages.nix            → home.packages, xdg.portal, fonts
    scripts.nix             → nix-built helpers (new-browser-window, screenshot/record)
    desktop.nix             → the 13 xdg.desktopEntries
    services.nix            → hyprmoncfgd unit + monitors.lua seed activation
  hypr/hyprland.lua         → self-contained; no undeclared globals
  scripts/*.sh              → plain bash, installed to ~/.config/hypr/scripts
```

Verified that `pkgs.hyprmoncfg` is a plain nixpkgs attribute (no dotfiles
overlay), so the moved module evaluates standalone.

### Public interface

```nix
options.hyprland-config = {
  enable       = mkEnableOption "Hyprland configuration";
  package      = mkOption { type = types.package; default = pkgs.hyprland; };
  monitors     = mkOption { type = types.listOf (types.attrsOf types.anything); };
  mod          = mkOption { type = types.str; default = "SUPER"; };
  terminal     = mkOption { type = types.str; default = "ghostty"; };
  lockCommand  = mkOption { type = types.str; default = "hyprlock"; };
  wallpaperDir = mkOption { type = types.str; default = "$HOME/sources/dotfiles/wallpapers"; };
  extraEnv     = mkOption { type = types.listOf types.anything; default = []; };
  extraLua     = mkOption { type = types.lines; default = ""; };
};
```

`lockCommand` is consumed in **two** places, which is why it is one option rather
than a Lua-only var: the `SUPER+Escape` bind and the generated `hypridle.conf`
(see "Host override surface" below).

`extraEnv` exists because all three hosts set
`wayland.windowManager.hyprland.settings.env`, and the module itself must inject
`HYPR_WALLPAPER_DIR` there. Making it an option avoids the module and the hosts
fighting over the same list.

Host usage, replacing the current `mkForce` overrides:

```nix
imports = [ hyprland-config.homeManagerModules.default ];

hyprland-config = {
  enable      = true;
  package     = hyprlandWrapped;                   # nixGL wrap stays host-local
  lockCommand = "${pkgs.hyprlock}/bin/hyprlock";   # was mkForce at hosts/work/home.nix:29
  monitors    = [ /* studio display, U3425WE, fallback */ ];
  extraLua    = ''hl.config({ input = { kb_options = "caps:escape" } })'';
};
```

`extraLua` replaces the current `extraConfig` + `lib.mkAfter` pattern so hosts
need no knowledge of home-manager's `extraConfig` internals.

### Host override surface

Every override the three hosts apply today, and where it lands after the move.
The migration is not complete until each row is accounted for.

| Host | Current override | After |
|---|---|---|
| all three | `settings.monitor` (`mkForce`) | `monitors` option |
| all three | `settings.env` | `extraEnv` option |
| work | `package = hyprlandWrapped` (nixGL) | `package` option; wrapper stays in dotfiles |
| work-desktop | `package = hyprlandSystem` | `package` option; wrapper stays in dotfiles |
| work | `settings.lock` (`mkForce`, line 29) | `lockCommand` option |
| work | `xdg.configFile."hypr/hypridle.conf"` (`mkForce`, line 42) | `lockCommand` threaded into a generated hypridle.conf |
| work, firelink | `extraConfig` (`mkAfter` on work) | `extraLua` option |

The `hypridle.conf` row is the one worth calling out: the work host currently
**duplicates the entire 15-line config** verbatim from `hypr/hypridle.conf`, with
the sole difference being `hyprlock` → `${pkgs.hyprlock}/bin/hyprlock` in two
places. That is copy-paste drift waiting to happen — an edit to the repo's
`hypridle.conf` silently does nothing on the work host.

Fix: the module generates `hypridle.conf` from a template, substituting
`lockCommand`. `hypr/hypridle.conf` stays the readable source of truth and the
work host's `mkForce` block disappears. This is in scope because the whole point
is that editing config in this repo takes effect.

## The Lua contract

`hypr/hyprland.lua` gains a declared prologue:

```lua
-- Values injected by the home-manager module (nix/default.nix). Assert rather
-- than let a nil silently drop the hl.bind that uses it: a missing bind is
-- invisible until you press the key.
assert(mod, "mod not set by hyprland-config module")
assert(terminal, "terminal not set by hyprland-config module")
assert(lock, "lock not set by hyprland-config module")
assert(browser, "browser not set by hyprland-config module")

-- Repo scripts resolve at runtime; adding one needs no Nix change.
local scripts = os.getenv("HOME") .. "/.config/hypr/scripts"
```

The asserts work because the generated preamble's `local` declarations and the
`hyprland.lua` body share one Lua chunk — already proven by `claude_here`
resolving today.

### Injected vs runtime

**Injected** if Nix must compute the value (store path or host-specific absolute
path):

- `browser` — needs `xdg-utils`, `gnugrep`, `gnused` in its closure
- `lock` — the work host forces `${pkgs.hyprlock}/bin/hyprlock`
  (`hosts/work/home.nix:29`)
- `mod`, `terminal` — plain strings, but host-overridable

**Runtime** if it is a repo file — every `scripts/*.sh`. Lines 190-191 become:

```lua
hl.bind(mod .. " + C", hl.dsp.exec_cmd(scripts .. "/claude-here.sh"))
hl.bind(mod .. " + E", hl.dsp.exec_cmd(scripts .. "/nvim-here.sh"))
```

`claude_here` and `nvim_here` stop existing as Nix concepts. This kills the bug
class: a typo'd filename fails visibly at keypress, and a new script is just a
new file. This mirrors the pattern already used for the Quickshell binds at
`hyprland.lua:252`.

`scripts/` stays a plain recursive source copy (not a generated derivation),
which is what preserves "drop in a file, done".

### Wallpaper directory

The module exports `wallpaperDir` into Hyprland's `env` so spawned children
inherit it. `scripts/wallpaper.sh:20` and `scripts/wallpaper-thumbs.sh:3`
currently hardcode `$HOME/sources/dotfiles/wallpapers`; they take it with a
fallback so they stay runnable standalone:

```bash
WP_DIR="${HYPR_WALLPAPER_DIR:-$HOME/sources/dotfiles/wallpapers}"
```

Wallpaper image files stay in dotfiles; only the coupling becomes declared.

## Known duplication (moved verbatim, unified later)

Screenshot/record logic exists twice and the two copies are **not** equivalent:

- `hypr/hyprland.lua:209-232` — inline shell for the keybinds. Has `notify-send`
  feedback, an "already recording" guard, and the `slurp -r` window picker.
- `dotfiles/modules/hyprland.nix:8-29` — nix-built scripts for the desktop
  entries. Has the `ffmpeg_6`-pinned `wf-recorder` (0.6.0 fails against ffmpeg 9)
  and a focused-output fix for multi-monitor.

Unifying them is behaviour-changing in both directions, so it is deferred to its
own commit with its own verification. Folding it into a move-only migration would
make a regression ambiguous as to cause.

## Migration order

Each step is independently buildable; no step leaves the tree broken.

1. **`hyprland-config`: add the Nix module.** Move the four chunks into `nix/`,
   export `homeManagerModules.default`. `dotfiles` untouched, still builds against
   the old pin.
2. **`hyprland-config`: fix the Lua contract.** Assert prologue, `scripts` local,
   lines 190-191 to runtime paths, `HYPR_WALLPAPER_DIR` fallback in the two
   wallpaper scripts.
3. **`dotfiles`: switch the three hosts.** Delete `modules/hyprland.nix`; add the
   import and option values to `hosts/{work,work-desktop,firelink}/home.nix`; work
   through every row of the host override surface table, including deleting the
   work host's duplicated `hypridle.conf` block; move the `hyprsphere` startup
   line into `extraLua`.
4. **Deferred, separate commits:** unify screenshot/record; migrate
   `quickshell.nix`.

Note: `dotfiles` pins this repo by remote ref
(`git+ssh://git@github.com/andrewykimse/hyprland-config`), so local edits are
invisible to a build until pushed. Use `--override-input` to test against the
local checkout before pushing.

## Verification

Layered, cheapest first. Steps 1-3 are agent-runnable; step 4 requires the user.

```bash
# 1. Module evaluates
nix flake check ~/sources/hyprland-config

# 2. Host config builds against the LOCAL checkout, nothing pushed
cd ~/sources/dotfiles && nix build \
  --override-input hyprland-config path:/home/akim7/sources/hyprland-config \
  .#homeConfigurations."akim7@akim7-work-desktop".activationPackage

# 3. THE GATE: generated Lua must be equivalent
diff <(cat ~/.config/hypr/hyprland.lua) \
     ./result/home-files/.config/hypr/hyprland.lua

# 3b. Other generated hypr configs must be byte-identical (hypridle.conf is
#     newly generated from a template, so this is the check that matters)
for f in hypridle.conf hyprlock.conf hyprpaper.conf; do
  diff ~/.config/hypr/$f ./result/home-files/.config/hypr/$f && echo "$f OK"
done
```

Expected diff in step 3: `claude_here` leaves the locals, the assert prologue and
`scripts` local appear, two `hl.bind` lines change form. **Anything else is a
regression.** That is the pass/fail signal.

Because the original bug was a *silently missing* bind, add a count check that
would have caught it:

```bash
# baseline before switch: 62 binds, no plain-SUPER E
hyprctl binds -j | jq 'length'

# after switch: expect 63, and both modmasks present for E
hyprctl binds -j | jq -r '.[] | select(.key=="E") | "\(.modmask) \(.key)"'
# want: 64 E  (SUPER+E, previously dropped)
#       65 E  (SUPER+SHIFT+E, exit)
```

`64 E` appearing is direct proof the decoupling fixed the original symptom.

**4. Manual, user-driven.** Cannot be automated — an agent cannot confirm a
keybind fires. Ask the user to press: `SUPER+E` (nvim, the original bug),
`SUPER+C` (claude), `SUPER+B` / `SUPER+W` (wallpaper — exercises the env-var
change), `SUPER+SHIFT+Return` (browser — exercises an injected var),
`SUPER+Escape` (lock — exercises `lockCommand`), and the record binds. On the
work host also confirm idle-lock still fires (`hypridle.conf` is newly
generated). Report results rather than claiming success.

### Rollback

Step 3 is the only step touching a live host. Current generation is 96
(`home-manager generations`), so: `home-manager switch --rollback`, or activate
generation 96 directly.

## Prevention

The root cause was a cross-repo contract with no enforcement and no failure
signal. After this change:

- The contract is declared in one place (`options.hyprland-config`) and typed, so
  a missing or misnamed value is a Nix evaluation error.
- The residual runtime contract is asserted in Lua, so it fails at config load
  with a named message.
- The common case — adding a script or bind — no longer touches the contract at
  all.
