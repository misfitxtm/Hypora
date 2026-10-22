import Quickshell
import Quickshell.Io
import QtQuick

// Bar items from plugins (docs/plugins.md) for this slot, main display only; a failing plugin loses only its own item.
Row {
    id: root
    required property var window
    property string slot: "right"
    property var entries: []

    spacing: 10

    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hypora/plugins.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const all = JSON.parse(text())
                // Only well-formed entries for this slot; component names become file names, so they are checked again here.
                root.entries = (Array.isArray(all) ? all : []).filter(e =>
                    e && e.slot === root.slot && /^[A-Z][A-Za-z0-9_]*$/.test(e.component || ""))
            } catch (e) {
                root.entries = []
            }
        }
        onLoadFailed: root.entries = []
    }

    Repeater {
        model: root.entries
        Loader {
            id: item
            required property var modelData
            anchors.verticalCenter: parent.verticalCenter
            // Plugin items live on the main display only; other bars never load them.
            active: ShellState.isPrimary(root.window.screen)
            // Collapse with the item, not the Loader: a hidden parent makes the item report visible=false for good.
            width: item.item?.visible ? item.item.implicitWidth : 0
            height: item.item?.visible ? item.item.implicitHeight : 0
            Component.onCompleted: setSource(modelData.component + ".qml", { window: root.window })
        }
    }
}
