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

        // Left: app menu, workspaces 1-9
        Row {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 8 }
            spacing: 4

            AppMenu { window: bar; anchors.verticalCenter: parent.verticalCenter }
            Item { width: 4; height: 1 }

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

        // Center: clipboard history, weather, then the clock (click for the calendar)
        Row {
            anchors.centerIn: parent
            spacing: 6

            Clipboard { window: bar; anchors.verticalCenter: parent.verticalCenter }
            Weather { window: bar; anchors.verticalCenter: parent.verticalCenter }
            Clock { window: bar; anchors.verticalCenter: parent.verticalCenter }
        }

        // Right: tray, then the status icons that open the control center
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 6 }
            spacing: 10

            Tray { window: bar; anchors.verticalCenter: parent.verticalCenter }
            SystemUsage { window: bar; anchors.verticalCenter: parent.verticalCenter }
            ControlCenter { window: bar; anchors.verticalCenter: parent.verticalCenter }
        }
    }
}
