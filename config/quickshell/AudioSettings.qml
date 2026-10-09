import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts

// Sound: output and input devices, and the volume of each app that's playing.
// Talks to PipeWire directly through Quickshell, so there's no pavucontrol here. The
// wiremix TUI is still one click away under "Advanced" for anything this doesn't cover.
// Open from the menu (Settings > Sound), the control centre's mixer button, or:
//     qs ipc call audio open
Scope {
    id: root

    IpcHandler {
        target: "audio"
        function open(): void { ShellState.audioSettingsOpen = true }
        function close(): void { ShellState.audioSettingsOpen = false }
    }

    LazyLoader {
        active: ShellState.audioSettingsOpen

        FloatingWindow {
            id: win
            title: "Sound"
            implicitWidth: 560
            implicitHeight: 660
            color: Theme.bg
            onClosed: ShellState.audioSettingsOpen = false

            readonly property var sinks: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioSink && !n.isStream)
            readonly property var sources: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioSource && !n.isStream)
            // Anything currently playing: one row per app
            readonly property var streams: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioOutStream)

            readonly property var defaultSink: Pipewire.defaultAudioSink
            readonly property var defaultSource: Pipewire.defaultAudioSource

            // Volume is only readable once a node is tracked, so track everything on show
            PwObjectTracker {
                objects: win.sinks.concat(win.sources).concat(win.streams)
            }

            function label(node) {
                return node.description || node.nickname || node.name || "Unknown device"
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.bg

                ColumnLayout {
                    anchors { fill: parent; margins: 22 }
                    spacing: 12

                    Text {
                        text: "Sound"
                        font.family: Theme.font; font.pixelSize: Theme.fontSize + 9; font.bold: true
                        color: Theme.fg
                    }

                    Flickable {
                        id: scroller
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        // Page Up / Page Down without reaching for the mouse. focus here
                        // is safe: this window has no text input to compete with.
                        focus: true
                        Keys.onPressed: event => event.accepted = PageScroll.handle(event, scroller)
                        clip: true
                        contentHeight: body.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: body
                            width: parent.width
                            spacing: 4

                            // ---------- output ----------
                            Heading { text: "Output" }
                            VolumeRow {
                                node: win.defaultSink
                                icon: "volume"
                                caption: win.defaultSink ? win.label(win.defaultSink) : "No output device"
                            }
                            Repeater {
                                model: win.sinks.length > 1 ? win.sinks : []
                                DeviceRow {
                                    required property var modelData
                                    node: modelData
                                    current: win.defaultSink && modelData.id === win.defaultSink.id
                                    text: win.label(modelData)
                                    onPicked: Pipewire.preferredDefaultAudioSink = modelData
                                }
                            }

                            // ---------- input ----------
                            Heading { text: "Input" }
                            VolumeRow {
                                node: win.defaultSource
                                icon: "mic"
                                caption: win.defaultSource ? win.label(win.defaultSource) : "No input device"
                            }
                            Repeater {
                                model: win.sources.length > 1 ? win.sources : []
                                DeviceRow {
                                    required property var modelData
                                    node: modelData
                                    current: win.defaultSource && modelData.id === win.defaultSource.id
                                    text: win.label(modelData)
                                    onPicked: Pipewire.preferredDefaultAudioSource = modelData
                                }
                            }

                            // ---------- per-app ----------
                            Heading { text: "Applications" }
                            Text {
                                Layout.fillWidth: true
                                Layout.leftMargin: 12
                                Layout.bottomMargin: 8
                                visible: win.streams.length === 0
                                text: "Nothing is playing."
                                font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                                color: Theme.dim
                            }
                            Repeater {
                                model: win.streams
                                VolumeRow {
                                    required property var modelData
                                    node: modelData
                                    icon: "volume"
                                    caption: modelData.properties
                                        ? (modelData.properties["application.name"] || win.label(modelData))
                                        : win.label(modelData)
                                }
                            }

                            // The TUI covers routing, profiles and anything else
                            Item { Layout.preferredHeight: 10 }
                            Text {
                                Layout.alignment: Qt.AlignRight
                                Layout.rightMargin: 4
                                text: "Advanced…"
                                font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                                color: advArea.containsMouse ? Theme.accent : Theme.dim
                                MouseArea {
                                    id: advArea
                                    anchors { fill: parent; margins: -6 }
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        ShellState.audioSettingsOpen = false
                                        Apps.inTerminal(Theme.mixer)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---------- pieces ----------
            component Heading: Text {
                Layout.topMargin: 14
                Layout.leftMargin: 4
                Layout.bottomMargin: 2
                font.family: Theme.font; font.pixelSize: Theme.fontSize - 3; font.bold: true
                font.capitalization: Font.AllUppercase; font.letterSpacing: 1
                color: Theme.dim
            }

            // A device or app with its own volume slider and mute
            component VolumeRow: Rectangle {
                id: vr
                property var node: null
                property string icon: "volume"
                property string caption: ""
                readonly property var audio: node ? node.audio : null

                Layout.fillWidth: true
                implicitHeight: 62
                radius: 10
                color: Theme.surface
                opacity: audio ? 1 : 0.55

                Icon {
                    id: vrIcon
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    name: vr.audio && vr.audio.muted ? (vr.icon === "mic" ? "mic-off" : "volume") : vr.icon
                    level: vr.audio && !vr.audio.muted ? vr.audio.volume : 0
                    size: 18
                    color: vr.audio && !vr.audio.muted ? Theme.accent : Theme.dim
                    MouseArea {
                        anchors { fill: parent; margins: -8 }
                        enabled: vr.audio !== null
                        cursorShape: Qt.PointingHandCursor
                        onClicked: vr.audio.muted = !vr.audio.muted
                    }
                }
                Text {
                    id: vrLabel
                    anchors { left: vrIcon.right; right: vrPct.left; leftMargin: 14; rightMargin: 10; top: parent.top; topMargin: 11 }
                    text: vr.caption
                    elide: Text.ElideRight
                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                    color: Theme.fg
                }
                Text {
                    id: vrPct
                    anchors { right: parent.right; rightMargin: 14; baseline: vrLabel.baseline }
                    text: vr.audio ? Math.round(vr.audio.volume * 100) + "%" : "--"
                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                    color: Theme.dim
                }
                Slider {
                    anchors { left: vrIcon.right; right: parent.right; leftMargin: 14; rightMargin: 14; bottom: parent.bottom; bottomMargin: 10 }
                    enabled: vr.audio !== null
                    value: vr.audio ? vr.audio.volume : 0
                    onMoved: v => { if (vr.audio) { vr.audio.volume = v; vr.audio.muted = false } }
                }
            }

            // One of several devices, picked to be the default
            component DeviceRow: Rectangle {
                id: dr
                property var node: null
                property bool current: false
                property string text: ""
                signal picked()

                Layout.fillWidth: true
                Layout.leftMargin: 12
                implicitHeight: 34
                radius: 8
                color: drArea.containsMouse ? Theme.surface : "transparent"

                Rectangle {
                    id: drDot
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    width: 12; height: 12; radius: 6
                    color: dr.current ? Theme.accent : "transparent"
                    border.width: dr.current ? 0 : 1.5
                    border.color: Theme.dim
                }
                Text {
                    anchors { left: drDot.right; right: parent.right; leftMargin: 12; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    text: dr.text
                    elide: Text.ElideRight
                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                    color: dr.current ? Theme.fg : Theme.dim
                }
                MouseArea {
                    id: drArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: dr.picked()
                }
            }
        }
    }
}
