-- Minimal Hyprland session used ONLY to host the Quickshell greeter.
-- Installed to /etc/greetd/hyprland.lua (not your desktop config).

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

-- Run the greeter; when it quits (after login or on failure), shut this session down.
hl.on("hyprland.start", function()
    hl.exec_cmd("qs -p /etc/greetd/quickshell/shell.qml; hyprctl dispatch 'hl.dsp.exit()'")
end)

hl.config({
    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        force_default_wallpaper  = 0,
    },
    animations = {
        enabled = false,
    },
    input = {
        kb_layout = "us",
    },
})
