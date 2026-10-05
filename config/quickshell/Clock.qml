import Quickshell
import QtQuick

// Clock in the middle of the bar. Click it for the calendar.
Rectangle {
    id: root
    required property var window

    implicitWidth: label.implicitWidth + 24
    implicitHeight: 24
    radius: height / 2
    color: drop.open ? Theme.surface : (area.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")

    SystemClock { id: clock; precision: SystemClock.Minutes }

    Text {
        id: label
        anchors.centerIn: parent
        text: Qt.formatDateTime(clock.date, "ddd MMM d   HH:mm")
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        color: Theme.fg
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: drop.open = true
    }

    Dropdown {
        id: drop
        screen: root.window.screen
        barHeight: root.window.height
        alignCenter: true
        onVisibleChanged: if (visible) panel.reset()

        CalendarPanel { id: panel }
    }
}
