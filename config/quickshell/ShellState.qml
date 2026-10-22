pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Small bits of state shared between shell components.
Singleton {
    id: state

    // The main display (HYPORA_PRIMARY in monitors.lua) read in one place; falls back to screens[0] when unset or unplugged.
    property string primaryName: ""
    readonly property var primaryScreen:
        Quickshell.screens.find(s => s.name === primaryName) ?? Quickshell.screens[0] ?? null

    function isPrimary(screen) { return screen === primaryScreen }

    FileView {
        path: Quickshell.env("HOME") + "/.config/hypr/monitors.lua"
        watchChanges: true
        printErrors: false
        // Read synchronously: this singleton is created on first use, and an async load would fall back to screens[0].
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
