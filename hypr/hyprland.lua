-- Startup
hl.on("hyprland.start", function()
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_DATA_DIRS")
    hl.exec_cmd("systemctl --user restart xdg-desktop-portal")
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("wl-paste --watch cliphist store")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
end)

-- Lid switch
hl.bind("switch:on:Lid Switch",  hl.dsp.exec_cmd("hyprctl keyword monitor \"eDP-1, disable\""),              { locked = true })
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("hyprctl keyword monitor \"eDP-1, preferred, auto, 2\""),   { locked = true })

-- Config
hl.config({
    general = {
        gaps_in     = 4,
        gaps_out    = 8,
        border_size = 2,
        col = {
            active_border   = { colors = { "rgba(bd93f9ee)", "rgba(ff79c6ee)" }, angle = 45 },
            inactive_border = "rgba(44475aaa)",
        },
        layout = "dwindle",
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
        touchpad = {
            natural_scroll = true,
        },
    },
})

-- Animations
hl.curve("snap", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.0 } } })

hl.animation({ leaf = "windows",     enabled = true, speed = 2, bezier = "snap" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 2, bezier = "snap", style = "popin 80%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 2, bezier = "snap" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 2, bezier = "snap" })
hl.animation({ leaf = "fade",        enabled = true, speed = 2, bezier = "default" })
hl.animation({ leaf = "border",      enabled = true, speed = 8, bezier = "default" })

-- Keybinds
hl.bind(mod .. " + Return",         hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + Q",              hl.dsp.window.close())
hl.bind(mod .. " + SHIFT + E",      hl.dsp.exit())
hl.bind(mod .. " + Space",          hl.dsp.exec_cmd("noctalia-shell ipc call launcher toggle"))
hl.bind(mod .. " + V",              hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + F",              hl.dsp.window.fullscreen())
hl.bind(mod .. " + Escape",         hl.dsp.exec_cmd(lock))
hl.bind(mod .. " + SHIFT + V",      hl.dsp.exec_cmd("noctalia-shell ipc call launcher clipboard"))

hl.bind(mod .. " + h", hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + l", hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. " + k", hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + j", hl.dsp.focus({ direction = "down" }))

hl.bind(mod .. " + CTRL + h", hl.dsp.window.move({ direction = "left" }))
hl.bind(mod .. " + CTRL + l", hl.dsp.window.move({ direction = "right" }))
hl.bind(mod .. " + CTRL + k", hl.dsp.window.move({ direction = "up" }))
hl.bind(mod .. " + CTRL + j", hl.dsp.window.move({ direction = "down" }))

for i = 1, 9 do
    hl.bind(mod .. " + " .. i,         hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

hl.bind("Print", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy"))

hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind(mod .. " + SHIFT + h", hl.dsp.window.resize({ x = -30, y = 0,   relative = true }), { repeating = true })
hl.bind(mod .. " + SHIFT + l", hl.dsp.window.resize({ x = 30,  y = 0,   relative = true }), { repeating = true })
hl.bind(mod .. " + SHIFT + k", hl.dsp.window.resize({ x = 0,   y = -30, relative = true }), { repeating = true })
hl.bind(mod .. " + SHIFT + j", hl.dsp.window.resize({ x = 0,   y = 30,  relative = true }), { repeating = true })

hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"),  { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),  { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl s 5%+"),                        { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 5%-"),                        { locked = true, repeating = true })
