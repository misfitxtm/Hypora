//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma IconTheme Papirus-Dark
import Quickshell
import Quickshell.Io

ShellRoot {
    // `qs ipc call shell reload`: hypora-theme uses this after switching themes
    IpcHandler {
        target: "shell"
        function reload(): void { Quickshell.reload(true) }
    }

    Wallpaper {}
    Bar {}
    PolkitDialog {}
    Notifications {}
    Launcher {}
    DisplaySettings {}
    ThemePicker {}
}
