pragma Singleton
import Quickshell
import QtQuick

// Small bits of state shared between shell components.
Singleton {
    // Do Not Disturb: hides notification popups (critical ones still show)
    property bool dnd: false

    // Display Settings window (DisplaySettings.qml)
    property bool displaySettingsOpen: false
}
