import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick

// App launcher. Toggle with:  qs ipc call launcher toggle   (bound to SUPER + R)
// Type to filter, Up/Down to select, Enter to launch, Escape or click outside to close.
Scope {
    id: root
    property bool open: false

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.open = !root.open }
        function show(): void { root.open = true }
        function hide(): void { root.open = false }
    }

    function launch(entry) {
        open = false
        Apps.launch(entry)
    }

    LazyLoader {
        active: root.open

        PanelWindow {
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "hypora-launcher"
            color: "#66000000"

            readonly property var results: Apps.query(search.text, "")

            // Click outside the card to close
            MouseArea {
                anchors.fill: parent
                onClicked: root.open = false
            }

            Rectangle {
                id: card
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.2
                width: 560
                height: 64 + list.height
                radius: 12
                color: Theme.bg
                border.width: 1
                border.color: Theme.accent

                MouseArea { anchors.fill: parent }   // swallow clicks inside the card

                TextInput {
                    id: search
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                    height: 24
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.font; font.pixelSize: Theme.fontSize + 5
                    color: Theme.fg
                    selectionColor: Theme.accent
                    focus: true
                    Component.onCompleted: forceActiveFocus()

                    // The field has focus while you type, so paging the results below has
                    // to be handled here rather than on the list itself.
                    Keys.onPressed: event => event.accepted = PageScroll.handle(event, list)

                    onTextChanged: list.currentIndex = 0
                    onAccepted: if (list.count > 0) root.launch(results[list.currentIndex])
                    Keys.onEscapePressed: root.open = false
                    Keys.onUpPressed: list.decrementCurrentIndex()
                    Keys.onDownPressed: list.incrementCurrentIndex()
                    Keys.onTabPressed: list.incrementCurrentIndex()
                    Keys.onBacktabPressed: list.decrementCurrentIndex()

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: search.text === ""
                        text: "Search apps"
                        font: search.font
                        color: Theme.dim
                    }
                }

                ListView {
                    id: list
                    anchors { left: parent.left; right: parent.right; top: search.bottom; margins: 10; topMargin: 14 }
                    height: Math.min(count, 8) * 44
                    clip: true
                    model: results
                    currentIndex: 0
                    highlightMoveDuration: 0
                    boundsBehavior: Flickable.StopAtBounds

                    highlight: Rectangle { radius: 8; color: Theme.surface }

                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        height: 44

                        IconImage {
                            id: icon
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            implicitSize: 26
                            source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                        }
                        Text {
                            id: nameText
                            anchors { left: icon.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            // Capped so the description always has room. Without this a long
                            // one (Comment runs to 140-odd characters) overlapped the name.
                            width: Math.min(implicitWidth, row.width * 0.55)
                            elide: Text.ElideRight
                            text: row.modelData.name
                            font.family: Theme.font; font.pixelSize: Theme.fontSize + 1
                            color: row.ListView.isCurrentItem ? Theme.accent : Theme.fg
                        }
                        Text {
                            anchors { left: nameText.right; leftMargin: 12
                                      right: parent.right; rightMargin: 12
                                      verticalCenter: parent.verticalCenter }
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                            // Apps.describe, not genericName: most .desktop files don't set
                            // GenericName, which left this column empty for half the list
                            text: Apps.describe(row.modelData)
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                            color: Theme.dim
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: list.currentIndex = row.index
                            onClicked: root.launch(row.modelData)
                        }
                    }
                }
            }
        }
    }
}
