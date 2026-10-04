import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts

// Hamburger button + dropdown panel. Place it as the first item in the bar's left Row.
Item {
    id: root
    required property var window

    implicitWidth: 26
    implicitHeight: 20

    // --- Button (three bars) ---
    Rectangle {
        anchors.fill: parent
        radius: 4
        color: popup.visible ? Theme.accent : "transparent"

        Column {
            anchors.centerIn: parent
            spacing: 3
            Repeater {
                model: 3
                Rectangle {
                    width: 14; height: 2; radius: 1
                    color: popup.visible ? Theme.bg : Theme.fg
                }
            }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: popup.visible = !popup.visible
        }
    }

    // Close when clicking anywhere else
    HyprlandFocusGrab {
        windows: [popup]
        active: popup.visible
        onCleared: popup.visible = false
    }

    // --- Panel ---
    PopupWindow {
        id: popup
        visible: false
        anchor.window: root.window
        anchor.rect.x: 8
        anchor.rect.y: root.window.height + 4
        implicitWidth: 300
        implicitHeight: panel.implicitHeight + 32
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: Theme.surface
            border.color: Theme.accent
            border.width: 1

            ColumnLayout {
                id: panel
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 14

                Text {
                    text: "Control Center"
                    font.family: Theme.font; font.pixelSize: Theme.fontSize + 2; font.bold: true
                    color: Theme.fg
                }

                // Volume
                RowLayout {
                    id: volRow
                    Layout.fillWidth: true
                    spacing: 10
                    readonly property var sink: Pipewire.defaultAudioSink
                    readonly property var audio: sink ? sink.audio : null
                    PwObjectTracker { objects: volRow.sink ? [volRow.sink] : [] }

                    Text {
                        text: volRow.audio && volRow.audio.muted ? "MUTE" : "VOL"
                        font.family: Theme.font; font.pixelSize: Theme.fontSize
                        color: volRow.audio && volRow.audio.muted ? Theme.dim : Theme.fg
                        Layout.preferredWidth: 42
                        MouseArea {
                            anchors.fill: parent
                            onClicked: if (volRow.audio) volRow.audio.muted = !volRow.audio.muted
                        }
                    }
                    Slider {
                        Layout.fillWidth: true
                        value: volRow.audio ? volRow.audio.volume : 0
                        onMoved: v => { if (volRow.audio) volRow.audio.volume = v }
                    }
                    Text {
                        text: volRow.audio ? Math.round(volRow.audio.volume * 100) + "%" : "--"
                        font.family: Theme.font; font.pixelSize: Theme.fontSize
                        color: Theme.fg
                        Layout.preferredWidth: 38
                        horizontalAlignment: Text.AlignRight
                    }
                }

                // Network
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "NET"
                        font.family: Theme.font; font.pixelSize: Theme.fontSize
                        color: Theme.fg
                        Layout.preferredWidth: 42
                    }
                    Network {}
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.dim; opacity: 0.4 }

                // Power
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    PowerButton {
                        label: "Lock"
                        onActivated: { popup.visible = false; Quickshell.execDetached(["hyprlock"]) }
                    }
                    PowerButton {
                        label: "Logout"
                        confirm: true
                        onActivated: Quickshell.execDetached(["sh", "-c",
                            "uwsm check is-active >/dev/null 2>&1 && uwsm stop || hyprctl dispatch 'hl.dsp.exit()'"])
                    }
                    PowerButton {
                        label: "Reboot"
                        confirm: true
                        onActivated: Quickshell.execDetached(["systemctl", "reboot"])
                    }
                    PowerButton {
                        label: "Off"
                        confirm: true
                        onActivated: Quickshell.execDetached(["systemctl", "poweroff"])
                    }
                }
            }
        }
    }
}
