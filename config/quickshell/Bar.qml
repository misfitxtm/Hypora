import Quickshell
import Quickshell.Hyprland
import QtQuick

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: bar
        required property var modelData
        screen: modelData

        anchors { top: true; left: true; right: true }
        implicitHeight: 30
        color: Theme.bg

        SystemClock { id: clock; precision: SystemClock.Minutes }

        // Left: workspaces 1-9
        Row {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 8 }
            spacing: 4

            ControlCenter { window: bar }

            Repeater {
                model: 9
                Rectangle {
                    id: ws
                    required property int index
                    readonly property int wsId: index + 1
                    readonly property bool focused: Hyprland.focusedWorkspace?.id === wsId
                    readonly property bool occupied: Hyprland.workspaces.values.some(w => w.id === wsId)

                    width: 22; height: 20; radius: 4
                    color: focused ? Theme.accent : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: ws.wsId
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        color: ws.focused ? Theme.bg : (ws.occupied ? Theme.fg : Theme.dim)
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: Hyprland.dispatch(`hl.dsp.focus({ workspace = "${ws.wsId}" })`)
                    }
                }
            }
        }

        // Center: clock
        Text {
            anchors.centerIn: parent
            text: Qt.formatDateTime(clock.date, "ddd MMM d   HH:mm")
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            color: Theme.fg
        }

        // Right: tray, network, volume, battery
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 12 }
            spacing: 14

            Tray { window: bar; anchors.verticalCenter: parent.verticalCenter }
            Network { anchors.verticalCenter: parent.verticalCenter }
            Volume { anchors.verticalCenter: parent.verticalCenter }
            Battery { anchors.verticalCenter: parent.verticalCenter }
        }
    }
}
