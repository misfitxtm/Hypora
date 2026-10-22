import QtQuick

// Round icon button; with confirm, the first click arms it (red) and a second within 3s fires it.
Rectangle {
    id: root
    property string icon
    property bool confirm: false
    property bool armed: false
    signal activated()

    implicitWidth: 36
    implicitHeight: 36
    radius: Math.min(width, height) / 2
    color: armed ? Theme.error : (area.containsMouse ? Qt.lighter(Theme.surface, 1.25) : Theme.surface)
    Behavior on color { ColorAnimation { duration: 120 } }

    Icon {
        anchors.centerIn: parent
        name: root.icon
        size: 16
        color: root.armed ? Theme.bg : Theme.fg
    }

    Timer { id: reset; interval: 3000; onTriggered: root.armed = false }

    // Arming is exclusive across the row, or two buttons could stay red and the hint could name the wrong action.
    function disarmSiblings() {
        if (!parent) return
        for (let i = 0; i < parent.children.length; i++) {
            const sib = parent.children[i]
            if (sib !== root && sib.armed !== undefined) sib.armed = false
        }
    }

    onArmedChanged: if (armed) disarmSiblings()
    // Disarm on close so a reopened panel is not one click from an old accidental arm.
    onVisibleChanged: if (!visible) armed = false

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // Moving to another button means a change of mind, so stand this one down at once.
        onEntered: root.disarmSiblings()
        onClicked: {
            if (root.confirm && !root.armed) { root.armed = true; reset.restart() }
            else { root.armed = false; root.activated() }
        }
    }
}
