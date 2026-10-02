import Quickshell
import Quickshell.Io
import QtQuick

// Polls NetworkManager via nmcli. Click opens nmtui in your terminal.
Item {
    id: root
    property string status: "NET --"

    implicitWidth: label.implicitWidth
    implicitHeight: 20

    Process {
        id: proc
        command: ["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION", "device", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let result = "NET off"
                for (const line of text.trim().split("\n")) {
                    const [type, state, ...rest] = line.split(":")
                    if (state !== "connected") continue
                    if (type === "wifi") { result = "WIFI " + rest.join(":"); break }
                    if (type === "ethernet") result = "ETH"
                }
                root.status = result
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        text: root.status
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        color: root.status === "NET off" ? Theme.dim : Theme.fg
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Quickshell.execDetached([Theme.terminal, "-e", "nmtui"])
    }
}
