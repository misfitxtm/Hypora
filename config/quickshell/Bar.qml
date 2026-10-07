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

        // Left: app menu, then this monitor's own workspaces.
        //
        // Each monitor owns a block of WS_STRIDE workspace numbers (see hyprland.lua):
        // monitor 0 has 1-10, monitor 1 has 11-20. The bar shows the block belonging to the
        // screen it is on and labels them 1-5, so every monitor reads as having its own set.
        readonly property int wsStatic: 5
        readonly property int wsStride: 10
        readonly property var hlMonitor: Hyprland.monitorFor(bar.screen)
        readonly property int wsBase: (hlMonitor?.id ?? 0) * wsStride

        // The five that are always there, plus any on-demand one currently in use here
        readonly property var workspaceIds: {
            const out = []
            for (let i = 1; i <= wsStatic; i++) out.push(wsBase + i)
            for (const w of Hyprland.workspaces.values)
                if (w.id > wsBase + wsStatic && w.id <= wsBase + wsStride) out.push(w.id)
            return out.sort((a, b) => a - b)
        }

        Row {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 8 }
            spacing: 4

            AppMenu { window: bar; anchors.verticalCenter: parent.verticalCenter }
            Item { width: 4; height: 1 }

            Repeater {
                model: bar.workspaceIds
                Rectangle {
                    id: ws
                    required property var modelData
                    readonly property int wsId: modelData
                    // This monitor's own active workspace, not whichever screen has focus
                    readonly property bool focused: bar.hlMonitor?.activeWorkspace?.id === wsId
                    readonly property bool occupied: Hyprland.workspaces.values.some(w => w.id === wsId)

                    width: 22; height: 20; radius: 4
                    color: focused ? Theme.accent : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: ws.wsId - bar.wsBase      // shown as 1-10, whichever monitor
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

        // Center: clipboard history, the clock (click for the calendar), then weather
        Row {
            anchors.centerIn: parent
            spacing: 6

            Clipboard { window: bar; anchors.verticalCenter: parent.verticalCenter }
            Clock { window: bar; anchors.verticalCenter: parent.verticalCenter }
            Weather { window: bar; anchors.verticalCenter: parent.verticalCenter }
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
