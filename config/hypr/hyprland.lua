-- hyprland.lua (Hyprland 0.55+ Lua config) adapted from upstream; reload with hyprctl reload && hyprctl configerrors.

------------------ PROGRAMS ------------------
local terminal    = "kitty"
-- Firefox is a flatpak, so use `flatpak run` rather than a desktop id (works without uwsm too).
local browser     = "flatpak run org.mozilla.firefox"
local fileManager = "nautilus"
local mainMod  = "SUPER"

-- Run through uwsm when it manages the session, but still work when started from a TTY.
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

-- dofile, not require, so `hyprctl reload` picks up changes to these optional files.
local function load(name)
    local path = package.searchpath(name, package.path)
    if path then dofile(path) end
end

-- Monitor layout saved by Display Settings (~/.config/hypr/monitors.lua)
load("monitors")

------------------ ENVIRONMENT ---------------
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct:qt5ct")   -- Qt apps follow the theme (also set in ~/.config/uwsm/env)

-- AUTOSTART: declared here and defined in WORKSPACES, since a Lua closure only sees locals that already exist.
local workspace_rules

-- Quickshell replaces waybar, mako and a separate polkit agent. Do not start those too.
hl.on("hyprland.start", function()
    hl.exec_cmd(app("qs"))
    -- Quickshell cannot watch the clipboard, so wl-paste records into cliphist for the bar widget.
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    -- Idle locking (~/.config/hypr/hypridle.conf). Without this nothing ever locks.
    hl.exec_cmd(app("hypridle"))
    -- Start the keyring (GNOME's session does it, Hyprland does not) so apps do not store tokens in the clear.
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets,ssh")
    -- The monitors exist by now, which they don't when the config is first read
    workspace_rules()
    -- Start on the main display (HYPORA_PRIMARY from monitors.lua; nil keeps focus); hyprctl keeps Lua errors off login.
    if HYPORA_PRIMARY then
        -- hl.dispatch takes a hl.dsp.* descriptor, never a string; it stays behind hyprctl until confirmed on hardware.
        hl.exec_cmd("hyprctl dispatch 'hl.dsp.focus({ monitor = \"" .. HYPORA_PRIMARY
                    .. "\" })' 2>&1 | logger -t hypora-session")
    end
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

-- KEYBINDINGS: one table so each action can be rebound; keep names in step with KeybindHelp.qml.
local keys = {
    terminal    = mainMod .. " + Return",
    browser     = mainMod .. " + B",
    files       = mainMod .. " + E",
    launcher    = mainMod .. " + R",
    menu        = mainMod .. " + A",
    themePicker = mainMod .. " + ALT + T",
    clipboard   = mainMod .. " + SHIFT + V",
    screenshot  = mainMod .. " + SHIFT + S",
    closeWindow = mainMod .. " + Q",
    toggleFloat = mainMod .. " + V",
    pseudo      = mainMod .. " + P",
    toggleSplit = mainMod .. " + J",
    fullscreen  = mainMod .. " + F",
    scratchpad  = mainMod .. " + S",
    -- Hyprland's SUPER + SHIFT + S default is the screenshot here, so the scratchpad move is bound elsewhere.
    moveToScratchpad = mainMod .. " + ALT + S",
    lock        = mainMod .. " + L",
    logout      = mainMod .. " + M",
    focusLeft   = mainMod .. " + left",
    focusRight  = mainMod .. " + right",
    focusUp     = mainMod .. " + up",
    focusDown   = mainMod .. " + down",
    monitorLeft  = mainMod .. " + SHIFT + left",
    monitorRight = mainMod .. " + SHIFT + right",
    -- For stacked screens; SUPER + up/down move focus and SUPER + SHIFT + [0-9] moves to a workspace.
    monitorUp    = mainMod .. " + SHIFT + up",
    monitorDown  = mainMod .. " + SHIFT + down",
}

do
    local path = package.searchpath("keybinds", package.path)
    if path then
        local ok, saved = pcall(dofile, path)
        if ok and type(saved) == "table" then
            for action, key in pairs(saved) do
                if type(key) == "string" and key ~= "" then keys[action] = key end
            end
        end
    end
end

hl.bind(keys.terminal,    hl.dsp.exec_cmd(terminal))
hl.bind(keys.browser,     hl.dsp.exec_cmd(app(browser)))
hl.bind(keys.files,       hl.dsp.exec_cmd(app(fileManager)))
hl.bind(keys.launcher,    hl.dsp.exec_cmd("qs ipc call launcher toggle"))   -- Launcher.qml
hl.bind(keys.menu,        hl.dsp.exec_cmd("qs ipc call menu toggle"))       -- AppMenu.qml
hl.bind(keys.themePicker, hl.dsp.exec_cmd("qs ipc call themes toggle"))     -- ThemePicker.qml
hl.bind(keys.closeWindow, hl.dsp.window.close())
hl.bind(keys.toggleFloat, hl.dsp.window.float({ action = "toggle" }))
hl.bind(keys.pseudo,      hl.dsp.window.pseudo())
hl.bind(keys.toggleSplit, hl.dsp.layout("togglesplit"))                     -- dwindle only
hl.bind(keys.clipboard,   hl.dsp.exec_cmd("qs ipc call clipboard toggle"))    -- Clipboard.qml
hl.bind(keys.screenshot,  hl.dsp.exec_cmd("hypora-screenshot region"))
hl.bind(keys.fullscreen,  hl.dsp.window.fullscreen())
hl.bind(keys.lock,        hl.dsp.exec_cmd("hyprlock"))
hl.bind(keys.logout,      hl.dsp.exec_cmd(logout))

-- Scratchpad (Hyprland's "magic" special workspace)
hl.bind(keys.scratchpad,       hl.dsp.workspace.toggle_special("magic"))
hl.bind(keys.moveToScratchpad, hl.dsp.window.move({ workspace = "special:magic" }))

-- Move focus
hl.bind(keys.focusLeft,  hl.dsp.focus({ direction = "left" }))
hl.bind(keys.focusRight, hl.dsp.focus({ direction = "right" }))
hl.bind(keys.focusUp,    hl.dsp.focus({ direction = "up" }))
hl.bind(keys.focusDown,  hl.dsp.focus({ direction = "down" }))

-- Move the window to the next monitor, guarded because Hyprland errors when there is no screen that way.
local MONITOR_AXIS = {
    l = { "x", -1 }, r = { "x", 1 },
    u = { "y", -1 }, d = { "y", 1 },
}

local function monitor_toward(dir)
    local here = hl.get_active_monitor()
    local all = hl.get_monitors() or {}
    local axis = MONITOR_AXIS[dir]
    if not here or not axis then return #all > 1 end
    local field, sign = axis[1], axis[2]
    if here[field] == nil then return #all > 1 end
    for _, m in ipairs(all) do
        if m.id ~= here.id and m[field] ~= nil
           and (m[field] - here[field]) * sign > 0 then
            return true
        end
    end
    return false
end

local function throw_to_monitor(dir)
    return function()
        if not monitor_toward(dir) then return end
        hl.dispatch(hl.dsp.window.move({ monitor = dir }))
    end
end

hl.bind(keys.monitorLeft,  throw_to_monitor("l"))
hl.bind(keys.monitorRight, throw_to_monitor("r"))
hl.bind(keys.monitorUp,    throw_to_monitor("u"))
hl.bind(keys.monitorDown,  throw_to_monitor("d"))

-- Per-monitor workspaces are blocks of WS_STRIDE numbers, so these binds are functions that read the focus at keypress.
local WS_STATIC = 5      -- always-there workspaces per monitor
local WS_STRIDE = 10     -- numbers reserved per monitor; keys 1-9,0 address them

function workspace_rules()      -- assigns the local forward-declared near AUTOSTART
    for _, m in ipairs(hl.get_monitors()) do
        for i = 1, WS_STRIDE do
            hl.workspace_rule({
                workspace  = tostring(m.id * WS_STRIDE + i),
                monitor    = m.name,
                -- Pin every number in the block, so even the on-demand ones stay put
                persistent = i <= WS_STATIC or nil,
                default    = (i == 1) or nil,
            })
        end
    end
end

-- hl.get_monitors() is empty this early, so the real call is in the start hook; this one covers a reload.
workspace_rules()
-- Run again on plug-in; pcall because a wrong event name would stop everything defined after it.
pcall(hl.on, "monitor.added", workspace_rules)

-- Which block the keys address: whichever monitor has the focus right now
local function ws(n)
    local m = hl.get_active_monitor()
    return tostring((m and m.id or 0) * WS_STRIDE + n)
end

for i = 1, 10 do
    local key = i % 10      -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key, function()
        hl.dispatch(hl.dsp.focus({ workspace = ws(i) }))
    end)
    hl.bind(mainMod .. " + SHIFT + " .. key, function()
        hl.dispatch(hl.dsp.window.move({ workspace = ws(i) }))
    end)
end

-- "m" scrolls only this monitor's workspaces, so it cannot reach the other screen's block.
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "m+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "m-1" }))

-- Move / resize windows with the mouse
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Volume and brightness keys (PipeWire via wpctl; needs brightnessctl)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true })
-- Tell the slider about brightness changes via qs ipc, since sysfs does not reliably send events.
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl set 5%+ && qs ipc call osd brightness"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl set 5%- && qs ipc call osd brightness"), { locked = true, repeating = true })

-- Media keys (needs playerctl)
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

------------------ WINDOW RULES --------------
hl.window_rule({
    -- Hypora's Display Settings window
    name  = "hypora-settings-windows",
    match = { title = "^(Display Settings|Network|Bluetooth)$" },
    float  = true,
    center = true,
})

-- Small utility windows that float better than tile; add an app ID here (`hyprctl clients` shows the class).
local floatingApps = {
    "org.gnome.Calculator",
}

local function class_regex(list)
    local parts = {}
    for _, c in ipairs(list) do
        -- A dot is "any character" to the matcher, so pin it to a literal one
        parts[#parts + 1] = c:gsub("%.", "\\.")
    end
    return "^(" .. table.concat(parts, "|") .. ")$"
end

hl.window_rule({
    name   = "hypora-float-utilities",
    match  = { class = class_regex(floatingApps) },
    float  = true,
    center = true,
})

hl.window_rule({
    -- Firmware updater floats and is pinned so it stays visible while writing; no size because 0.56.2 ignores it (#16446).
    name   = "hypora-firmware-updater",
    match  = { title = "^Firmware Update$" },
    float  = true,
    pin    = true,
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
