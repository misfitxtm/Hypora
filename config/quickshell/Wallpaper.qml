import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import Qt.labs.folderlistmodel

// Desktop wallpaper, drawn by the shell on the background layer of every monitor.
// The images are the current theme's (~/.config/hypora/current/backgrounds/); the chosen
// one is remembered in ~/.config/hypora/current/wallpaper.
// Cycle with the menu's Settings > Next wallpaper, or:  qs ipc call wallpaper next
Scope {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.config/hypora/current"
    readonly property string chosen: saved.text().trim()
    readonly property var files: {
        const out = []
        for (let i = 0; i < folder.count; i++) out.push(folder.get(i, "fileName"))
        return out
    }
    // The saved choice if it still exists, otherwise the theme's first wallpaper
    readonly property string current: files.includes(chosen) ? chosen : (files[0] ?? "")
    readonly property url source: current ? `file://${dir}/backgrounds/${current}` : ""

    function next() {
        if (files.length === 0) return
        saved.setText(files[(files.indexOf(current) + 1) % files.length] + "\n")
    }

    Component.onCompleted: ShellState.nextWallpaper = () => root.next()

    IpcHandler {
        target: "wallpaper"
        function next(): void { root.next() }
    }

    FolderListModel {
        id: folder
        folder: `file://${root.dir}/backgrounds`
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
        showDirs: false
        sortField: FolderListModel.Name
    }

    FileView {
        id: saved
        path: root.dir + "/wallpaper"
        watchChanges: true
        onFileChanged: reload()
        printErrors: false
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "hypora-wallpaper"
            color: Theme.bg

            // Cross-fade: the old image stays underneath while the new one fades in
            Image {
                id: under
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(win.width, win.height)
                asynchronous: true
            }
            Image {
                id: top
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(win.width, win.height)
                asynchronous: true
                Component.onCompleted: source = root.source
                onStatusChanged: if (status === Image.Ready) fade.restart()
            }
            NumberAnimation { id: fade; target: top; property: "opacity"; from: 0; to: 1; duration: 600 }

            Connections {
                target: root
                function onSourceChanged() {
                    under.source = top.source
                    top.opacity = 0
                    top.source = root.source
                }
            }
        }
    }
}
