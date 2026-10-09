import Quickshell
import Quickshell.Io
import QtQuick

// Clipboard history, left of the clock. Click (or SUPER + SHIFT + V) for recent copies;
// pick one to put it back on the clipboard.
//
// The history is recorded by `wl-paste --watch cliphist store`, started from
// hyprland.lua. Quickshell can't watch the clipboard itself — it doesn't speak
// wlr-data-control, so it would only see what was copied while the shell had focus.
Rectangle {
    id: root
    required property var window

    property var entries: []      // [{ id, preview }]
    property string notice: ""

    implicitWidth: 26
    implicitHeight: 24
    radius: height / 2
    color: drop.open ? Theme.surface : (area.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")

    Icon {
        anchors.centerIn: parent
        name: "clipboard"
        size: 15
        color: drop.open ? Theme.accent : Theme.fg
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: drop.open = true
    }

    IpcHandler {
        // One handler per bar; the main display's owns the shortcut
        enabled: ShellState.isPrimary(root.window.screen)
        target: "clipboard"
        function toggle(): void { drop.open = !drop.open }
    }

    // `cliphist list` prints "<id>\t<preview>" per line, newest first
    Process {
        id: load
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t")
                    if (tab > 0) out.push({ id: line.slice(0, tab), preview: line.slice(tab + 1) })
                }
                root.entries = out
                root.notice = out.length === 0 ? "Nothing copied yet." : ""
            }
        }
        onExited: code => {
            if (code !== 0) {
                root.entries = []
                root.notice = "cliphist isn't available, so there's no history to show."
            }
        }
    }

    function refresh() { if (!load.running) load.running = true }

    function paste(id) {
        // The pipe needs a shell, so the id must not be able to carry anything else into
        // it. cliphist ids are plain integers; refuse whatever isn't one.
        if (!/^[0-9]+$/.test(id)) {
            notice = "Skipped an entry with an unexpected id."
            return
        }
        drop.open = false
        Quickshell.execDetached(["sh", "-c", `cliphist decode ${id} | wl-copy`])
    }

    function wipe() {
        Quickshell.execDetached(["cliphist", "wipe"])
        entries = []
        notice = "History cleared."
    }

    Dropdown {
        id: drop
        screen: root.window.screen
        barHeight: root.window.height
        anchorItem: root        // open under the icon, not at the far left of the bar
        onVisibleChanged: if (visible) root.refresh()

        Rectangle {
            implicitWidth: 380
            implicitHeight: 48 + Math.max(1, Math.min(list.count, 9)) * 34 + 14
            radius: 16
            color: Theme.bg
            border.width: 1
            border.color: Theme.surface

            Text {
                id: heading
                anchors { left: parent.left; top: parent.top; margins: 16 }
                text: "Clipboard"
                font.family: Theme.font; font.pixelSize: Theme.fontSize + 1; font.bold: true
                color: Theme.fg
            }
            Text {
                anchors { right: parent.right; rightMargin: 16; verticalCenter: heading.verticalCenter }
                visible: root.entries.length > 0
                text: "Clear"
                font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                color: clearArea.containsMouse ? Theme.error : Theme.dim
                MouseArea {
                    id: clearArea
                    anchors { fill: parent; margins: -6 }
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.wipe()
                }
            }

            ListView {
                id: list
                // Page Up / Page Down through the history without the mouse.
                focus: true
                Keys.onPressed: event => event.accepted = PageScroll.handle(event, list)
                anchors {
                    left: parent.left; right: parent.right
                    top: heading.bottom; bottom: parent.bottom
                    leftMargin: 10; rightMargin: 10; topMargin: 10; bottomMargin: 12
                }
                clip: true
                spacing: 1
                model: root.entries
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 34
                    radius: 7
                    color: rowArea.containsMouse ? Theme.surface : "transparent"

                    Text {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        width: 22
                        text: row.index + 1
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
                        color: Theme.dim
                    }
                    Text {
                        anchors { left: parent.left; right: parent.right; leftMargin: 34; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: row.modelData.preview
                        elide: Text.ElideRight
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                        color: Theme.fg
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.paste(row.modelData.id)
                    }
                }

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 24
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    visible: list.count === 0
                    text: root.notice
                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                    color: Theme.dim
                }
            }
        }
    }
}
