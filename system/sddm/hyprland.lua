-- Minimal Hyprland session that hosts the SDDM greeter.
-- Installed to /usr/share/sddm/themes/hypora/hyprland.lua; SDDM starts the greeter itself.

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

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
