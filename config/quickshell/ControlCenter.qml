import Quickshell
import QtQuick

// Status icons on the right of the bar. Clicking them opens the control center;
// clicking anywhere else (or Escape) closes it.
Rectangle {
    id: root
    required property var window

    implicitWidth: icons.implicitWidth + 20
    implicitHeight: 24
    radius: height / 2
    color: drop.open ? Theme.surface : (area.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: drop.open = true
    }

    Row {
        id: icons
        anchors.centerIn: parent
        spacing: 12

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: ShellState.dnd
            name: "bell-off"
            size: 15
        }
        Network { anchors.verticalCenter: parent.verticalCenter }
        Volume { anchors.verticalCenter: parent.verticalCenter }
        Battery { anchors.verticalCenter: parent.verticalCenter }
    }

    Dropdown {
        id: drop
        screen: root.window.screen
        barHeight: root.window.height
        alignRight: true

        ControlPanel { onCloseRequested: drop.open = false }
    }
}
