import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// Bar indicator. Scroll over it to change volume; clicks go to the control center.
Icon {
    id: root
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink ? sink.audio : null

    name: "volume"
    level: !audio || audio.muted ? 0 : audio.volume
    size: 15
    color: !audio || audio.muted ? Theme.dim : Theme.fg

    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -4
        acceptedButtons: Qt.NoButton
        onWheel: w => {
            if (!root.audio) return
            const step = w.angleDelta.y > 0 ? 0.05 : -0.05
            root.audio.volume = Math.max(0, Math.min(1, root.audio.volume + step))
        }
    }
}
