import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick

// The slider that appears at the bottom of the screen when you press a volume or
// brightness key, and goes away again.
//
// The two halves are driven differently, because the two sources are different:
//
//   Volume comes from PipeWire as a property, so it is simply watched. That costs nothing
//   and means the slider also appears when the volume changes from somewhere else — the
//   scroll wheel over the bar icon, or the control center.
//
//   Brightness has no such thing. The kernel exposes it as a sysfs file, and sysfs does not
//   reliably raise inotify events, so watching it would mean polling a file several times a
//   second forever to catch a keypress. Instead the keybind says so: hyprland.lua calls
//   `qs ipc call osd brightness` right after brightnessctl, and this reads the value once,
//   when it is actually wanted.
//
// Brightness is only wired up where there is a backlight to dim. A desktop has an empty
// /sys/class/backlight, and a slider that cannot move is worse than no slider.
Scope {
    id: root

    property bool visible: false
    property string icon: "volume"
    property real value: 0          // 0..1, drives both the bar and the icon's own level
    property string label: ""
    property bool hasBacklight: false

    // Nothing should appear during startup just because the values were read for the first
    // time. PipeWire publishes the current volume as soon as it connects, which without
    // this would flash the slider on every login.
    property bool ready: false
    Component.onCompleted: settle.start()
    Timer { id: settle; interval: 1500; onTriggered: root.ready = true }

    function show(icon, value, label) {
        if (!ready) return
        root.icon = icon
        root.value = Math.max(0, Math.min(1, value))
        root.label = label
        root.visible = true
        hide.restart()
    }

    Timer { id: hide; interval: 1600; onTriggered: root.visible = false }

    IpcHandler {
        target: "osd"
        // Called by the brightness keybinds, after brightnessctl has already applied the
        // change — so reading now gets the new value rather than the old one.
        function brightness(): void { if (root.hasBacklight) readBrightness.running = true }
        function volume(): void { root.showVolume() }
    }

    // ---------- backlight ----------

    Process {
        id: detect
        running: true
        command: ["sh", "-c", "ls -1 /sys/class/backlight 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: root.hasBacklight = text.trim() !== ""
        }
    }

    Process {
        id: readBrightness
        // -m is the machine-readable form: device,class,current,percent,max
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("\n")[0].split(",")
                if (parts.length < 5) return
                const cur = parseFloat(parts[2])
                const max = parseFloat(parts[4])
                if (!(max > 0)) return
                // "sun", because that is the glyph Icon.qml has; there is no
                // separate brightness one and inventing a name would draw nothing.
                root.show("sun", cur / max, Math.round(cur / max * 100) + "%")
            }
        }
    }

    // ---------- volume ----------

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink ? sink.audio : null
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    function showVolume() {
        if (!audio) return
        // One name, not two: Icon.qml draws the crossed-out speaker itself when level
        // reaches zero, which is how the bar indicator shows muting too.
        show("volume",
             audio.muted ? 0 : audio.volume,
             audio.muted ? "Muted" : Math.round(audio.volume * 100) + "%")
    }

    Connections {
        target: root.audio
        ignoreUnknownSignals: true
        function onVolumeChanged() { root.showVolume() }
        function onMutedChanged() { root.showVolume() }
    }

    // ---------- the slider ----------

    LazyLoader {
        active: root.visible

        PanelWindow {
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
            anchors { bottom: true; left: true; right: true }
            implicitHeight: 120
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            // Explicitly none: this is a readout, and taking the keyboard would swallow the
            // next press of the very key that raised it.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "hypora-osd"
            color: "transparent"
            mask: Region {}        // clicks pass straight through to whatever is beneath

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 28
                width: 260
                height: 56
                radius: 14
                color: Theme.bg
                border.width: 1
                border.color: Theme.surface

                opacity: root.visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }

                Icon {
                    id: osdIcon
                    anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                    name: root.icon
                    level: root.value
                    size: 20
                    color: root.value > 0 ? Theme.accent : Theme.dim
                }

                Rectangle {
                    id: track
                    anchors {
                        left: osdIcon.right; leftMargin: 16
                        right: pct.left; rightMargin: 16
                        verticalCenter: parent.verticalCenter
                    }
                    height: 6
                    radius: 3
                    color: Theme.surface

                    Rectangle {
                        width: parent.width * root.value
                        height: parent.height
                        radius: parent.radius
                        color: Theme.accent
                        Behavior on width { NumberAnimation { duration: 90 } }
                    }
                }

                Text {
                    id: pct
                    anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                    text: root.label
                    // Fixed width so the slider doesn't shuffle sideways as the number
                    // changes width between 9% and 100%
                    width: 42
                    horizontalAlignment: Text.AlignRight
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.fg
                }
            }
        }
    }
}
