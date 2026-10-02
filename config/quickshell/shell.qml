import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Greetd
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root

    // What to start after a successful login. Check: ls /usr/share/wayland-sessions
    readonly property var sessionCommand: ["uwsm", "start", "hyprland-uwsm.desktop"]

    property string stage: "user"   // "user" -> "auth"
    property string prompt: ""
    property bool echo: false
    property string message: ""
    property bool isError: false
    property bool busy: false

    function failBack(msg) {
        root.message = msg
        root.isError = true
        root.busy = false
        root.stage = "user"
        if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession()
    }

    Connections {
        target: Greetd

        function onAuthMessage(message, error, responseRequired, echoResponse) {
            root.busy = false
            if (responseRequired) {
                root.stage = "auth"
                root.prompt = message
                root.echo = echoResponse
                root.message = ""
            } else {
                // Informational message (e.g. fingerprint hint); acknowledge it
                root.message = message
                root.isError = error
                Greetd.respond("")
            }
        }
        function onAuthFailure(message) {
            root.failBack(message !== "" ? message : "Authentication failed")
        }
        function onReadyToLaunch() {
            root.busy = true
            Greetd.launch(root.sessionCommand)
        }
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            readonly property bool primary: modelData === Quickshell.screens[0]

            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: Theme.bg

            // Only the primary screen shows the login form
            Item {
                anchors.fill: parent
                visible: win.primary

                ColumnLayout {
                    anchors.centerIn: parent
                    width: 340
                    spacing: 14

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        font.family: Theme.font; font.pixelSize: 72; font.bold: true
                        color: Theme.fg
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.bottomMargin: 24
                        text: Qt.formatDateTime(clock.date, "dddd, MMMM d")
                        font.family: Theme.font; font.pixelSize: Theme.fontSize + 2
                        color: Theme.dim
                    }

                    Text {
                        text: root.stage === "user" ? "Username" : root.prompt.replace(/:\s*$/, "")
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                        color: Theme.dim
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 40; radius: 8
                        color: Theme.surface
                        border.width: 1
                        border.color: input.activeFocus ? Theme.accent : Theme.dim

                        TextInput {
                            id: input
                            anchors { fill: parent; margins: 10 }
                            enabled: !root.busy
                            echoMode: root.stage === "auth" && !root.echo ? TextInput.Password : TextInput.Normal
                            font.family: Theme.font; font.pixelSize: Theme.fontSize + 1
                            color: Theme.fg
                            verticalAlignment: TextInput.AlignVCenter
                            focus: true
                            Component.onCompleted: forceActiveFocus()

                            onAccepted: {
                                if (root.busy || text === "") return
                                root.busy = true
                                if (root.stage === "user") Greetd.createSession(text)
                                else Greetd.respond(text)
                                text = ""
                            }
                            Keys.onEscapePressed: {
                                if (root.stage === "auth") {
                                    Greetd.cancelSession()
                                    root.stage = "user"
                                    root.message = ""
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: root.busy && root.message === "" ? "Working..." : root.message
                        wrapMode: Text.Wrap
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                        color: root.isError ? Theme.error : Theme.dim
                    }

                    RowLayout {
                        Layout.topMargin: 30
                        Layout.fillWidth: true
                        spacing: 8
                        PowerButton {
                            label: "Reboot"; confirm: true
                            onActivated: Quickshell.execDetached(["systemctl", "reboot"])
                        }
                        PowerButton {
                            label: "Off"; confirm: true
                            onActivated: Quickshell.execDetached(["systemctl", "poweroff"])
                        }
                    }
                }

                Connections {
                    target: root
                    function onStageChanged() { input.forceActiveFocus() }
                }
            }
        }
    }
}
