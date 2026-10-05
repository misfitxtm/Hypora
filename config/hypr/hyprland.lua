-- hyprland.lua  (Hyprland 0.55+ Lua config)
-- Based on the upstream example config, adapted for Hypora:
--   * Quickshell provides the bar, notifications and polkit prompt
--   * Border colors come from the active theme (theme.lua, written by hypora-theme)
-- Docs: https://wiki.hypr.land/Configuring/Start/
-- After editing:  hyprctl reload && hyprctl configerrors

------------------ PROGRAMS ------------------
local terminal = "kitty"
local browser  = "firefox"
local mainMod  = "SUPER"

-- Run through uwsm when the session is uwsm-managed (the login screen picks that
-- session), but still work when Hyprland was started directly from a TTY.
local function app(cmd)
    return "if uwsm check is-active >/dev/null 2>&1; then exec uwsm app -- " .. cmd .. "; else exec " .. cmd .. "; fi"
end
local logout = "uwsm check is-active >/dev/null 2>&1 && uwsm stop || hyprctl dispatch 'hl.dsp.exit()'"

------------------ MONITORS ------------------
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

-- Optional files next to this one in ~/.config/hypr/. dofile (not require) so that
-- `hyprctl reload` picks up changes.
local function load(name)
    local path = package.searchpath(name, package.path)
    if path then dofile(path) end
end

-- Monitor layout saved by Display Settings (~/.config/hypr/monitors.lua)
load("monitors")

------------------ ENVIRONMENT ---------------
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")   -- Qt apps follow the theme (also set in ~/.config/uwsm/env)

------------------ AUTOSTART -----------------
-- Quickshell replaces waybar + mako + a standalone polkit agent.
-- Don't start any of those alongside it.
hl.on("hyprland.start", function()
    hl.exec_cmd(app("qs"))
end)

------------------ LOOK AND FEEL -------------
hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 10,
        border_size = 2,

        resize_on_border = false,
        allow_tearing    = false,
        layout           = "dwindle",
    },

    decoration = {
        rounding       = 8,
        rounding_power = 2,

        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },

        blur = {
            enabled  = true,
            size     = 3,
            passes   = 1,
            vibrancy = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
    },

    misc = {
        force_default_wallpaper = 0,    -- no mascot wallpapers
        disable_hyprland_logo   = true,
    },
})

-- Border colors from the active theme (~/.config/hypr/theme.lua, written by hypora-theme)
load("theme")

------------------ INPUT ---------------------
hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        follow_mouse = 1,
        sensitivity  = 0,

        touchpad = {
            natural_scroll = false,
        },
    },
})

------------------ KEYBINDINGS ---------------
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(app(browser)))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("qs ipc call launcher toggle"))       -- app launcher (Launcher.qml)
hl.bind(mainMod .. " + ALT + T", hl.dsp.exec_cmd("qs ipc call themes toggle"))   -- theme picker (ThemePicker.qml)
hl.bind(mainMod .. " + Q", hl.dsp.window.close())                                -- close the focused window
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))      -- dwindle only
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("hyprlock"))
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd(logout))          -- log out

-- Move focus
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Workspaces: SUPER + [0-9] to switch, SUPER + SHIFT + [0-9] to move window
for i = 1, 10 do
    local key = i % 10      -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,           hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key,   hl.dsp.window.move({ workspace = i }))
end

-- Scroll through workspaces
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move / resize windows with the mouse
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Volume and brightness keys (PipeWire via wpctl; needs brightnessctl)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl set 5%+"),                          { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl set 5%-"),                          { locked = true, repeating = true })

-- Media keys (needs playerctl)
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

------------------ WINDOW RULES --------------
hl.window_rule({
    -- Hypora's Display Settings window
    name  = "hypora-display-settings",
    match = { title = "^Display Settings$" },
    float  = true,
    center = true,
})

hl.window_rule({
    -- Ignore maximize requests from apps
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})
