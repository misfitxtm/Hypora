import QtQuick

// Round icon button. If confirm is true, the first click arms it (turns red);
// a second click within 3s fires it.
Rectangle {
    id: root
    property string icon
    property bool confirm: false
    property bool armed: false
    signal activated()

    implicitWidth: 36
    implicitHeight: 36
    radius: height / 2
    color: armed ? Theme.error : (area.containsMouse ? Qt.lighter(Theme.surface, 1.25) : Theme.surface)
    Behavior on color { ColorAnimation { duration: 120 } }

    Icon {
        anchors.centerIn: parent
        name: root.icon
        size: 16
        color: root.armed ? Theme.bg : Theme.fg
    }

    Timer { id: reset; interval: 3000; onTriggered: root.armed = false }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.confirm && !root.armed) { root.armed = true; reset.restart() }
            else { root.armed = false; root.activated() }
        }
    }
}
