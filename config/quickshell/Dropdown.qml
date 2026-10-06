import Quickshell
import Quickshell.Wayland
import QtQuick

// Hosts a dropdown panel under the bar. It covers the whole screen with an invisible
// layer, so a click anywhere outside the panel (the bar included) or Escape closes it.
//
// Horizontal placement, in order of precedence: centred under `anchorItem` if one is set,
// otherwise alignCenter / alignRight / the left edge.
PanelWindow {
    id: root
    property bool open: false
    property bool alignRight: false
    property bool alignCenter: false
    property int barHeight: 30
    default property alias content: holder.data

    // The bar widget this panel belongs to, so the panel opens under the thing you clicked
    // rather than at a fixed edge. Both this window and the bar span the screen from x = 0,
    // so the widget's scene position is also its screen position.
    property Item anchorItem: null
    property real anchorCentre: 0
    readonly property int edgeMargin: 8

    // mapToItem is a function call, not a binding, so it's refreshed each time the panel
    // opens — the bar's own layout shifts as the clock text and the tray change width.
    function refreshAnchor() {
        if (anchorItem)
            anchorCentre = anchorItem.mapToItem(null, anchorItem.width / 2, 0).x
    }

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
        x: {
            if (root.anchorItem)
                // Centred on the widget, but never hanging off either edge of the screen
                return Math.max(root.edgeMargin,
                                Math.min(root.width - width - root.edgeMargin,
                                         root.anchorCentre - width / 2))
            if (root.alignCenter) return (root.width - width) / 2
            if (root.alignRight) return root.width - width - root.edgeMargin
            return root.edgeMargin
        }
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

    // Before the panel can paint, so it doesn't appear at a stale position and slide across
    onOpenChanged: if (open) refreshAnchor()
    onVisibleChanged: if (visible) { holder.forceActiveFocus(); appear.restart() }
}
