import Quickshell
import Quickshell.Wayland
import Quickshell.Bluetooth
import QtQuick
import QtQuick.Layouts

// Asks whether to trust a Bluetooth device when it connects without being trusted.
// A trusted device may reconnect on its own, so this is the moment to decide.
// "Not now" is remembered until the shell restarts; the device stays untrusted.
Scope {
    id: root

    property var declined: ({})

    readonly property var pending: (Bluetooth.defaultAdapter?.devices?.values ?? [])
        .filter(d => d.connected && !d.trusted && !declined[d.address])
    readonly property var device: pending[0] ?? null

    function decline(d) { declined = Object.assign({}, declined, { [d.address]: true }) }

    LazyLoader {
        active: root.device !== null

        PanelWindow {
            anchors { top: true }
            margins { top: 40 }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            implicitWidth: 380
            implicitHeight: card.implicitHeight
            color: "transparent"

            Rectangle {
                id: card
                width: parent.width
                implicitHeight: col.implicitHeight + 24
                radius: 8
                color: Theme.surface
                border.width: 1
                border.color: Theme.accent

                ColumnLayout {
                    id: col
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: "Trust this device?"
                        font.family: Theme.font; font.pixelSize: Theme.fontSize; font.bold: true
                        color: Theme.fg
                    }
                    Text {
                        Layout.fillWidth: true
                        // Device names come from the device, so they are shown as plain text
                        text: (root.device?.deviceName || root.device?.address || "") + " just connected."
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                        color: Theme.fg
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "A trusted device can reconnect without asking you."
                        wrapMode: Text.Wrap
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                        color: Theme.dim
                    }
                    Row {
                        spacing: 8
                        Repeater {
                            model: [
                                { label: "Trust", trust: true },
                                { label: "Not now", trust: false }
                            ]
                            Rectangle {
                                id: btn
                                required property var modelData
                                width: btnText.implicitWidth + 16
                                height: 24; radius: 4
                                color: modelData.trust ? Theme.accent : Theme.bg
                                Text {
                                    id: btnText
                                    anchors.centerIn: parent
                                    text: btn.modelData.label
                                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                                    color: btn.modelData.trust ? Theme.bg : Theme.accent
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (btn.modelData.trust) root.device.trusted = true
                                        else root.decline(root.device)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
