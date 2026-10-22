-- Minimal Hyprland session hosting the SDDM greeter, installed to the theme directory.

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

-- Focus the main display if set; pcall dofile because a missing or broken file must not stop the greeter.
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
