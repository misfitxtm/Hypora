import QtQuick
import QtQuick.Layouts

// If confirm is true, the first click arms it ("Sure?"); a second click within 3s fires it.
Rectangle {
    id: root
    property string label
    property bool confirm: false
    property bool armed: false
    signal activated()

    Layout.fillWidth: true
    implicitHeight: 32
    radius: 6
    color: armed ? Theme.error : Theme.bg

    Text {
        anchors.centerIn: parent
        text: root.armed ? "Sure?" : root.label
        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
        color: root.armed ? Theme.bg : Theme.fg
    }

    Timer { id: reset; interval: 3000; onTriggered: root.armed = false }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (root.confirm && !root.armed) { root.armed = true; reset.restart() }
            else { root.armed = false; root.activated() }
        }
    }
}
