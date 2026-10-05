import QtQuick

// Horizontal slider with a round knob. value is 0..1; emits moved(v) while dragging.
Item {
    id: root
    property real value: 0
    signal moved(real v)

    readonly property real clamped: Math.max(0, Math.min(1, value))
    implicitHeight: 22

    Rectangle {
        id: track
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        height: 6; radius: 3
        color: Theme.surface

        Rectangle {
            width: knob.x + knob.width / 2
            height: parent.height; radius: 3
            color: Theme.accent
        }
    }

    Rectangle {
        id: knob
        width: 16; height: 16; radius: 8
        anchors.verticalCenter: parent.verticalCenter
        x: root.clamped * (root.width - width)
        color: Theme.fg
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        function update(x) { root.moved(Math.max(0, Math.min(1, (x - knob.width / 2) / (width - knob.width)))) }
        onPressed: m => update(m.x)
        onPositionChanged: m => { if (pressed) update(m.x) }
        onWheel: w => root.moved(Math.max(0, Math.min(1, root.clamped + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
