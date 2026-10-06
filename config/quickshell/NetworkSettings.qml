import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick
import QtQuick.Layouts

// Network settings: Wi-Fi on/off, nearby networks, connect, disconnect and forget.
// Covers everyday use; nmtui is still one click away under "Advanced".
// Open from the menu (Settings > Network), the Wi-Fi tile's arrow, or:
//     qs ipc call network open
Scope {
    id: root

    IpcHandler {
        target: "network"
        function open(): void { ShellState.networkSettingsOpen = true }
        function close(): void { ShellState.networkSettingsOpen = false }
    }

    LazyLoader {
        active: ShellState.networkSettingsOpen

        FloatingWindow {
            id: win
            title: "Network"
            implicitWidth: 520
            implicitHeight: 620
            color: Theme.bg
            onClosed: ShellState.networkSettingsOpen = false

            readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
            readonly property var wired: Networking.devices.values.find(d => d.type !== DeviceType.Wifi && d.connected) ?? null

            // A card whose radio is switched off drops out of Networking.devices entirely, so
            // "no device" does not mean "no hardware" — reporting it that way sends you looking
            // for a driver or firmware problem that isn't there. Net asks nmcli, which lists the
            // card in every state, so it is the honest answer to "is there a Wi-Fi card".
            readonly property bool wifiPresent: wifiDevice !== null || Net.hasWifi
            // False only for a hard block: a physical switch, or the BIOS
            readonly property bool wifiBlocked: !Networking.wifiHardwareEnabled

            // The radio goes through Net (nmcli) rather than the Networking module, because
            // with the radio off there's no device object for the module to act on, which is
            // exactly when you need the switch to work. Same path the control centre uses.
            function setRadio(on) {
                Net.setWifiEnabled(on)
                Networking.requestSetWifiEnabled(on)
            }

            // Strongest entry per name, connected first, then by signal
            readonly property var networks: {
                const best = {}
                for (const n of (wifiDevice?.networks?.values ?? [])) {
                    if (!n.name) continue
                    const prev = best[n.name]
                    if (!prev || n.connected || n.signalStrength > prev.signalStrength) best[n.name] = n
                }
                return Object.values(best).sort((a, b) =>
                    (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength))
            }

            property var pending: null      // network awaiting a password
            property string notice: ""

            function secured(n) {
                return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Unknown
            }

            function activate(n) {
                notice = ""
                if (n.connected) { n.disconnect(); return }
                // A known network already has its secret stored; a new secured one needs asking
                if (n.known || !secured(n)) n.connect()
                else { pending = n; password.text = ""; password.forceActiveFocus() }
            }

            // First-time join: create the profile with nmcli, then let Quickshell track it.
            // The password goes in on stdin, never on the command line: arguments are
            // world-readable in /proc/<pid>/cmdline for as long as the process lives.
            property string secret: ""

            function joinWithPassword() {
                if (!pending || password.text === "") return
                secret = password.text
                join.command = ["nmcli", "--ask", "device", "wifi", "connect", pending.name]
                join.running = true
                notice = `Connecting to ${pending.name}...`
                pending = null
                password.text = ""
            }

            Process {
                id: join
                stdinEnabled: true
                stdout: joinOut
                stderr: joinOut
                // nmcli --ask prompts for the secret once it's running
                onStarted: { write(win.secret + "\n"); win.secret = "" }
                onExited: code => {
                    win.secret = ""
                    win.notice = code === 0 ? "" : "Could not connect. Check the password and try again."
                }
            }
            StdioCollector { id: joinOut }

            // Keep the list fresh while the window is open
            Component.onCompleted: if (wifiDevice) wifiDevice.scannerEnabled = true
            Component.onDestruction: if (wifiDevice) wifiDevice.scannerEnabled = false

            Rectangle {
                id: page
                anchors.fill: parent
                color: Theme.bg

                ColumnLayout {
                    anchors { fill: parent; margins: 24 }
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: "Network"
                            font.family: Theme.font; font.pixelSize: Theme.fontSize + 9; font.bold: true
                            color: Theme.fg
                        }
                        Text {
                            visible: win.wifiPresent
                            text: win.wifiBlocked ? "Wi-Fi blocked"
                                : Networking.wifiEnabled ? "Wi-Fi on" : "Wi-Fi off"
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                            color: Theme.dim
                        }
                        Toggle {
                            visible: win.wifiPresent
                            enabled: !win.wifiBlocked
                            opacity: enabled ? 1 : 0.4
                            checked: Networking.wifiEnabled
                            onToggled: win.setRadio(!Networking.wifiEnabled)
                        }
                    }

                    // Wired, when present
                    Rectangle {
                        Layout.fillWidth: true
                        visible: win.wired !== null
                        implicitHeight: 54
                        radius: 12
                        color: Theme.surface
                        Icon {
                            id: wiredIcon
                            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                            name: "ethernet"; size: 18; color: Theme.accent
                        }
                        Column {
                            anchors { left: wiredIcon.right; leftMargin: 14; verticalCenter: parent.verticalCenter }
                            Text {
                                text: "Wired"
                                font.family: Theme.font; font.pixelSize: Theme.fontSize; font.bold: true
                                color: Theme.fg
                            }
                            Text {
                                text: win.wired ? win.wired.address : ""
                                font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
                                color: Theme.dim
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: win.notice
                        wrapMode: Text.Wrap
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                        color: win.notice.startsWith("Could not") ? Theme.error : Theme.dim
                    }

                    // Password prompt for a new secured network
                    Rectangle {
                        Layout.fillWidth: true
                        visible: win.pending !== null
                        implicitHeight: 94
                        radius: 12
                        color: Theme.surface
                        border.width: 1
                        border.color: Theme.accent

                        ColumnLayout {
                            anchors { fill: parent; margins: 14 }
                            spacing: 8
                            Text {
                                text: win.pending ? `Password for ${win.pending.name}` : ""
                                font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                                color: Theme.fg
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 34
                                    radius: 8
                                    color: Theme.bg
                                    TextInput {
                                        id: password
                                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                        verticalAlignment: TextInput.AlignVCenter
                                        echoMode: TextInput.Password
                                        font.family: Theme.font; font.pixelSize: Theme.fontSize
                                        color: Theme.fg
                                        selectionColor: Theme.accent
                                        clip: true
                                        onAccepted: win.joinWithPassword()
                                        Keys.onEscapePressed: win.pending = null
                                    }
                                }
                                Button { text: "Cancel"; onClicked: win.pending = null }
                                Button { text: "Join"; primary: true; onClicked: win.joinWithPassword() }
                            }
                        }
                    }

                    ListView {
                        id: list
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        model: win.networks
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            readonly property bool busy: modelData.state === NetworkState.Connecting
                                                      || modelData.state === NetworkState.Disconnecting
                            width: ListView.view.width
                            height: 52
                            radius: 10
                            color: rowArea.containsMouse ? Theme.surface : "transparent"

                            Icon {
                                id: sig
                                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                                name: "wifi"
                                level: row.modelData.signalStrength / 100
                                size: 17
                                color: row.modelData.connected ? Theme.accent : Theme.fg
                            }
                            Column {
                                anchors { left: sig.right; leftMargin: 14; right: action.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                Text {
                                    width: parent.width
                                    text: row.modelData.name
                                    elide: Text.ElideRight
                                    font.family: Theme.font; font.pixelSize: Theme.fontSize
                                    font.bold: row.modelData.connected
                                    color: row.modelData.connected ? Theme.accent : Theme.fg
                                }
                                Text {
                                    width: parent.width
                                    text: row.busy ? NetworkState.toString(row.modelData.state)
                                         : row.modelData.connected ? "Connected"
                                         : row.modelData.known ? "Saved" : ""
                                    elide: Text.ElideRight
                                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
                                    color: Theme.dim
                                }
                            }
                            Row {
                                id: action
                                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                spacing: 10
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: win.secured(row.modelData)
                                    name: "lock"; size: 13; color: Theme.dim
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: row.modelData.known && rowArea.containsMouse
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
                            width: list.width - 40
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            text: !win.wifiPresent ? "No Wi-Fi adapter found"
                                 : win.wifiBlocked ? "Wi-Fi is blocked by a hardware switch or the BIOS"
                                 : !Networking.wifiEnabled ? "Wi-Fi is off — use the switch above"
                                 : "Looking for networks..."
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                            color: Theme.dim
                        }
                    }

                    // The TUI is still there for anything this window doesn't cover
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
                            onClicked: Apps.inTerminal(Theme.network)
                        }
                    }
                }
            }

            component Button: Rectangle {
                id: btn
                property string text
                property bool primary: false
                signal clicked()
                implicitWidth: btnText.implicitWidth + 28
                implicitHeight: 34
                radius: 17
                color: primary ? Theme.accent : (btnArea.containsMouse ? Qt.lighter(Theme.surface, 1.25) : Theme.surface)
                Text {
                    id: btnText
                    anchors.centerIn: parent
                    text: btn.text
                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 1; font.bold: btn.primary
                    color: btn.primary ? Theme.bg : Theme.fg
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
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tog.toggled()
                }
            }
        }
    }
}
