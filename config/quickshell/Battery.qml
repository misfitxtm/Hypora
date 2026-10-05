import Quickshell.Services.UPower
import QtQuick

// Bar indicator, shown on laptops only. Turns red when low.
Row {
    readonly property var dev: UPower.displayDevice
    readonly property bool low: dev.percentage < 0.15 && !charging
    readonly property bool charging: dev.state === UPowerDeviceState.Charging

    visible: dev.isLaptopBattery
    spacing: 4

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: "battery"
        level: parent.dev.percentage
        charging: parent.charging
        size: 17
        color: parent.low ? Theme.error : Theme.fg
    }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(parent.dev.percentage * 100) + "%"
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
        color: parent.low ? Theme.error : Theme.fg
    }
}
