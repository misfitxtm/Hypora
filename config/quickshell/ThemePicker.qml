import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import Qt.labs.folderlistmodel

// Theme picker (SUPER + ALT + T, or menu > Settings > Theme). Each card previews a theme
// with its first wallpaper, a miniature desktop in its colors and its palette.
// Arrows to choose, Enter or click to apply (runs hypora-theme), Esc to close.
// Also:  qs ipc call themes toggle
Scope {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string themesDir: home + "/.config/hypora/themes"

    IpcHandler {
        target: "themes"
        function toggle(): void { ShellState.themePickerOpen = !ShellState.themePickerOpen }
    }

    function parse(text) {
        const out = {}
        for (const line of text.split("\n")) {
            const m = line.match(/^([a-z_]+)\s*=\s*"([^"]*)"/)
            if (m) out[m[1]] = m[2]
        }
        return out
    }

    function pretty(name) { return name.replace(/([a-z])([A-Z])/g, "$1 $2") }

    function apply(name) {
        ShellState.themePickerOpen = false
        Quickshell.execDetached([root.home + "/.local/bin/hypora-theme", name])
    }

    LazyLoader {
        active: ShellState.themePickerOpen

        PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "hypora-themes"
            color: "#99000000"

            FileView { id: currentName; path: root.home + "/.config/hypora/current/name"; blockLoading: true; printErrors: false }

            FolderListModel {
                id: themes
                folder: "file://" + root.themesDir
                showDirs: true
                showFiles: false
                sortField: FolderListModel.Name
            }

            MouseArea {
                anchors.fill: parent
                onClicked: ShellState.themePickerOpen = false
            }

            Rectangle {
                id: panel
                anchors.centerIn: parent
                width: grid.cellWidth * Math.min(Math.max(grid.count, 1), 3) + 48
                height: header.height + grid.cellHeight * Math.min(Math.ceil(grid.count / 3), 2) + 56
                radius: 18
                color: Theme.bg
                border.width: 1
                border.color: Theme.surface

                MouseArea { anchors.fill: parent }   // swallow clicks inside the panel

                Column {
                    id: header
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                    spacing: 2
                    Text {
                        text: "Themes"
                        font.family: Theme.font; font.pixelSize: Theme.fontSize + 7; font.bold: true
                        color: Theme.fg
                    }
                    Text {
                        text: "Arrows to choose, Enter to apply, Esc to close"
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                        color: Theme.dim
                    }
                }

                GridView {
                    id: grid
                    anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom; margins: 24; topMargin: 16 }
                    cellWidth: 344
                    cellHeight: 286
                    clip: true
                    model: themes
                    focus: true
                    keyNavigationEnabled: true
                    highlightFollowsCurrentItem: false
                    boundsBehavior: Flickable.StopAtBounds
                    Component.onCompleted: forceActiveFocus()

                    Keys.onReturnPressed: if (currentItem) root.apply(currentItem.name)
                    Keys.onEnterPressed: if (currentItem) root.apply(currentItem.name)
                    Keys.onEscapePressed: ShellState.themePickerOpen = false

                    // Start on the theme in use
                    onCountChanged: {
                        for (let i = 0; i < count; i++)
                            if (themes.get(i, "fileName") === currentName.text().trim()) currentIndex = i
                    }

                    delegate: Item {
                        id: card
                        required property string fileName
                        required property int index
                        readonly property string name: fileName
                        readonly property var c: root.parse(colors.text())
                        readonly property bool isCurrent: name === currentName.text().trim()
                        readonly property bool selected: GridView.isCurrentItem

                        width: grid.cellWidth
                        height: grid.cellHeight

                        FileView { id: colors; path: `${root.themesDir}/${card.name}/colors.toml`; blockLoading: true; printErrors: false }
                        FolderListModel {
                            id: walls
                            folder: `file://${root.themesDir}/${card.name}/backgrounds`
                            nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
                            showDirs: false
                            sortField: FolderListModel.Name
                        }

                        Rectangle {
                            anchors { fill: parent; margins: 6 }
                            radius: 14
                            color: card.selected ? Theme.surface : "transparent"
                            border.width: 2
                            border.color: card.selected ? Theme.accent : "transparent"

                            // ---- preview: wallpaper + a miniature desktop in the theme's colors ----
                            Rectangle {
                                id: preview
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                                height: 180
                                clip: true
                                color: card.c.background ?? "#000000"

                                Image {
                                    anchors.fill: parent
                                    visible: walls.count > 0
                                    source: walls.count > 0 ? walls.get(0, "fileUrl") : ""
                                    fillMode: Image.PreserveAspectCrop
                                    sourceSize: Qt.size(640, 360)
                                    asynchronous: true
                                }

                                // Bar
                                Rectangle {
                                    anchors { left: parent.left; right: parent.right; top: parent.top }
                                    height: 14
                                    color: card.c.background ?? "#000"
                                    Row {
                                        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                                        spacing: 3
                                        Rectangle { width: 6; height: 6; radius: 3; color: card.c.accent ?? "#888" }
                                        Repeater {
                                            model: 4
                                            Rectangle {
                                                required property int index
                                                width: 6; height: 4; radius: 1
                                                color: index === 0 ? (card.c.accent ?? "#888") : (card.c.dim ?? "#666")
                                            }
                                        }
                                    }
                                    Rectangle { anchors.centerIn: parent; width: 36; height: 3; radius: 1; color: card.c.foreground ?? "#ccc" }
                                    Rectangle {
                                        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                        width: 22; height: 6; radius: 3; color: card.c.surface ?? "#333"
                                    }
                                }

                                // A terminal window
                                Rectangle {
                                    x: 22; y: 30
                                    width: 158; height: 120
                                    radius: 5
                                    color: card.c.background ?? "#000"
                                    border.width: 1.5
                                    border.color: card.c.accent ?? "#888"
                                    Column {
                                        anchors { left: parent.left; top: parent.top; margins: 9 }
                                        spacing: 6
                                        Repeater {
                                            model: ["green", "blue", "magenta", "yellow", "foreground", "red"]
                                            Row {
                                                required property string modelData
                                                required property int index
                                                spacing: 4
                                                Rectangle { width: 6; height: 4; radius: 1; color: card.c.green ?? "#8a8" }
                                                Rectangle {
                                                    width: 30 + (index * 37) % 70; height: 4; radius: 1
                                                    color: card.c[modelData] ?? "#ccc"
                                                }
                                            }
                                        }
                                    }
                                }

                                // A second window (unfocused)
                                Rectangle {
                                    x: 190; y: 30
                                    width: 112; height: 120
                                    radius: 5
                                    color: card.c.surface ?? "#222"
                                    border.width: 1.5
                                    border.color: card.c.muted ?? "#444"
                                    Column {
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 9 }
                                        spacing: 7
                                        Rectangle { width: parent.width * 0.6; height: 5; radius: 2; color: card.c.foreground ?? "#ccc" }
                                        Repeater {
                                            model: 4
                                            Rectangle {
                                                required property int index
                                                width: parent.width * (0.9 - index * 0.15); height: 3; radius: 1
                                                color: card.c.dim ?? "#666"
                                            }
                                        }
                                        Rectangle { width: 40; height: 12; radius: 6; color: card.c.accent ?? "#888" }
                                    }
                                }
                            }

                            // ---- name, "current" tag and palette ----
                            Row {
                                id: title
                                anchors { left: preview.left; top: preview.bottom; topMargin: 12 }
                                spacing: 8
                                Text {
                                    text: root.pretty(card.name)
                                    font.family: Theme.font; font.pixelSize: Theme.fontSize + 1; font.bold: true
                                    color: card.selected ? Theme.accent : Theme.fg
                                }
                                Rectangle {
                                    visible: card.isCurrent
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: tag.implicitWidth + 14; height: 18; radius: 9
                                    color: Theme.accent
                                    Text {
                                        id: tag
                                        anchors.centerIn: parent
                                        text: "Current"
                                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 4; font.bold: true
                                        color: Theme.bg
                                    }
                                }
                            }
                            Row {
                                anchors { left: preview.left; top: title.bottom; topMargin: 10 }
                                spacing: 6
                                Repeater {
                                    model: ["background", "surface", "accent", "red", "green", "yellow", "blue", "magenta", "cyan"]
                                    Rectangle {
                                        required property string modelData
                                        width: 18; height: 18; radius: 9
                                        color: card.c[modelData] ?? "transparent"
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.15)
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: grid.currentIndex = card.index
                                onClicked: root.apply(card.name)
                            }
                        }
                    }
                }
            }
        }
    }
}
