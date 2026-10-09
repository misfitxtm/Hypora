-- Minimal Hyprland session that hosts the SDDM greeter.
-- Installed to /usr/share/sddm/themes/hypora/hyprland.lua; SDDM starts the greeter itself.

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

-- The main display chosen in Hypora's Display Settings, if one was set. Written by
-- hypora-greeter into this directory; absent until someone picks a main display.
--
-- pcall and a plain existence check, because this is the config that draws the login
-- screen: if the generated file is ever malformed, the greeter must still come up. A
-- login screen on the wrong monitor is a nuisance; no login screen is a rescue disk.
-- pcall alone, with no io.open existence check: dofile on a missing file raises, pcall
-- catches it, and that covers both "not written yet" and "written badly" in one step
-- without assuming Hyprland's Lua exposes the io library at all.
--
-- This only moves keyboard focus. Which monitor *shows* the login panel is decided by
-- Main.qml reading `primary` from theme.conf, because SDDM instantiates the theme once
-- per screen and no amount of compositor focus changes that.
pcall(dofile, "/usr/share/sddm/themes/hypora/primary-monitor.lua")

hl.config({
    input = {
        kb_layout = "us",
    },
    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        force_default_wallpaper  = 0,
    },
    animations = {
        enabled = false,
    },
})
