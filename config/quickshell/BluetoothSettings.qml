import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import QtQuick
import QtQuick.Layouts

// Bluetooth settings: power, scanning, pairing, connecting and forgetting devices.
// Replaces dropping into bluetui for everyday use.
// Open from the menu (Settings > Bluetooth), the Bluetooth tile's arrow, or:
//     qs ipc call bluetooth open
Scope {
    id: root

    IpcHandler {
        target: "bluetooth"
        function open(): void { ShellState.bluetoothSettingsOpen = true }
        function close(): void { ShellState.bluetoothSettingsOpen = false }
    }

    LazyLoader {
        active: ShellState.bluetoothSettingsOpen

        FloatingWindow {
            id: win
            title: "Bluetooth"
            implicitWidth: 520
            implicitHeight: 620
            color: Theme.bg
            onClosed: ShellState.bluetoothSettingsOpen = false

            readonly property var adapter: Bluetooth.defaultAdapter
            readonly property var devices: (adapter?.devices?.values ?? []).slice().sort((a, b) =>
                (b.connected - a.connected) || (b.paired - a.paired)
                || (a.deviceName || a.address).localeCompare(b.deviceName || b.address))
            readonly property var paired: devices.filter(d => d.paired)
            readonly property var nearby: devices.filter(d => !d.paired)

            function label(d) { return d.deviceName || d.name || d.address }

            function activate(d) {
                if (d.state === BluetoothDeviceState.Connecting || d.pairing) return
                if (d.connected) d.disconnect()
                else if (d.paired) d.connect()
                else d.pair()
            }

            function status(d) {
                if (d.pairing) return "Pairing..."
                if (d.state === BluetoothDeviceState.Connecting) return "Connecting..."
                if (d.state === BluetoothDeviceState.Disconnecting) return "Disconnecting..."
                if (d.connected) return d.batteryAvailable ? `Connected  ${Math.round(d.battery * 100)}%` : "Connected"
                if (d.paired) return "Paired"
                return ""
            }

            // Scan only while the window is open
            Component.onCompleted: if (adapter && adapter.enabled) adapter.discovering = true
            Component.onDestruction: if (adapter) adapter.discovering = false

            Rectangle {
                anchors.fill: parent
                color: Theme.bg

                ColumnLayout {
                    anchors { fill: parent; margins: 24 }
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: "Bluetooth"
                            font.family: Theme.font; font.pixelSize: Theme.fontSize + 9; font.bold: true
                            color: Theme.fg
                        }
                        Text {
                            text: !win.adapter ? "No adapter" : win.adapter.enabled ? "On" : "Off"
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                            color: Theme.dim
                        }
                        Toggle {
                            enabled: win.adapter !== null
                            opacity: enabled ? 1 : 0.4
                            checked: win.adapter?.enabled ?? false
                            onToggled: {
                                win.adapter.enabled = !win.adapter.enabled
                                if (win.adapter.enabled) win.adapter.discovering = true
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: win.adapter?.enabled ?? false
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: win.adapter?.discovering ? "Scanning for devices..." : "Scanning paused"
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                            color: Theme.dim
                        }
                        Button {
                            text: win.adapter?.discovering ? "Stop" : "Scan"
                            onClicked: win.adapter.discovering = !win.adapter.discovering
                        }
                    }

                    ListView {
                        id: list
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        boundsBehavior: Flickable.StopAtBounds
                        model: win.paired.concat(win.nearby)

                        // "My devices" / "Nearby" dividers
                        section.property: "paired"
                        section.delegate: Text {
                            required property string section
                            topPadding: 10
                            bottomPadding: 4
                            leftPadding: 4
                            text: section === "true" ? "MY DEVICES" : "NEARBY"
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 3; font.bold: true
                            font.letterSpacing: 1
                            color: Theme.dim
                        }

                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            width: ListView.view.width
                            height: 52
                            radius: 10
                            color: rowArea.containsMouse ? Theme.surface : "transparent"

                            Icon {
                                id: devIcon
                                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                                name: "bluetooth"
                                size: 17
                                color: row.modelData.connected ? Theme.accent : Theme.fg
                            }
                            Column {
                                anchors { left: devIcon.right; leftMargin: 14; right: forget.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                Text {
                                    width: parent.width
                                    text: win.label(row.modelData)
                                    elide: Text.ElideRight
                                    font.family: Theme.font; font.pixelSize: Theme.fontSize
                                    font.bold: row.modelData.connected
                                    color: row.modelData.connected ? Theme.accent : Theme.fg
                                }
                                Text {
                                    width: parent.width
                                    visible: text !== ""
                                    text: win.status(row.modelData)
                                    elide: Text.ElideRight
                                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
                                    color: Theme.dim
                                }
                            }
                            Text {
                                id: forget
                                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                visible: row.modelData.paired && rowArea.containsMouse
                                text: "Forget"
                                font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                                color: forgetArea.containsMouse ? Theme.error : Theme.dim
                                MouseArea {
                                    id: forgetArea
                                    anchors { fill: parent; margins: -6 }
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: row.modelData.forget()
                                }
                            }
                            MouseArea {
                                id: rowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (!forgetArea.containsMouse) win.activate(row.modelData)
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: list.count === 0
                            text: !win.adapter ? "No Bluetooth adapter found"
                                 : !win.adapter.enabled ? "Bluetooth is off"
                                 : "No devices found yet"
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                            color: Theme.dim
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: "Advanced..."
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                        color: advArea.containsMouse ? Theme.accent : Theme.dim
                        MouseArea {
                            id: advArea
                            anchors { fill: parent; margins: -6 }
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Apps.inTerminal(Theme.bluetooth)
                        }
                    }
                }
            }

            component Button: Rectangle {
                id: btn
                property string text
                signal clicked()
                implicitWidth: btnText.implicitWidth + 28
                implicitHeight: 32
                radius: 16
                color: btnArea.containsMouse ? Qt.lighter(Theme.surface, 1.25) : Theme.surface
                Text {
                    id: btnText
                    anchors.centerIn: parent
                    text: btn.text
                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                    color: Theme.fg
                }
                MouseArea {
                    id: btnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: btn.clicked()
                }
            }

            component Toggle: Rectangle {
                id: tog
                property bool checked
                signal toggled()
                implicitWidth: 44
                implicitHeight: 24
                radius: 12
                color: checked ? Theme.accent : Theme.surface
                Rectangle {
                    width: 18; height: 18; radius: 9
                    anchors.verticalCenter: parent.verticalCenter
                    x: tog.checked ? parent.width - width - 3 : 3
                    color: tog.checked ? Theme.bg : Theme.fg
                    Behavior on x { NumberAnimation { duration: 120 } }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: tog.enabled
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tog.toggled()
                }
            }
        }
    }
}
