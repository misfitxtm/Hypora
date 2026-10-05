import Quickshell
import Quickshell.Wayland
import QtQuick

// Hosts a dropdown panel under the bar. It covers the whole screen with an invisible
// layer, so a click anywhere outside the panel (the bar included) or Escape closes it.
PanelWindow {
    id: root
    property bool open: false
    property bool alignRight: false
    property int barHeight: 30
    default property alias content: holder.data

    visible: open
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "hypora-dropdown"
    color: "transparent"

    // Outside the panel: close
    MouseArea {
        anchors.fill: parent
        onClicked: root.open = false
    }
    // Inside the panel: swallow clicks that no control handled
    MouseArea {
        x: holder.x; y: holder.y
        width: holder.width; height: holder.height
    }

    FocusScope {
        id: holder
        x: root.alignRight ? root.width - width - 8 : 8
        y: root.barHeight + 6
        width: childrenRect.width
        height: childrenRect.height
        focus: true
        Keys.onEscapePressed: root.open = false

        // Slide and fade in when opened
        opacity: 0
        transform: Translate { id: slide }
        ParallelAnimation {
            id: appear
            NumberAnimation { target: holder; property: "opacity"; from: 0; to: 1; duration: 140 }
            NumberAnimation { target: slide; property: "y"; from: -8; to: 0; duration: 160; easing.type: Easing.OutCubic }
        }
    }

    onVisibleChanged: if (visible) { holder.forceActiveFocus(); appear.restart() }
}
