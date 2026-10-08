import Quickshell.Services.UPower
import QtQuick

// Bar indicator, shown on laptops only. Turns red when low.
//
// Reads a real battery out of UPower.devices in preference to the DisplayDevice composite,
// and shows nothing rather than a number it cannot stand behind. An earlier version read
// the composite unguarded, so a device that was present but not yet populated rendered its
// defaults as fact — a bar sitting at 100% while the battery drained.
Row {
    id: root
    readonly property var dev: {
        const real = (UPower.devices?.values ?? []).find(d => d && d.isLaptopBattery && d.ready)
        return real ?? UPower.displayDevice
    }
    readonly property bool valid: dev !== null && dev !== undefined
                                  && dev.ready === true && dev.isLaptopBattery === true
    readonly property real pct: valid ? dev.percentage : 0
    readonly property bool charging: valid && dev.state === UPowerDeviceState.Charging
    readonly property bool low: valid && pct < 0.15 && !charging

    visible: valid
    spacing: 4

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: "battery"
        level: root.pct
        charging: root.charging
        size: 17
        color: root.low ? Theme.error : Theme.fg
    }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(root.pct * 100) + "%"
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
        color: root.low ? Theme.error : Theme.fg
    }
}
