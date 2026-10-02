import QtQuick

// Minimal horizontal slider. value is 0..1; emits moved(v) while dragging.
Item {
    id: root
    property real value: 0
    signal moved(real v)

    implicitHeight: 20

    Rectangle {
        id: track
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        height: 6; radius: 3
        color: Theme.bg

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.value))
            height: parent.height; radius: 3
            color: Theme.accent
        }
    }

    MouseArea {
        anchors.fill: parent
        function update(x) { root.moved(Math.max(0, Math.min(1, x / width))) }
        onPressed: m => update(m.x)
        onPositionChanged: m => { if (pressed) update(m.x) }
    }
}
