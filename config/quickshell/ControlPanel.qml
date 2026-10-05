import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts

// Contents of the control center dropdown (GNOME / macOS style quick settings).
Rectangle {
    id: root
    signal closeRequested()

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink ? sink.audio : null
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var battery: UPower.displayDevice

    // PowerProfiles reports Balanced even without a daemon; check the daemon is really there
    property bool profilesAvailable: false
    Process {
        command: ["sh", "-c", "busctl --system status org.freedesktop.UPower.PowerProfiles >/dev/null 2>&1 "
                            + "|| busctl --system status net.hadess.PowerProfiles >/dev/null 2>&1"]
        running: true
        onExited: code => root.profilesAvailable = code === 0
    }

    // Which power button is waiting for its second click, for the hint text
    property string armedHint: lock.armed ? "" : logout.armed ? "Click again to log out"
                             : reboot.armed ? "Click again to restart" : off.armed ? "Click again to power off" : ""

    implicitWidth: 360
    implicitHeight: layout.implicitHeight + 32
    radius: 18
    color: Theme.bg
    border.width: 1
    border.color: Theme.surface

    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    // ---- Brightness (only when a backlight exists; needs brightnessctl) ----
    property real brightness: -1
    Process {
        id: readBrightness
        command: ["brightnessctl", "-c", "backlight", "-m"]
        running: true
        // Output: device,class,current,percent%,max
        stdout: StdioCollector {
            onStreamFinished: {
                const pct = parseInt((text.split(",")[3] ?? ""))
                root.brightness = isNaN(pct) ? -1 : pct / 100
            }
        }
    }
    function setBrightness(v) {
        brightness = v
        Quickshell.execDetached(["brightnessctl", "-c", "backlight", "set", Math.max(1, Math.round(v * 100)) + "%"])
    }

    // ---- Night light (hyprsunset) ----
    property bool hasSunset: false
    Process {
        command: ["sh", "-c", "command -v hyprsunset"]
        running: true
        onExited: code => root.hasSunset = code === 0
    }
    Process {
        id: sunset
        command: ["hyprsunset", "-t", "4500"]
    }

    ColumnLayout {
        id: layout
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        spacing: 16

        // Session buttons, spread across the full width
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            PowerButton {
                id: lock
                Layout.fillWidth: true
                icon: "lock"
                onActivated: { root.closeRequested(); Quickshell.execDetached(["hyprlock"]) }
            }
            PowerButton {
                id: logout
                Layout.fillWidth: true
                icon: "logout"; confirm: true
                onActivated: Quickshell.execDetached(["sh", "-c",
                    "uwsm check is-active >/dev/null 2>&1 && uwsm stop || hyprctl dispatch 'hl.dsp.exit()'"])
            }
            PowerButton {
                id: reboot
                Layout.fillWidth: true
                icon: "reboot"; confirm: true
                onActivated: Quickshell.execDetached(["systemctl", "reboot"])
            }
            PowerButton {
                id: off
                Layout.fillWidth: true
                icon: "power"; confirm: true
                onActivated: Quickshell.execDetached(["systemctl", "poweroff"])
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: -8
            visible: root.armedHint !== ""
            text: root.armedHint
            font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
            color: Theme.error
        }

        // Sliders
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Icon {
                name: "volume"
                level: !root.audio || root.audio.muted ? 0 : root.audio.volume
                size: 18
                color: root.audio && !root.audio.muted ? Theme.fg : Theme.dim
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.audio) root.audio.muted = !root.audio.muted
                }
            }
            Slider {
                Layout.fillWidth: true
                value: root.audio ? root.audio.volume : 0
                onMoved: v => { if (root.audio) { root.audio.volume = v; root.audio.muted = false } }
            }
            // Full mixer (outputs, inputs, per-app volume)
            Icon {
                name: "sliders"
                size: 16
                color: mixerArea.containsMouse ? Theme.accent : Theme.dim
                MouseArea {
                    id: mixerArea
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.closeRequested(); Apps.inTerminal(Theme.mixer) }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            visible: root.brightness >= 0
            spacing: 12
            Icon { name: "sun"; size: 18 }
            Slider {
                Layout.fillWidth: true
                value: root.brightness
                onMoved: v => root.setBrightness(v)
            }
        }

        // Power mode (power-profiles-daemon / tuned-ppd)
        Row {
            Layout.fillWidth: true
            visible: root.profilesAvailable
            spacing: 6
            Repeater {
                model: [
                    { label: "Saver", value: PowerProfile.PowerSaver },
                    { label: "Balanced", value: PowerProfile.Balanced },
                    { label: "Performance", value: PowerProfile.Performance }
                ]
                Rectangle {
                    id: seg
                    required property var modelData
                    readonly property bool current: PowerProfiles.profile === modelData.value
                    visible: modelData.value !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile
                    readonly property int count: PowerProfiles.hasPerformanceProfile ? 3 : 2
                    width: (parent.width - parent.spacing * (count - 1)) / count
                    height: 32
                    radius: height / 2
                    color: current ? Theme.accent : (segArea.containsMouse ? Qt.lighter(Theme.surface, 1.25) : Theme.surface)
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "zap"
                            size: 13
                            visible: seg.current
                            color: Theme.bg
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: seg.modelData.label
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 2; font.bold: seg.current
                            color: seg.current ? Theme.bg : Theme.fg
                        }
                    }
                    MouseArea {
                        id: segArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: PowerProfiles.profile = seg.modelData.value
                    }
                }
            }
        }

        // Toggle tiles
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 10
            rowSpacing: 10

            Tile {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: Net.hasWifi ? (Net.wifiEnabled ? "wifi" : "wifi-off") : Net.icon
                title: Net.hasWifi ? "Wi-Fi" : "Network"
                subtitle: Net.type === "wifi" ? Net.ssid
                        : Net.type === "ethernet" ? "Wired"
                        : Net.hasWifi && !Net.wifiEnabled ? "Off" : "Disconnected"
                active: Net.hasWifi ? Net.wifiEnabled : Net.type !== ""
                hasMenu: true
                onToggled: {
                    if (Net.hasWifi) Net.setWifiEnabled(!Net.wifiEnabled)
                    else menu()
                }
                onMenu: { root.closeRequested(); ShellState.networkSettingsOpen = true }
            }
            Tile {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: "bluetooth"
                title: "Bluetooth"
                available: root.adapter !== null
                active: root.adapter?.enabled ?? false
                subtitle: !root.adapter ? "Unavailable" : root.adapter.enabled ? "On" : "Off"
                hasMenu: root.adapter !== null
                onToggled: root.adapter.enabled = !root.adapter.enabled
                onMenu: { root.closeRequested(); ShellState.bluetoothSettingsOpen = true }
            }
            Tile {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: ShellState.dnd ? "bell-off" : "bell"
                title: "Do Not Disturb"
                subtitle: ShellState.dnd ? "On" : "Off"
                active: ShellState.dnd
                onToggled: ShellState.dnd = !ShellState.dnd
            }
            Tile {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: "moon"
                title: "Night Light"
                available: root.hasSunset
                active: sunset.running
                subtitle: !root.hasSunset ? "Unavailable" : sunset.running ? "On" : "Off"
                onToggled: sunset.running = !sunset.running
            }
        }
    }
}
