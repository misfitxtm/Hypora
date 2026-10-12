import Quickshell
import Quickshell.Io
import QtQuick

// Bar items added by plugins (see docs/plugins.md). One of these sits in each part of the bar.
//
// `hypora-plugin` keeps ~/.config/hypora/plugins.json, a list of {id, component, slot}.
// This loads the entries whose slot matches. The file is watched, so enabling or removing
// a plugin shows up without restarting the shell. A plugin that fails to load only loses
// its own item: the Loader logs the error and the rest of the bar carries on.
//
// A plugin's component is a bar item like Clock.qml: it takes `window` (the bar's window)
// and hides itself by setting its own `visible` to false.
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
                // Only well-formed entries for this slot. Names are checked again here because they become
                // file names: a component name is a QML type name and nothing more.
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
            // Collapse with the item, so a hidden plugin leaves no gap in the bar. Not by hiding the
            // Loader: a hidden parent makes the item report visible=false, so it could never come back.
            width: item.item?.visible ? item.item.implicitWidth : 0
            height: item.item?.visible ? item.item.implicitHeight : 0
            Component.onCompleted: setSource(modelData.component + ".qml", { window: root.window })
        }
    }
}
