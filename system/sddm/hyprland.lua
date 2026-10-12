-- Minimal Hyprland session that hosts the SDDM greeter.
-- Installed to /usr/share/sddm/themes/hypora/hyprland.lua; SDDM starts the greeter itself.

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

-- The main display chosen in Display Settings, if any. hypora-greeter writes it into this
-- directory; it does not exist until a main display is picked.
--
-- pcall around dofile: a missing file (not written yet) or a broken one (written badly)
-- must not stop the greeter. A login screen on the wrong monitor is a nuisance; no login
-- screen is a rescue disk. This also avoids assuming Hyprland's Lua has the io library.
--
-- This only moves keyboard focus. Which monitor shows the login panel is decided by
-- Main.qml reading `primary` from theme.conf, because SDDM creates the theme once per
-- screen.
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
