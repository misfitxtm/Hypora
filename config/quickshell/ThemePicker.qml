import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import Qt.labs.folderlistmodel

// Theme picker (SUPER + ALT + T, or menu > Style > Theme), as a sliding carousel: one theme
// at a time, centred and large, with its neighbours peeking in at either side.
//
// Each card is a live preview rather than a screenshot — the theme's own first wallpaper
// behind a miniature desktop drawn in that theme's colours, so what you see is generated
// from the same colors.toml that hypora-theme will apply.
//
// Left/Right or scroll to slide, Enter or click to apply, Esc to close. Typing filters.
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
            color: "#d0000000"

            property string filterText: ""      // not on the Text below: it has `text` already
            readonly property int cardWidth: 620
            readonly property int cardHeight: 390

            FileView {
                id: currentName
                path: root.home + "/.config/hypora/current/name"
                blockLoading: true
                printErrors: false
            }
            readonly property string active: currentName.text().trim()

            FolderListModel {
                id: themes
                folder: "file://" + root.themesDir
                showDirs: true
                showFiles: false
                sortField: FolderListModel.Name
            }

            // FolderListModel can't filter on a typed string, so the carousel runs off a
            // plain list built from it — which also makes "no match" easy to show.
            readonly property var allNames: {
                const out = []
                for (let i = 0; i < themes.count; i++) out.push(themes.get(i, "fileName"))
                return out
            }
            readonly property var shown: {
                const q = win.filterText.trim().toLowerCase()
                return q === "" ? allNames : allNames.filter(n => n.toLowerCase().indexOf(q) >= 0)
            }
            readonly property string focused: carousel.currentIndex >= 0
                                               && carousel.currentIndex < shown.length
                                               ? shown[carousel.currentIndex] : ""

            // Land on the theme in use the first time the list arrives
            property bool positioned: false
            onShownChanged: {
                if (!positioned && shown.length > 0) {
                    const i = shown.indexOf(active)
                    carousel.currentIndex = i >= 0 ? i : 0
                    carousel.positionViewAtIndex(carousel.currentIndex, ListView.Center)
                    positioned = true
                } else if (carousel.currentIndex >= shown.length) {
                    carousel.currentIndex = Math.max(0, shown.length - 1)
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: ShellState.themePickerOpen = false
            }

            // ---------- keys ----------
            Item {
                anchors.fill: parent
                focus: true
                Component.onCompleted: forceActiveFocus()
                Keys.onLeftPressed: carousel.decrementCurrentIndex()
                Keys.onRightPressed: carousel.incrementCurrentIndex()
                Keys.onEscapePressed: ShellState.themePickerOpen = false
                Keys.onReturnPressed: if (win.focused !== "") root.apply(win.focused)
                Keys.onEnterPressed: if (win.focused !== "") root.apply(win.focused)
                // Anything else goes to the filter, so you can just start typing
                Keys.onPressed: event => {
                    // Before the filter catches everything: paging the carousel is a
                    // navigation key, not something you meant to type.
                    if (PageScroll.handle(event, carousel)) { event.accepted = true; return }
                    if (event.key === Qt.Key_Backspace) { win.filterText = win.filterText.slice(0, -1); event.accepted = true }
                    else if (event.text.length === 1 && event.text >= " ") { win.filterText += event.text; event.accepted = true }
                }
            }

            // Laid out against the window, not stacked in a Column. A Column takes the
            // width of its widest child, which here is the full-width carousel, so the
            // heading and dots ended up at its left edge and the strip itself was pushed
            // off centre. Anchoring each piece independently keeps the selected card on
            // the middle of the monitor whatever the screen width is.
            Item {
                id: stage
                anchors.fill: parent

                // ---------- heading ----------
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: carousel.top
                    width: win.cardWidth
                    height: 56
                    Text {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        text: "Themes"
                        font.family: Theme.font; font.pixelSize: Theme.fontSize + 9; font.bold: true
                        color: Theme.fg
                    }
                    // The filter doubles as the hint line until you type into it
                    Rectangle {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: 228; height: 32; radius: 16
                        color: win.filterText === "" ? "transparent" : Theme.surface
                        border.width: 1
                        border.color: win.filterText === "" ? "transparent" : Theme.accent
                        Icon {
                            id: fIcon
                            anchors { left: parent.left; leftMargin: 11; verticalCenter: parent.verticalCenter }
                            visible: win.filterText !== ""
                            name: "search"; size: 13; color: Theme.dim
                        }
                        Text {
                            id: filter
                            anchors {
                                left: win.filterText === "" ? parent.left : fIcon.right
                                leftMargin: win.filterText === "" ? 0 : 9
                                right: parent.right; rightMargin: 12
                                verticalCenter: parent.verticalCenter
                            }
                            horizontalAlignment: win.filterText === "" ? Text.AlignRight : Text.AlignLeft
                            elide: Text.ElideRight
                            text: win.filterText === "" ? "Type to filter  ·  Enter to apply" : win.filterText
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                            color: win.filterText === "" ? Theme.dim : Theme.fg
                        }
                    }
                }

                // ---------- the carousel ----------
                ListView {
                    id: carousel
                    // Full width so the centred card lands on the centre of the screen, and
                    // so the neighbours have somewhere to show
                    anchors { left: parent.left; right: parent.right }
                    y: (parent.height - height) / 2
                    height: win.cardHeight + 24

                    orientation: ListView.Horizontal
                    model: win.shown
                    spacing: 26
                    clip: false
                    // Snap the current card to the middle; this is what makes it slide
                    // rather than scroll, and it keeps keyboard and wheel in agreement.
                    snapMode: ListView.SnapOneItem
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    preferredHighlightBegin: (width - win.cardWidth) / 2
                    preferredHighlightEnd: (width + win.cardWidth) / 2
                    highlightMoveDuration: 260
                    highlightMoveVelocity: -1
                    boundsBehavior: Flickable.StopAtBounds
                    // Only the visible cards plus one either side get built
                    cacheBuffer: win.cardWidth * 2

                    delegate: Item {
                        id: card
                        required property string modelData
                        required property int index
                        readonly property string name: modelData
                        readonly property var c: root.parse(colors.text())
                        readonly property bool isCurrent: name === win.active
                        readonly property bool selected: index === carousel.currentIndex

                        width: win.cardWidth
                        height: carousel.height

                        // Neighbours sit back and dim, so the centre card reads as the subject
                        scale: selected ? 1 : 0.9
                        opacity: selected ? 1 : 0.45
                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 220 } }

                        FileView {
                            id: colors
                            path: `${root.themesDir}/${card.name}/colors.toml`
                            blockLoading: true
                            printErrors: false
                        }
                        FolderListModel {
                            id: walls
                            folder: `file://${root.themesDir}/${card.name}/backgrounds`
                            nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
                            showDirs: false
                            sortField: FolderListModel.Name
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 18
                            color: Theme.bg
                            border.width: 2
                            border.color: card.selected ? Theme.accent : Theme.surface

                            // ---- live preview: the theme's wallpaper under a miniature desktop ----
                            Item {
                                id: preview
                                anchors { fill: parent; margins: 10 }
                                anchors.bottomMargin: 74
                                clip: true

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 10
                                    color: card.c.background ?? "#000000"
                                }
                                Image {
                                    anchors.fill: parent
                                    visible: walls.count > 0
                                    source: walls.count > 0 ? walls.get(0, "fileUrl") : ""
                                    fillMode: Image.PreserveAspectCrop
                                    sourceSize: Qt.size(win.cardWidth, 320)
                                    asynchronous: true
                                    layer.enabled: true
                                    layer.effect: null
                                }

                                // Bar
                                Rectangle {
                                    anchors { left: parent.left; right: parent.right; top: parent.top }
                                    height: 22
                                    color: card.c.background ?? "#000"
                                    Row {
                                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                        spacing: 5
                                        Rectangle { width: 9; height: 9; radius: 4.5; color: card.c.accent ?? "#888" }
                                        Repeater {
                                            model: 5
                                            Rectangle {
                                                required property int index
                                                width: 9; height: 6; radius: 2
                                                color: index === 0 ? (card.c.accent ?? "#888") : (card.c.dim ?? "#666")
                                            }
                                        }
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 54; height: 5; radius: 2
                                        color: card.c.foreground ?? "#ccc"
                                    }
                                    Rectangle {
                                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                        width: 34; height: 9; radius: 4.5; color: card.c.surface ?? "#333"
                                    }
                                }

                                // A focused terminal
                                Rectangle {
                                    x: 38; y: 52
                                    width: 268; height: 186
                                    radius: 8
                                    color: card.c.background ?? "#000"
                                    border.width: 2
                                    border.color: card.c.accent ?? "#888"
                                    Column {
                                        anchors { left: parent.left; top: parent.top; margins: 14 }
                                        spacing: 10
                                        Repeater {
                                            model: ["green", "blue", "magenta", "yellow", "foreground", "red"]
                                            Row {
                                                required property string modelData
                                                required property int index
                                                spacing: 6
                                                Rectangle { width: 10; height: 6; radius: 2; color: card.c.green ?? "#8a8" }
                                                Rectangle {
                                                    width: 48 + (index * 37) % 110; height: 6; radius: 2
                                                    color: card.c[modelData] ?? "#ccc"
                                                }
                                            }
                                        }
                                    }
                                }

                                // An unfocused window beside it
                                Rectangle {
                                    x: 320; y: 52
                                    width: 194; height: 186
                                    radius: 8
                                    color: card.c.surface ?? "#222"
                                    border.width: 2
                                    border.color: card.c.muted ?? "#444"
                                    Column {
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                                        spacing: 11
                                        Rectangle { width: parent.width * 0.6; height: 8; radius: 3; color: card.c.foreground ?? "#ccc" }
                                        Repeater {
                                            model: 4
                                            Rectangle {
                                                required property int index
                                                width: parent.width * (0.92 - index * 0.14); height: 5; radius: 2
                                                color: card.c.dim ?? "#666"
                                            }
                                        }
                                        Rectangle { width: 66; height: 20; radius: 10; color: card.c.accent ?? "#888" }
                                    }
                                }
                            }

                            // ---- name, "in use" tag, palette ----
                            Row {
                                anchors { left: parent.left; leftMargin: 20; bottom: parent.bottom; bottomMargin: 22 }
                                spacing: 10
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.pretty(card.name)
                                    font.family: Theme.font; font.pixelSize: Theme.fontSize + 3; font.bold: true
                                    color: card.selected ? Theme.accent : Theme.fg
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: card.isCurrent
                                    width: tag.implicitWidth + 16; height: 20; radius: 10
                                    color: Theme.accent
                                    Text {
                                        id: tag
                                        anchors.centerIn: parent
                                        text: "In use"
                                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 4; font.bold: true
                                        color: Theme.bg
                                    }
                                }
                            }
                            Row {
                                anchors { right: parent.right; rightMargin: 20; bottom: parent.bottom; bottomMargin: 22 }
                                spacing: 7
                                Repeater {
                                    model: ["background", "surface", "accent", "red", "green", "yellow", "blue", "magenta", "cyan"]
                                    Rectangle {
                                        required property string modelData
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 20; height: 20; radius: 10
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
                                // Click a neighbour to bring it in; click the centre one to apply it
                                onClicked: card.selected ? root.apply(card.name)
                                                         : carousel.currentIndex = card.index
                            }
                        }
                    }
                }

                // ---------- position dots ----------
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: carousel.bottom
                    width: win.cardWidth
                    height: 40
                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        visible: win.shown.length > 1
                        Repeater {
                            model: win.shown.length
                            Rectangle {
                                required property int index
                                width: index === carousel.currentIndex ? 20 : 7
                                height: 7; radius: 3.5
                                color: index === carousel.currentIndex ? Theme.accent : Theme.surface
                                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: win.shown.length === 0
                        text: `Nothing matches "${win.filterText}"`
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                        color: Theme.dim
                    }
                }
            }
        }
    }
}
