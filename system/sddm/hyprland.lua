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
do
    local extra = "/usr/share/sddm/themes/hypora/primary-monitor.lua"
    local f = io.open(extra, "r")
    if f then
        f:close()
        pcall(dofile, extra)
    end
end

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
