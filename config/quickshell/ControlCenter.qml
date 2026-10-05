import Quickshell
import Quickshell.Hyprland
import QtQuick

// Status icons on the right of the bar. Clicking them opens the control center.
Rectangle {
    id: root
    required property var window

    implicitWidth: icons.implicitWidth + 20
    implicitHeight: 24
    radius: height / 2
    color: popup.visible ? Theme.surface : (area.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: popup.visible = !popup.visible
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

    // Close when clicking anywhere else
    HyprlandFocusGrab {
        windows: [popup]
        active: popup.visible
        onCleared: popup.visible = false
    }

    PopupWindow {
        id: popup
        visible: false
        anchor.window: root.window
        anchor.rect.x: root.window.width - implicitWidth - 8
        anchor.rect.y: root.window.height + 6
        implicitWidth: panel.implicitWidth
        implicitHeight: panel.implicitHeight
        color: "transparent"

        ControlPanel {
            id: panel
            anchors.fill: parent
            onCloseRequested: popup.visible = false
        }
    }
}
