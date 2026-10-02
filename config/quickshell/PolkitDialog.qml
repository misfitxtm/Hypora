import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import QtQuick
import QtQuick.Layouts

Scope {
    PolkitAgent { id: agent }

    LazyLoader {
        active: agent.isActive

        PanelWindow {
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "#99000000"

            Rectangle {
                anchors.centerIn: parent
                width: 420
                height: col.implicitHeight + 40
                radius: 10
                color: Theme.surface
                border.color: Theme.accent
                border.width: 1

                ColumnLayout {
                    id: col
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                    spacing: 12

                    Text {
                        Layout.fillWidth: true
                        text: "Authentication required"
                        font.family: Theme.font; font.pixelSize: Theme.fontSize + 3; font.bold: true
                        color: Theme.fg
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: agent.flow ? agent.flow.message : ""
                        font.family: Theme.font; font.pixelSize: Theme.fontSize
                        color: Theme.fg
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        wrapMode: Text.Wrap
                        text: agent.flow ? agent.flow.supplementaryMessage : ""
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                        color: agent.flow && agent.flow.supplementaryIsError ? Theme.error : Theme.dim
                    }
                    Text {
                        text: agent.flow ? agent.flow.inputPrompt : ""
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                        color: Theme.dim
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 34; radius: 6
                        color: Theme.bg
                        border.color: Theme.dim

                        TextInput {
                            id: input
                            anchors { fill: parent; margins: 8 }
                            echoMode: agent.flow && agent.flow.responseVisible ? TextInput.Normal : TextInput.Password
                            font.family: Theme.font; font.pixelSize: Theme.fontSize
                            color: Theme.fg
                            focus: true
                            Component.onCompleted: forceActiveFocus()
                            onAccepted: {
                                agent.flow.submit(text)
                                text = ""
                            }
                            Keys.onEscapePressed: agent.flow.cancelAuthenticationRequest()
                        }
                    }

                    Text {
                        visible: agent.flow && agent.flow.failed
                        text: "Authentication failed, try again."
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                        color: Theme.error
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 8
                        Rectangle {
                            width: 80; height: 30; radius: 6; color: Theme.bg
                            Text { anchors.centerIn: parent; text: "Cancel"; color: Theme.fg
                                   font.family: Theme.font; font.pixelSize: Theme.fontSize }
                            MouseArea { anchors.fill: parent; onClicked: agent.flow.cancelAuthenticationRequest() }
                        }
                        Rectangle {
                            width: 80; height: 30; radius: 6; color: Theme.accent
                            Text { anchors.centerIn: parent; text: "OK"; color: Theme.bg
                                   font.family: Theme.font; font.pixelSize: Theme.fontSize }
                            MouseArea { anchors.fill: parent; onClicked: input.accepted() }
                        }
                    }
                }
            }
        }
    }
}
