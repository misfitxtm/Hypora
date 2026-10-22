import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import QtQuick

// Left click = activate, middle = secondary action, right = menu
Row {
    id: root
    required property var window
    spacing: 8

    // Names plugins asked to hide (see docs/plugins.md, widget.hide_tray), from plugins.json
    property var hidden: []
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hypora/plugins.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const all = JSON.parse(text())
                // reduce, not flatMap: the QML JS engine has no flatMap
                root.hidden = (Array.isArray(all) ? all : []).reduce((acc, e) => Array.isArray(e?.hide_tray) ? acc.concat(e.hide_tray) : acc, [])
                    .filter(h => typeof h === "string" && h !== "")
            } catch (e) {
                root.hidden = []
            }
        }
        onLoadFailed: root.hidden = []
    }

    Repeater {
        model: SystemTray.items

        Item {
            id: entry
            required property var modelData
            readonly property string tag: ((modelData.id ?? "") + " " + (modelData.title ?? "")).toLowerCase()
            visible: !root.hidden.some(h => entry.tag.includes(h))
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
