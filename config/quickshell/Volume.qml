import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// Scroll = volume, left click = mute, right click = mixer
Item {
    id: root
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink ? sink.audio : null

    implicitWidth: label.implicitWidth
    implicitHeight: 20

    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        text: !root.audio ? "VOL --"
              : root.audio.muted ? "VOL muted"
              : "VOL " + Math.round(root.audio.volume * 100) + "%"
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        color: root.audio && root.audio.muted ? Theme.dim : Theme.fg
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: m => {
            if (m.button === Qt.RightButton) Quickshell.execDetached([Theme.mixer])
            else if (root.audio) root.audio.muted = !root.audio.muted
        }
        onWheel: w => {
            if (!root.audio) return
            const step = w.angleDelta.y > 0 ? 0.05 : -0.05
            root.audio.volume = Math.max(0, Math.min(1, root.audio.volume + step))
        }
    }
}
