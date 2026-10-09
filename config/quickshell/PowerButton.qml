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

    // Arming is exclusive across the row. Each button used to hold its own state with no
    // coordination, so arming Power off and then moving to Restart left two buttons red at
    // once for the full three seconds. That is not only untidy: the hint underneath picks
    // the first armed button it finds, so it could name a different action than the one the
    // next click would actually run.
    //
    // Done by walking the siblings rather than by wiring the four buttons together in
    // ControlPanel, so the component stays self-contained and a fifth button needs no
    // bookkeeping. Anything in the row without an `armed` property is skipped.
    function disarmSiblings() {
        if (!parent) return
        for (let i = 0; i < parent.children.length; i++) {
            const sib = parent.children[i]
            if (sib !== root && sib.armed !== undefined) sib.armed = false
        }
    }

    onArmedChanged: if (armed) disarmSiblings()
    // Closing the panel with a button still armed would leave it armed on reopen, one click
    // away from firing something you armed by accident a while ago.
    onVisibleChanged: if (!visible) armed = false

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // Moving to another button is the clearest signal that you changed your mind, so it
        // stands the armed one down rather than waiting out its timer.
        onEntered: root.disarmSiblings()
        onClicked: {
            if (root.confirm && !root.armed) { root.armed = true; reset.restart() }
            else { root.armed = false; root.activated() }
        }
    }
}
