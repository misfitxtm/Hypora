import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

// Icon theme picker (menu > Style > Icons). Lists every icon theme installed on the
// machine and previews a few real icons from each, so you can see what you're choosing.
//
// The choice is saved to ~/.config/hypora/icons and applied by hypora-theme. It is kept
// separate from the colour theme on purpose: switching palette shouldn't silently put
// your icons back.
// Also:  qs ipc call icons toggle
Scope {
    id: root

    readonly property string home: Quickshell.env("HOME")

    IpcHandler {
        target: "icons"
        function toggle(): void { ShellState.iconPickerOpen = !ShellState.iconPickerOpen }
    }

    LazyLoader {
        active: ShellState.iconPickerOpen

        PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "hypora-icons"
            color: "#99000000"

            property var themes: []
            property string chosen: ""

            function apply(name) {
                chosen = name
                file.setText(name + "\n")
                // Re-render the theme so GTK, Qt and the shell all pick the icons up
                Quickshell.execDetached([root.home + "/.local/bin/hypora-theme", current.text().trim() || "Nord"])
                ShellState.iconPickerOpen = false
            }

            FileView {
                id: file
                path: root.home + "/.config/hypora/icons"
                blockLoading: true
                printErrors: false
                onLoaded: win.chosen = text().trim()
            }
            FileView {
                id: current
                path: root.home + "/.config/hypora/current/name"
                blockLoading: true
                printErrors: false
            }

            // bin/hypora-icons lists each theme with a few of its own icon files.
            // Quickshell's icon provider has no "theme" parameter, so previews load the
            // files straight off disk instead of going through the icon lookup.
            Process {
                id: scan
                running: true
                command: [root.home + "/.local/bin/hypora-icons"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const out = []
                        for (const line of text.split("\n")) {
                            const f = line.split("\t")
                            if (f.length >= 3 && f[0]) out.push({ dir: f[0], label: f[1], icons: f[2].split("|") })
                        }
                        win.themes = out
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: ShellState.iconPickerOpen = false
            }

            Rectangle {
                id: panel
                anchors.centerIn: parent
                width: 620
                height: Math.min(560, header.height + grid.contentHeight + 60)
                radius: 18
                color: Theme.bg
                border.width: 1
                border.color: Theme.surface

                MouseArea { anchors.fill: parent }

                Column {
                    id: header
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 }
                    spacing: 2
                    Text {
                        text: "Icons"
                        font.family: Theme.font; font.pixelSize: Theme.fontSize + 7; font.bold: true
                        color: Theme.fg
                    }
                    Text {
                        text: "Stays put when you change colour theme. Esc to close."
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                        color: Theme.dim
                    }
                }

                GridView {
                    id: grid
                    anchors {
                        left: parent.left; right: parent.right
                        top: header.bottom; bottom: parent.bottom
                        margins: 22; topMargin: 14
                    }
                    cellWidth: 188
                    cellHeight: 92
                    clip: true
                    model: win.themes
                    focus: true
                    boundsBehavior: Flickable.StopAtBounds
                    Component.onCompleted: forceActiveFocus()
                    Keys.onEscapePressed: ShellState.iconPickerOpen = false
                    // GridView is a Flickable too, so paging works the same way.
                    Keys.onPressed: event => event.accepted = PageScroll.handle(event, grid)

                    delegate: Item {
                        id: cell
                        required property var modelData
                        readonly property bool isCurrent: modelData.dir === win.chosen
                        width: grid.cellWidth
                        height: grid.cellHeight

                        Rectangle {
                            anchors { fill: parent; margins: 5 }
                            radius: 12
                            color: cellArea.containsMouse ? Theme.surface : Qt.rgba(1, 1, 1, 0.03)
                            border.width: cell.isCurrent ? 2 : 0
                            border.color: Theme.accent

                            Row {
                                id: preview
                                anchors { left: parent.left; top: parent.top; leftMargin: 12; topMargin: 12 }
                                spacing: 6
                                Repeater {
                                    model: cell.modelData.icons
                                    Image {
                                        required property string modelData
                                        width: 24; height: 24
                                        sourceSize: Qt.size(24, 24)
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        source: "file://" + modelData
                                    }
                                }
                            }
                            Text {
                                anchors { left: parent.left; right: parent.right; top: preview.bottom; leftMargin: 12; rightMargin: 12; topMargin: 10 }
                                elide: Text.ElideRight
                                text: cell.modelData.label
                                font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                                font.bold: cell.isCurrent
                                color: cell.isCurrent ? Theme.accent : Theme.fg
                            }
                            MouseArea {
                                id: cellArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.apply(cell.modelData.dir)
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: grid.count === 0
                        text: "Looking for installed icon themes…"
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                        color: Theme.dim
                    }
                }
            }
        }
    }
}
