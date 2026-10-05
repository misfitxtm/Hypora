import Quickshell
import Quickshell.Io
import QtQuick

// Hypora logo at the left of the bar; opens the app menu.
// Also: qs ipc call menu toggle
Rectangle {
    id: root
    required property var window

    implicitWidth: 30
    implicitHeight: 24
    radius: height / 2
    color: drop.open ? Theme.surface : (area.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")

    Logo {
        anchors.centerIn: parent
        size: 18
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: drop.open = true
    }

    // One menu per bar; IPC toggles the one on the first screen
    IpcHandler {
        enabled: root.window.screen === Quickshell.screens[0]
        target: "menu"
        function toggle(): void { drop.open = !drop.open }
    }

    Dropdown {
        id: drop
        screen: root.window.screen
        barHeight: root.window.height
        onVisibleChanged: if (visible) panel.reset()

        AppMenuPanel {
            id: panel
            onCloseRequested: drop.open = false
        }
    }
}
