import Quickshell.Services.UPower
import QtQuick

Item {
    visible: UPower.displayDevice.isLaptopBattery
    implicitWidth: label.implicitWidth
    implicitHeight: 20

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        text: "BAT " + Math.round(UPower.displayDevice.percentage * 100) + "%"
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        color: UPower.displayDevice.percentage < 0.15 ? Theme.error : Theme.fg
    }
}
