pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Small bits of state shared between shell components.
Singleton {
    id: state

    // The main display, chosen in Display Settings and stored in ~/.config/hypr/monitors.lua
    // as HYPORA_PRIMARY. Read here rather than in each component so there is one reader.
    //
    // Why this exists: the single-instance panels (app menu, clipboard history) have to pick
    // one screen to live on, and `Quickshell.screens[0]` is enumeration order — which is the
    // laptop panel on a docked machine as often as not, and changes when a cable moves. A
    // name the user picked is stable across both.
    //
    // Falls back to screens[0] when nothing is set or the saved output isn't connected, so a
    // monitor named here and then unplugged doesn't leave the menu with nowhere to open.
    property string primaryName: ""
    readonly property var primaryScreen:
        Quickshell.screens.find(s => s.name === primaryName) ?? Quickshell.screens[0] ?? null

    function isPrimary(screen) { return screen === primaryScreen }

    FileView {
        path: Quickshell.env("HOME") + "/.config/hypr/monitors.lua"
        watchChanges: true
        printErrors: false
        // Read synchronously, for the same reason SysInfo does: this singleton is created on
        // first use, and an async load would let the first binding of primaryScreen fall back
        // to screens[0] before the saved name arrives.
        blockLoading: true
        onFileChanged: reload()
        onLoaded: {
            const m = /^HYPORA_PRIMARY\s*=\s*"([^"]*)"/m.exec(text())
            state.primaryName = m ? m[1] : ""
        }
        onLoadFailed: state.primaryName = ""
    }
    // Do Not Disturb: hides notification popups (critical ones still show)
    property bool dnd: false

    // Display Settings window (DisplaySettings.qml)
    property bool displaySettingsOpen: false

    // Icon theme picker (IconPicker.qml)
    property bool iconPickerOpen: false

    // Security window (SecuritySettings.qml)
    property bool securitySettingsOpen: false

    // Keyboard shortcuts window (KeybindHelp.qml)
    property bool keybindHelpOpen: false

    // Default apps window (DefaultApps.qml)
    property bool defaultAppsOpen: false

    // Sound window (AudioSettings.qml)
    property bool audioSettingsOpen: false

    // Network and Bluetooth windows
    property bool networkSettingsOpen: false
    property bool bluetoothSettingsOpen: false

    // Theme picker (ThemePicker.qml)
    property bool themePickerOpen: false

    // Set by Wallpaper.qml; lets the menu cycle wallpapers
    property var nextWallpaper: () => {}
}
