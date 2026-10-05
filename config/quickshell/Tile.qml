import QtQuick

// Quick-settings toggle tile (GNOME style). Click toggles; the optional chevron
// on the right opens more settings.
Rectangle {
    id: root
    property string icon
    property string title
    property string subtitle
    property bool active: false
    property bool available: true
    property bool hasMenu: false
    signal toggled()
    signal menu()

    readonly property color ink: active ? Theme.bg : Theme.fg

    implicitHeight: 56
    radius: height / 2
    color: active ? Theme.accent : (main.containsMouse && available ? Qt.lighter(Theme.surface, 1.25) : Theme.surface)
    opacity: available ? 1 : 0.5
    Behavior on color { ColorAnimation { duration: 120 } }

    MouseArea {
        id: main
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: root.hasMenu ? divider.left : parent.right }
        enabled: root.available
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }

    Icon {
        id: glyph
        anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
        name: root.icon
        level: 1
        size: 18
        color: root.ink
    }

    Column {
        anchors {
            left: glyph.right; leftMargin: 12
            right: root.hasMenu ? divider.left : parent.right; rightMargin: 10
            verticalCenter: parent.verticalCenter
        }
        Text {
            width: parent.width
            text: root.title
            elide: Text.ElideRight
            font.family: Theme.font; font.pixelSize: Theme.fontSize - 1; font.bold: true
            color: root.ink
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: root.subtitle
            elide: Text.ElideRight
            font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
            color: root.ink
            opacity: 0.75
        }
    }

    Rectangle {
        id: divider
        visible: root.hasMenu
        anchors { right: parent.right; rightMargin: 40; verticalCenter: parent.verticalCenter }
        width: 1; height: parent.height - 24
        color: root.ink
        opacity: 0.25
    }

    MouseArea {
        visible: root.hasMenu
        anchors { left: divider.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        cursorShape: Qt.PointingHandCursor
        onClicked: root.menu()
        Icon {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -2
            name: "chevron"
            size: 16
            color: root.ink
        }
    }
}
