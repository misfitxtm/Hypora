import Quickshell
import QtQuick

// System usage in the bar, left of the control center: RAM, CPU and temperatures.
// Click it to choose which readings to show; the choice is remembered.
Rectangle {
    id: root
    required property var window

    readonly property var visibleItems: SysInfo.items.filter(i => i.available && SysInfo.enabled(i.key))

    implicitWidth: visibleItems.length > 0 ? readings.implicitWidth + 16 : 0
    implicitHeight: 24
    visible: SysInfo.ready && visibleItems.length > 0
    radius: height / 2
    color: drop.open ? Theme.surface : (area.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: drop.open = true
    }

    Row {
        id: readings
        anchors.centerIn: parent
        spacing: 10

        Repeater {
            model: root.visibleItems

            Row {
                required property var modelData
                spacing: 4

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: parent.modelData.icon
                    size: 14
                    color: SysInfo.tone(parent.modelData.key)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: SysInfo.value(parent.modelData.key)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    color: SysInfo.tone(parent.modelData.key)
                    // Keep the bar from twitching as the numbers change width
                    horizontalAlignment: Text.AlignRight
                    width: Math.max(implicitWidth, 26)
                }
            }
        }
    }

    Dropdown {
        id: drop
        screen: root.window.screen
        barHeight: root.window.height
        alignRight: true

        Rectangle {
            implicitWidth: 260
            implicitHeight: menu.implicitHeight + 28
            radius: 16
            color: Theme.bg
            border.width: 1
            border.color: Theme.surface

            Column {
                id: menu
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 2

                Text {
                    leftPadding: 8
                    bottomPadding: 8
                    text: "Show in the bar"
                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 2; font.bold: true
                    font.capitalization: Font.AllUppercase; font.letterSpacing: 1
                    color: Theme.dim
                }

                Repeater {
                    model: SysInfo.items

                    Rectangle {
                        id: row
                        required property var modelData
                        readonly property bool on: SysInfo.enabled(modelData.key)

                        width: parent.width
                        height: modelData.available ? 36 : 0
                        visible: modelData.available
                        radius: 8
                        color: rowArea.containsMouse ? Theme.surface : "transparent"

                        Icon {
                            id: rowIcon
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            name: row.modelData.icon
                            size: 15
                            color: row.on ? Theme.accent : Theme.dim
                        }
                        Text {
                            anchors { left: rowIcon.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            text: row.modelData.label
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                            color: row.on ? Theme.fg : Theme.dim
                        }
                        Text {
                            anchors { right: check.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: SysInfo.value(row.modelData.key)
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                            color: Theme.dim
                        }
                        // Checkbox
                        Rectangle {
                            id: check
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            width: 18; height: 18; radius: 5
                            color: row.on ? Theme.accent : "transparent"
                            border.width: row.on ? 0 : 1.5
                            border.color: Theme.dim
                            Text {
                                anchors.centerIn: parent
                                visible: row.on
                                text: "✓"
                                font.family: Theme.font; font.pixelSize: 12; font.bold: true
                                color: Theme.bg
                            }
                        }
                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: SysInfo.toggle(row.modelData.key)
                        }
                    }
                }

                // Memory and GPU detail, when there is something worth adding
                Text {
                    topPadding: 8
                    leftPadding: 8
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: {
                        const bits = []
                        if (SysInfo.ram) bits.push("RAM " + SysInfo.detail("ram"))
                        if (SysInfo.gpu && SysInfo.gpu.name) bits.push("GPU " + SysInfo.gpu.name)
                        return bits.join("   ")
                    }
                    visible: text !== ""
                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
                    color: Theme.dim
                }
            }
        }
    }
}
