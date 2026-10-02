import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import QtQuick

// Left click = activate, middle = secondary action, right = menu
Row {
    id: root
    required property var window
    spacing: 8

    Repeater {
        model: SystemTray.items

        Item {
            id: entry
            required property var modelData
            width: 18
            height: 18

            IconImage {
                anchors.fill: parent
                source: entry.modelData.icon
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onClicked: m => {
                    if (m.button === Qt.LeftButton) {
                        entry.modelData.activate()
                    } else if (m.button === Qt.MiddleButton) {
                        entry.modelData.secondaryActivate()
                    } else if (entry.modelData.hasMenu) {
                        const p = entry.mapToItem(root.window.contentItem, 0, entry.height)
                        entry.modelData.display(root.window, p.x, p.y)
                    }
                }
            }
        }
    }
}
