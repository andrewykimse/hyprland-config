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

-- Monitor layout is managed by hyprmoncfg, which writes ~/.config/hypr/monitors.lua.
require("monitors")

-- Startup
hl.on("hyprland.start", function()
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_DATA_DIRS")
    hl.exec_cmd("systemctl --user restart xdg-desktop-portal")
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("wl-paste --watch cliphist store")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("quickshell -p " .. os.getenv("HOME") .. "/.config/quickshell/pill")
    hl.exec_cmd("quickshell -p " .. os.getenv("HOME") .. "/.config/quickshell/launcher")
    hl.exec_cmd("quickshell -p " .. os.getenv("HOME") .. "/.config/quickshell/rishot")
end)

-- New windows land on whatever workspace is focused when they map, not the
-- workspace of whatever spawned them. Walk up the process tree from a new
-- window's pid, and if some ancestor tells us where it belongs, move the
-- window there instead. Processes that daemonize/reparent before their
-- window maps, or that have no such ancestor at all (launched from a
-- keybind or app menu), fall through to the default placement.
--
-- Two sources of "where it belongs", checked per ancestor as we walk up:
--
-- 1. HYPR_SPAWN_WORKSPACE in the ancestor's environment (see shell.nix):
--    each shell tags itself with the workspace it was opened on, so any
--    descendant of a shell carries a precise answer regardless of pid.
--    This is what disambiguates Ghostty tabs -- see point 2.
-- 2. pid_focus, our own record of the last workspace a pid was focused on.
--    This is the fallback for windows with no shell ancestor at all
--    (launched from an app menu/launcher, or a shell that predates this
--    tagging). The walk starts at the window's *parent*, deliberately
--    skipping the window's own pid: Ghostty (and anything else
--    single-instance) hands new windows to one already-running process, so
--    a terminal you just opened with a keybind shares its pid with
--    whatever terminal window was last focused, possibly on another
--    workspace. Matching on the window's own pid would "route" it back
--    there -- indistinguishable from, and overridden by, the far more
--    common case of just wanting a new terminal where you already are.
--
-- pid_focus is also the reason (1) is necessary rather than sufficient on
-- its own: Ghostty is single-instance, so every tab/window it owns shares
-- one pid, and pid_focus (keyed by pid) can't tell tabs apart -- it just
-- remembers whichever tab was *last focused*, which drifts to wherever
-- you're currently typing if you have more than one tab open. A shell's
-- own HYPR_SPAWN_WORKSPACE sidesteps that entirely by naming the workspace
-- directly, so it's checked first and wins whenever it's present.
local pid_focus = {}

local function remember_focus(win)
    if not (win.pid and win.workspace) then return end
    pid_focus[win.pid] = win.workspace.id
end

for _, w in ipairs(hl.get_windows()) do
    remember_focus(w)
end

hl.on("window.active", remember_focus)

hl.on("window.open", function(win)
    if not win.pid or not win.address then return end

    local function parent_pid(pid)
        local f = io.open("/proc/" .. pid .. "/stat", "r")
        if not f then return nil end
        local line = f:read("*l")
        f:close()
        if not line then return nil end
        local rest = line:match("%)%s*(.*)")
        local ppid = rest and rest:match("^%S+%s+(%d+)")
        return ppid and tonumber(ppid)
    end

    local function spawn_env_workspace(pid)
        local f = io.open("/proc/" .. pid .. "/environ", "rb")
        if not f then return nil end
        local data = f:read("*a")
        f:close()
        if not data then return nil end
        local ws = data:match("HYPR_SPAWN_WORKSPACE=(%d+)")
        return ws and tonumber(ws)
    end

    local pid, target, fallback = parent_pid(win.pid), nil, nil
    for _ = 1, 20 do
        if not pid or pid <= 1 then break end
        target = spawn_env_workspace(pid)
        if target then break end
        fallback = fallback or pid_focus[pid]
        pid = parent_pid(pid)
    end
    target = target or fallback

    if target and (not win.workspace or win.workspace.id ~= target) then
        -- A newly opened window grabs input focus, and moving the focused
        -- window to another workspace drags the monitor's view along with
        -- it. Since the point here is to keep working undisturbed on
        -- whatever workspace was actually active, switch straight back.
        local active_ws = hl.get_active_workspace()
        hl.dispatch(hl.dsp.window.move({ workspace = target, window = "address:" .. win.address }))
        if active_ws and active_ws.id ~= target then
            hl.dispatch(hl.dsp.focus({ workspace = active_ws.id }))
        end
    end
end)

-- Lid switch
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("hyprctl keyword monitor \"eDP-1, disable\""), { locked = true })
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("hyprctl keyword monitor \"eDP-1, preferred, auto, 2\""),
    { locked = true })

-- Config
hl.config({
    general = {
        gaps_in     = 4,
        gaps_out    = 8,
        border_size = 2,
        col         = {
            active_border   = { colors = { "rgba(bd93f9ee)", "rgba(ff79c6ee)" }, angle = 45 },
            inactive_border = "rgba(44475aaa)",
        },
        layout      = "scrolling",
    },
    decoration = {
        rounding = 6,
        blur = {
            enabled = true,
        },
    },
    input = {
        kb_layout    = "us",
        follow_mouse = 1,
        touchpad     = {
            natural_scroll = true,
        },
    },
    scrolling = {
        column_width = 0.333,
    },
})

-- Auto-fit column width to the number of open windows on a workspace, up to
-- 3 columns; beyond that, columns stay at 1/3 width and scroll off-screen.
local function fit_scrolling_columns()
    local ws = hl.get_active_workspace()
    if not ws then return end
    local count = 0
    for _, w in ipairs(hl.get_workspace_windows(ws)) do
        if w.mapped and not w.floating then
            count = count + 1
        end
    end
    if count == 0 then return end
    local width = string.format("%.4f", 1 / math.min(count, 3))
    hl.dispatch(hl.dsp.layout("colresize all " .. width))
    if count <= 3 then
        hl.dispatch(hl.dsp.layout("fit all"))
    end
end

for _, event in ipairs({ "window.open", "window.close", "window.destroy", "window.move_to_workspace", "workspace.active" }) do
    hl.on(event, fit_scrolling_columns)
end

-- Animations
hl.curve("snap", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.0 } } })

hl.animation({ leaf = "windows", enabled = true, speed = 2, bezier = "snap" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2, bezier = "snap", style = "popin 80%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 2, bezier = "snap" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 2, bezier = "snap" })
hl.animation({ leaf = "fade", enabled = true, speed = 2, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 8, bezier = "default" })

-- Keybinds
hl.bind(mod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + Q", hl.dsp.window.close())
hl.bind(mod .. " + SHIFT + E", hl.dsp.exit())
hl.bind(mod .. " + F", hl.dsp.window.fullscreen())
hl.bind(mod .. " + Escape", hl.dsp.exec_cmd(lock))
-- btop needs 80 columns and refuses to draw below that. A scrolling-layout column
-- (column_width 0.333) is ~835px here, which at the default font size is only 77,
-- so shrink the font for this window to buy headroom. minsize can't help: it is in
-- pixels and only applies to floating windows.
hl.bind(mod .. " + T", hl.dsp.exec_cmd(terminal .. " --class=com.btop --font-size=10 -e btop"))
hl.bind(mod .. " + M", hl.dsp.exec_cmd(terminal .. " --class=com.hyprmoncfg -e hyprmoncfg"))
hl.bind(mod .. " + C", hl.dsp.exec_cmd(scripts .. "/claude-here.sh"))
hl.bind(mod .. " + E", hl.dsp.exec_cmd(scripts .. "/nvim-here.sh"))
hl.bind(mod .. " + SHIFT + Return", hl.dsp.exec_cmd(browser))

hl.bind(mod .. " + h", hl.dsp.layout("focus l"))
hl.bind(mod .. " + l", hl.dsp.layout("focus r"))
hl.bind(mod .. " + k", hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + j", hl.dsp.focus({ direction = "down" }))

hl.bind(mod .. " + CTRL + h", hl.dsp.layout("swapcol l"))
hl.bind(mod .. " + CTRL + l", hl.dsp.layout("swapcol r"))
hl.bind(mod .. " + CTRL + k", hl.dsp.window.move({ direction = "up" }))
hl.bind(mod .. " + CTRL + j", hl.dsp.window.move({ direction = "down" }))

for i = 1, 9 do
    hl.bind(mod .. " + " .. i, hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

hl.bind("Print", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy"))
hl.bind(mod .. " + S", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy"))

-- Recording has no on-screen indicator, so notify on start and stop.
hl.bind(mod .. " + SHIFT + S", hl.dsp.exec_cmd(
    "pgrep -x wf-recorder >/dev/null && notify-send 'Already recording' && exit; " ..
    "mkdir -p ~/Videos; out=~/Videos/$(date +%Y-%m-%d-%H%M%S).mp4; " ..
    "region=$(slurp) || exit; notify-send 'Recording started' \"$out\"; " ..
    "wf-recorder -g \"$region\" -f \"$out\""))
-- wf-recorder cannot capture a toplevel directly, so feed the geometry of every
-- window on a visible workspace to slurp -r and record the box that gets picked.
hl.bind(mod .. " + SHIFT + W", hl.dsp.exec_cmd(
    "pgrep -x wf-recorder >/dev/null && notify-send 'Already recording' && exit; " ..
    "mkdir -p ~/Videos; out=~/Videos/$(date +%Y-%m-%d-%H%M%S).mp4; " ..
    "vis=$(hyprctl -j monitors | jq -r '[.[].activeWorkspace.id]|join(\",\")'); " ..
    "boxes=$(hyprctl -j clients | jq -r --arg v \"$vis\" " ..
    "'($v|split(\",\")|map(tonumber)) as $w | .[] " ..
    "| select(.mapped and (.workspace.id as $x | $w | index($x))) " ..
    "| [(.at|map(tostring)|join(\",\")),(.size|map(tostring)|join(\"x\"))]|join(\" \")'); " ..
    "region=$(printf '%s\\n' \"$boxes\" | slurp -r) || exit; " ..
    "notify-send 'Recording window' \"$out\"; " ..
    "wf-recorder -g \"$region\" -f \"$out\""))
hl.bind(mod .. " + SHIFT + R", hl.dsp.exec_cmd(
    "pkill -INT -x wf-recorder && notify-send 'Recording saved' || notify-send 'Not recording'"))

hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind(mod .. " + SHIFT + h", hl.dsp.window.resize({ x = -10, y = 0, relative = true }), { repeating = true })
hl.bind(mod .. " + SHIFT + l", hl.dsp.window.resize({ x = 10, y = 0, relative = true }), { repeating = true })
hl.bind(mod .. " + SHIFT + k", hl.dsp.window.resize({ x = 0, y = -10, relative = true }), { repeating = true })
hl.bind(mod .. " + SHIFT + j", hl.dsp.window.resize({ x = 0, y = 10, relative = true }), { repeating = true })

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"),
    { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
    { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
    { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl s 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 5%-"), { locked = true, repeating = true })

-- Quickshell
hl.bind(mod .. " + Space", hl.dsp.exec_cmd(scripts .. "/launcher.sh"))
hl.bind(mod .. " + V", hl.dsp.exec_cmd(scripts .. "/clipboard.sh"))
hl.bind(mod .. " + B", hl.dsp.exec_cmd(scripts .. "/wallpaper.sh"))
hl.bind(mod .. " + W", hl.dsp.exec_cmd(scripts .. "/wallpaper-picker.sh"))
hl.bind(mod .. " + grave", hl.dsp.exec_cmd(scripts .. "/pill-toggle.sh"))

hl.bind(mod .. " + Tab", function()
    hl.dispatch(hl.dsp.submap("hyprsphere"))
    hl.dispatch(hl.dsp.exec_cmd("qs -c hyprsphere ipc call hyprsphere toggle"))
end)

hl.define_submap("hyprsphere", function()
    hl.bind(mod .. " + Super_L", function()
        hl.dispatch(hl.dsp.exec_cmd("qs -c hyprsphere ipc call hyprsphere commit"))
        hl.dispatch(hl.dsp.submap("reset"))
    end, { release = true })
    hl.bind(mod .. " + Super_R", function()
        hl.dispatch(hl.dsp.exec_cmd("qs -c hyprsphere ipc call hyprsphere commit"))
        hl.dispatch(hl.dsp.submap("reset"))
    end, { release = true })

    hl.bind("Escape", function()
        hl.dispatch(hl.dsp.exec_cmd("qs -c hyprsphere ipc call hyprsphere cancel"))
        hl.dispatch(hl.dsp.submap("reset"))
    end)
end)
