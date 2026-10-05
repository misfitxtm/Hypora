pragma Singleton
import Quickshell
import QtQuick

// Small bits of state shared between shell components.
Singleton {
    // Do Not Disturb: hides notification popups (critical ones still show)
    property bool dnd: false

    // Display Settings window (DisplaySettings.qml)
    property bool displaySettingsOpen: false

    // Network and Bluetooth windows
    property bool networkSettingsOpen: false
    property bool bluetoothSettingsOpen: false

    // Theme picker (ThemePicker.qml)
    property bool themePickerOpen: false

    // Set by Wallpaper.qml; lets the menu cycle wallpapers
    property var nextWallpaper: () => {}
}
