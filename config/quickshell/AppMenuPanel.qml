import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

// Contents of the app menu (ArcMenu style): search, categories and apps on the left;
// places, settings and session buttons in the sidebar on the right.
Rectangle {
    id: root
    signal closeRequested()

    property string category: ""     // "" = all apps
    readonly property var results: Apps.query(search.text, category)

    // Called each time the menu opens
    function reset() {
        search.text = ""
        category = ""
        list.currentIndex = 0
        list.positionViewAtBeginning()
        search.forceActiveFocus()
    }

    function launch(entry) {
        closeRequested()
        Apps.launch(entry)
    }
    function openFolder(xdgName) {
        closeRequested()
        Quickshell.execDetached(["sh", "-c", `xdg-open "$(xdg-user-dir ${xdgName} 2>/dev/null || echo "$HOME")"`])
    }
    function openTui(cmd) {
        closeRequested()
        Apps.inTerminal(cmd)
    }

    implicitWidth: 660
    implicitHeight: 500
    radius: 18
    color: Theme.bg
    border.width: 1
    border.color: Theme.surface
    clip: true

    FileView { id: hostname; path: "/etc/hostname"; blockLoading: true }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---------------- Left: search, categories, apps ----------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 16
            spacing: 12

            Rectangle {
                Layout.fillWidth: true
                height: 40
                radius: 20
                color: Theme.surface
                border.width: 1
                border.color: search.activeFocus ? Theme.accent : "transparent"

                Icon {
                    id: searchIcon
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    name: "search"
                    size: 15
                    color: Theme.dim
                }
                TextInput {
                    id: search
                    anchors { left: searchIcon.right; right: parent.right; leftMargin: 10; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    font.family: Theme.font; font.pixelSize: Theme.fontSize + 1
                    color: Theme.fg
                    selectionColor: Theme.accent
                    clip: true
                    onTextChanged: list.currentIndex = 0
                    onAccepted: if (list.count > 0) root.launch(root.results[list.currentIndex])
                    Keys.onUpPressed: list.decrementCurrentIndex()
                    Keys.onDownPressed: list.incrementCurrentIndex()
                    Keys.onTabPressed: list.incrementCurrentIndex()

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: search.text === ""
                        text: "Search apps"
                        font: search.font
                        color: Theme.dim
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                // Categories (hidden while searching)
                ListView {
                    id: cats
                    Layout.preferredWidth: 140
                    Layout.fillHeight: true
                    visible: search.text === ""
                    clip: true
                    spacing: 0
                    boundsBehavior: Flickable.StopAtBounds
                    model: [{ id: "", label: "All Apps" }, ...Apps.categories]

                    delegate: Rectangle {
                        id: cat
                        required property var modelData
                        readonly property bool selected: root.category === modelData.id
                        width: ListView.view.width
                        height: 32
                        radius: 8
                        color: selected ? Theme.surface : (catArea.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent")

                        Text {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            text: cat.modelData.label
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 1; font.bold: cat.selected
                            color: cat.selected ? Theme.accent : Theme.fg
                        }
                        MouseArea {
                            id: catArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.category = cat.modelData.id; list.currentIndex = 0; search.forceActiveFocus() }
                        }
                    }
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: root.results
                    currentIndex: 0
                    highlightMoveDuration: 0
                    boundsBehavior: Flickable.StopAtBounds
                    highlight: Rectangle { radius: 8; color: Theme.surface }

                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        height: 40

                        IconImage {
                            id: appIcon
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            implicitSize: 24
                            source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                        }
                        Text {
                            anchors { left: appIcon.right; right: parent.right; leftMargin: 12; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            text: row.modelData.name
                            elide: Text.ElideRight
                            font.family: Theme.font; font.pixelSize: Theme.fontSize
                            color: row.ListView.isCurrentItem ? Theme.accent : Theme.fg
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: list.currentIndex = row.index
                            onClicked: root.launch(row.modelData)
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: list.count === 0
                        text: "No apps found"
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                        color: Theme.dim
                    }
                }
            }
        }

        // ---------------- Right: sidebar ----------------
        Rectangle {
            Layout.preferredWidth: 210
            Layout.fillHeight: true
            color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.45)

            ColumnLayout {
                anchors { fill: parent; margins: 14 }
                spacing: 2

                // User
                RowLayout {
                    Layout.bottomMargin: 10
                    spacing: 10
                    Rectangle {
                        width: 36; height: 36; radius: 18
                        color: Theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: (Quickshell.env("USER") ?? "?").charAt(0).toUpperCase()
                            font.family: Theme.font; font.pixelSize: 16; font.bold: true
                            color: Theme.bg
                        }
                    }
                    Column {
                        Text {
                            text: Quickshell.env("USER") ?? ""
                            font.family: Theme.font; font.pixelSize: Theme.fontSize; font.bold: true
                            color: Theme.fg
                        }
                        Text {
                            text: hostname.text().trim()
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
                            color: Theme.dim
                        }
                    }
                }

                SidebarHeading { text: "Places" }
                SidebarItem { icon: "home"; label: "Home"; onClicked: root.openFolder("HOME") }
                SidebarItem { icon: "folder"; label: "Documents"; onClicked: root.openFolder("DOCUMENTS") }
                SidebarItem { icon: "download"; label: "Downloads"; onClicked: root.openFolder("DOWNLOAD") }
                SidebarItem { icon: "image"; label: "Pictures"; onClicked: root.openFolder("PICTURES") }

                SidebarHeading { text: "Settings"; Layout.topMargin: 8 }
                SidebarItem { icon: "monitor"; label: "Display"; onClicked: { root.closeRequested(); ShellState.displaySettingsOpen = true } }
                SidebarItem { icon: "wifi"; label: "Network"; onClicked: root.openTui(Theme.network) }
                SidebarItem { icon: "bluetooth"; label: "Bluetooth"; onClicked: root.openTui(Theme.bluetooth) }
                SidebarItem { icon: "volume"; label: "Sound"; onClicked: root.openTui(Theme.mixer) }
                SidebarItem { icon: "terminal"; label: "Terminal"; onClicked: { root.closeRequested(); Apps.run([Theme.terminal]) } }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8
                    PowerButton {
                        icon: "lock"
                        onActivated: { root.closeRequested(); Quickshell.execDetached(["hyprlock"]) }
                    }
                    PowerButton {
                        icon: "logout"; confirm: true
                        onActivated: Quickshell.execDetached(["sh", "-c",
                            "uwsm check is-active >/dev/null 2>&1 && uwsm stop || hyprctl dispatch 'hl.dsp.exit()'"])
                    }
                    PowerButton {
                        icon: "reboot"; confirm: true
                        onActivated: Quickshell.execDetached(["systemctl", "reboot"])
                    }
                    PowerButton {
                        icon: "power"; confirm: true
                        onActivated: Quickshell.execDetached(["systemctl", "poweroff"])
                    }
                }
            }
        }
    }

    component SidebarHeading: Text {
        Layout.leftMargin: 10
        Layout.bottomMargin: 2
        font.family: Theme.font; font.pixelSize: Theme.fontSize - 3; font.bold: true
        font.capitalization: Font.AllUppercase; font.letterSpacing: 1
        color: Theme.dim
    }

    component SidebarItem: Rectangle {
        id: item
        property string icon
        property string label
        signal clicked()

        Layout.fillWidth: true
        height: 32
        radius: 8
        color: itemArea.containsMouse ? Theme.surface : "transparent"

        Icon {
            id: itemIcon
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            name: item.icon
            size: 15
            color: itemArea.containsMouse ? Theme.accent : Theme.fg
        }
        Text {
            anchors { left: itemIcon.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
            text: item.label
            font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
            color: Theme.fg
        }
        MouseArea {
            id: itemArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: item.clicked()
        }
    }
}
