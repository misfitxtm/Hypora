import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

// This IS the notification daemon. Disable mako/dunst/swaync or they will conflict.
Scope {
    NotificationServer {
        id: server
        bodySupported: true
        actionsSupported: true
        keepOnReload: true
        onNotification: n => { n.tracked = true }
    }

    // With Do Not Disturb on, only critical notifications pop up
    function shown(n) { return !ShellState.dnd || n.urgency === NotificationUrgency.Critical }

    PanelWindow {
        visible: server.trackedNotifications.values.some(n => shown(n))
        anchors { top: true; right: true }
        margins { top: 40; right: 12 }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        implicitWidth: 380
        implicitHeight: stack.implicitHeight
        color: "transparent"

        ColumnLayout {
            id: stack
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: 8

            Repeater {
                model: server.trackedNotifications

                Rectangle {
                    id: card
                    required property var modelData
                    readonly property bool critical: modelData.urgency === NotificationUrgency.Critical
                    // Sent image, then the app's icon (name or path), then its desktop entry's icon
                    readonly property string iconSource: {
                        if (modelData.image) return modelData.image
                        const name = modelData.appIcon
                            || (DesktopEntries.heuristicLookup(modelData.desktopEntry || modelData.appName)?.icon ?? "")
                        if (name.startsWith("/")) return "file://" + name
                        return Quickshell.iconPath(name || "dialog-information", "dialog-information")
                    }

                    Layout.fillWidth: true
                    visible: shown(modelData)
                    implicitHeight: Math.max(content.implicitHeight, icon.implicitHeight) + 24
                    radius: 8
                    color: Theme.surface
                    border.width: 1
                    border.color: critical ? Theme.error : Theme.accent

                    // Auto-expire (never for critical). expireTimeout is in seconds; <=0 means default.
                    Timer {
                        interval: card.modelData.expireTimeout > 0 ? card.modelData.expireTimeout * 1000 : 6000
                        running: !card.critical
                        onTriggered: card.modelData.expire()
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: card.modelData.dismiss()
                    }

                    // The theme has no Claude icon, so Hypora's own logo stands in
                    readonly property bool isClaude: /claude/i.test(modelData.appName + modelData.appIcon)

                    Item {
                        id: icon
                        anchors { left: parent.left; top: parent.top; margins: 12 }
                        implicitWidth: 40; implicitHeight: 40
                        IconImage {
                            anchors.fill: parent
                            visible: !card.isClaude
                            source: card.iconSource
                        }
                        Icon {
                            anchors.centerIn: parent
                            visible: card.isClaude
                            name: "claude"; size: 32; color: Theme.accent
                        }
                    }

                    ColumnLayout {
                        id: content
                        anchors { left: icon.right; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 4

                        Text {
                            text: card.modelData.appName
                            textFormat: Text.PlainText
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                            color: Theme.dim
                        }
                        Text {
                            Layout.fillWidth: true
                            text: card.modelData.summary
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            font.family: Theme.font; font.pixelSize: Theme.fontSize; font.bold: true
                            color: Theme.fg
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            // Apps may send <b>, <i>, <u> and <br>. Any other "<" is escaped so it shows as
                            // text: StyledText would otherwise fetch an <img src="http://..."> from
                            // the network the moment the notification appears, even unterminated.
                            text: card.modelData.body.replace(/<(?!\/?(?:b|i|u|br)\s*\/?>)/gi, "&lt;")
                            textFormat: Text.StyledText
                            wrapMode: Text.Wrap
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                            color: Theme.fg
                        }
                        Row {
                            spacing: 8
                            Repeater {
                                model: card.modelData.actions
                                Rectangle {
                                    id: btn
                                    required property var modelData
                                    width: actionText.implicitWidth + 16
                                    height: 24; radius: 4
                                    color: Theme.bg
                                    Text {
                                        id: actionText
                                        anchors.centerIn: parent
                                        text: btn.modelData.text
                                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                                        color: Theme.accent
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: btn.modelData.invoke()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
