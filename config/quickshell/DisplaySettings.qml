import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as C

// Display Settings: resolution, refresh rate, scale, rotation, position and on/off per monitor.
// Changes apply live (hyprctl eval), then ask to be kept; after 15s without an answer they
// revert. Kept settings are saved to ~/.config/hypr/monitors.lua, which hyprland.lua loads.
// Open from the app menu, the "Display Settings" app entry, or:  qs ipc call display open
Scope {
    id: root

    IpcHandler {
        target: "display"
        function open(): void { ShellState.displaySettingsOpen = true }
        function close(): void { ShellState.displaySettingsOpen = false }
    }

    LazyLoader {
        active: ShellState.displaySettingsOpen

        FloatingWindow {
            id: win
            title: "Display Settings"
            implicitWidth: 640
            implicitHeight: 720
            color: Theme.bg
            onClosed: ShellState.displaySettingsOpen = false

            property var monitors: []          // from `hyprctl monitors all -j`
            property var edits: ({})           // name -> { mode, scale, transform, position, disabled }
            property var applied: ({})         // edits as they were before the last Apply
            property string selected: ""
            property int countdown: 0          // > 0 while waiting for Keep / Revert

            readonly property var mon: monitors.find(m => m.name === selected) ?? null
            readonly property var edit: edits[selected] ?? null
            readonly property bool dirty: JSON.stringify(edits) !== JSON.stringify(current())

            // ---- data ----
            function current() {
                const out = {}
                for (const m of monitors) out[m.name] = {
                    mode: `${m.width}x${m.height}@${m.refreshRate.toFixed(2)}`,
                    scale: String(Math.round(m.scale * 1e6) / 1e6),
                    transform: m.transform,
                    position: `${m.x}x${m.y}`,
                    disabled: m.disabled
                }
                return out
            }

            function setEdit(key, value) {
                const all = Object.assign({}, edits)
                all[selected] = Object.assign({}, all[selected], { [key]: value })
                edits = all
            }

            function lua(set) {
                return Object.entries(set).map(([name, e]) =>
                    `hl.monitor({ output = "${name}", mode = "${e.mode}", position = "${e.position}", `
                    + `scale = "${e.scale}", transform = ${e.transform}, disabled = ${e.disabled} })`).join("\n")
            }

            function reload() { query.running = true }

            function apply() {
                applied = current()
                evalLua(lua(edits))
                countdown = 15
            }
            function keep() {
                countdown = 0
                saved.setText("-- Written by Hypora Display Settings. Loaded from hyprland.lua.\n" + lua(edits) + "\n")
                reloadSoon.restart()
            }
            function revert() {
                countdown = 0
                evalLua(lua(applied))
                edits = applied
                reloadSoon.restart()
            }
            function evalLua(code) {
                Quickshell.execDetached(["hyprctl", "eval", code])
            }

            Process {
                id: query
                command: ["hyprctl", "monitors", "all", "-j"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        try { win.monitors = JSON.parse(text) } catch (e) { win.monitors = [] }
                        if (win.countdown === 0) win.edits = win.current()
                        if (!win.monitors.some(m => m.name === win.selected))
                            win.selected = (win.monitors.find(m => m.focused) ?? win.monitors[0])?.name ?? ""
                    }
                }
            }
            Timer { id: reloadSoon; interval: 800; onTriggered: win.reload() }
            Timer {
                interval: 1000
                repeat: true
                running: win.countdown > 0
                onTriggered: if (--win.countdown === 0) win.revert()
            }

            FileView {
                id: saved
                path: Quickshell.env("HOME") + "/.config/hypr/monitors.lua"
                blockLoading: true
                printErrors: false
            }

            // ---- options for the selected monitor ----
            readonly property var resolutions: {
                const seen = []
                for (const m of (mon?.availableModes ?? [])) {
                    const r = m.split("@")[0]
                    if (!seen.includes(r)) seen.push(r)
                }
                return seen.map(r => ({ label: r.replace("x", " × "), value: r }))
            }
            readonly property string resolution: edit ? edit.mode.split("@")[0] : ""
            readonly property var rates: (mon?.availableModes ?? [])
                .filter(m => m.split("@")[0] === resolution)
                .map(m => m.split("@")[1].replace("Hz", ""))
                .filter((r, i, all) => all.indexOf(r) === i)
                .map(r => ({ label: `${parseFloat(r).toFixed(2)} Hz`, value: r }))

            Rectangle {
                id: page
                anchors.fill: parent
                color: Theme.bg

                ColumnLayout {
                    anchors { fill: parent; margins: 24 }
                    spacing: 18

                    Text {
                        text: "Displays"
                        font.family: Theme.font; font.pixelSize: Theme.fontSize + 9; font.bold: true
                        color: Theme.fg
                    }

                    // Arrangement preview (current layout); click a monitor to select it
                    Rectangle {
                        id: arrangement
                        Layout.fillWidth: true
                        Layout.preferredHeight: 170
                        radius: 12
                        color: Theme.surface

                        readonly property var boxes: win.monitors.filter(m => !m.disabled).map(m => {
                            const rotated = m.transform % 2 === 1
                            const w = (rotated ? m.height : m.width) / m.scale
                            const h = (rotated ? m.width : m.height) / m.scale
                            return { name: m.name, x: m.x, y: m.y, w, h }
                        })
                        readonly property real minX: Math.min(...boxes.map(b => b.x))
                        readonly property real minY: Math.min(...boxes.map(b => b.y))
                        readonly property real spanW: Math.max(...boxes.map(b => b.x + b.w)) - minX
                        readonly property real spanH: Math.max(...boxes.map(b => b.y + b.h)) - minY
                        readonly property real fit: boxes.length ? Math.min((width - 40) / spanW, (height - 40) / spanH) : 1

                        Item {
                            anchors.centerIn: parent
                            width: arrangement.spanW * arrangement.fit
                            height: arrangement.spanH * arrangement.fit

                            Repeater {
                                model: arrangement.boxes
                                Rectangle {
                                    id: box
                                    required property var modelData
                                    readonly property bool isSelected: modelData.name === win.selected
                                    x: (modelData.x - arrangement.minX) * arrangement.fit + 2
                                    y: (modelData.y - arrangement.minY) * arrangement.fit + 2
                                    width: modelData.w * arrangement.fit - 4
                                    height: modelData.h * arrangement.fit - 4
                                    radius: 6
                                    color: isSelected ? Theme.accent : Theme.bg
                                    border.width: 1
                                    border.color: isSelected ? Theme.accent : Theme.dim

                                    Text {
                                        anchors.centerIn: parent
                                        text: box.modelData.name
                                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1; font.bold: true
                                        color: box.isSelected ? Theme.bg : Theme.fg
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: win.selected = box.modelData.name
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: win.monitors.length === 0
                            text: "No displays found (is Hyprland running?)"
                            font.family: Theme.font; font.pixelSize: Theme.fontSize
                            color: Theme.dim
                        }
                    }

                    // Disabled monitors can't be drawn above, so list every output as chips too
                    Row {
                        spacing: 8
                        visible: win.monitors.length > 1
                        Repeater {
                            model: win.monitors
                            Rectangle {
                                id: chip
                                required property var modelData
                                readonly property bool isSelected: modelData.name === win.selected
                                width: chipText.implicitWidth + 24
                                height: 28
                                radius: 14
                                color: isSelected ? Theme.surface : "transparent"
                                border.width: 1
                                border.color: isSelected ? Theme.accent : Theme.surface
                                Text {
                                    id: chipText
                                    anchors.centerIn: parent
                                    text: chip.modelData.name + (chip.modelData.disabled ? " (off)" : "")
                                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                                    color: chip.isSelected ? Theme.accent : Theme.fg
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.selected = chip.modelData.name
                                }
                            }
                        }
                    }

                    // Settings for the selected monitor
                    GridLayout {
                        Layout.fillWidth: true
                        visible: win.edit !== null
                        columns: 2
                        columnSpacing: 20
                        rowSpacing: 14
                        enabled: win.countdown === 0

                        Text {
                            Layout.columnSpan: 2
                            text: win.mon ? `${win.mon.make} ${win.mon.model}`.trim() || win.mon.name : ""
                            font.family: Theme.font; font.pixelSize: Theme.fontSize + 1; font.bold: true
                            color: Theme.fg
                        }

                        Label { text: "Enabled"; visible: win.monitors.length > 1 }
                        Toggle {
                            visible: win.monitors.length > 1
                            checked: win.edit ? !win.edit.disabled : true
                            // Never allow turning off the last enabled monitor
                            locked: checked && Object.values(win.edits).filter(e => !e.disabled).length <= 1
                            onToggled: win.setEdit("disabled", !win.edit.disabled)
                        }

                        Label { text: "Resolution" }
                        Select {
                            Layout.fillWidth: true
                            model: win.resolutions
                            currentIndex: indexOfValue(win.resolution)
                            onActivated: i => {
                                const r = win.resolutions[i].value
                                const best = (win.mon.availableModes.find(m => m.startsWith(r + "@")) ?? "").replace("Hz", "")
                                win.setEdit("mode", best)
                            }
                        }

                        Label { text: "Refresh rate" }
                        Select {
                            Layout.fillWidth: true
                            model: win.rates
                            currentIndex: indexOfValue(win.edit ? win.edit.mode.split("@")[1] : "")
                            onActivated: i => win.setEdit("mode", `${win.resolution}@${win.rates[i].value}`)
                        }

                        Label { text: "Scale" }
                        Segmented {
                            options: [
                                { label: "100%", value: "1" }, { label: "125%", value: "1.25" },
                                { label: "150%", value: "1.5" }, { label: "167%", value: "1.666667" },
                                { label: "200%", value: "2" }
                            ]
                            value: win.edit?.scale ?? "1"
                            onPicked: v => win.setEdit("scale", v)
                        }

                        Label { text: "Rotation" }
                        Segmented {
                            options: [
                                { label: "Normal", value: 0 }, { label: "90°", value: 1 },
                                { label: "180°", value: 2 }, { label: "270°", value: 3 }
                            ]
                            value: win.edit?.transform ?? 0
                            onPicked: v => win.setEdit("transform", v)
                        }

                        Label { text: "Position"; visible: win.monitors.length > 1 }
                        Select {
                            Layout.fillWidth: true
                            visible: win.monitors.length > 1
                            readonly property var choices: [
                                { label: win.mon ? `Current (${win.mon.x}, ${win.mon.y})` : "Current", value: win.mon ? `${win.mon.x}x${win.mon.y}` : "auto" },
                                { label: "Right of the others", value: "auto-right" },
                                { label: "Left of the others", value: "auto-left" },
                                { label: "Above the others", value: "auto-up" },
                                { label: "Below the others", value: "auto-down" }
                            ]
                            model: choices
                            currentIndex: Math.max(0, indexOfValue(win.edit?.position ?? ""))
                            onActivated: i => win.setEdit("position", choices[i].value)
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Footer: Apply / Reset, or the keep-or-revert prompt
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: win.countdown > 0 ? `Keep these display settings? Reverting in ${win.countdown}s.`
                                                    : "Changes apply right away and can be reverted."
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                            color: win.countdown > 0 ? Theme.fg : Theme.dim
                        }
                        Button {
                            text: win.countdown > 0 ? "Revert" : "Reset"
                            enabled: win.countdown > 0 || win.dirty
                            onClicked: win.countdown > 0 ? win.revert() : (win.edits = win.current())
                        }
                        Button {
                            text: win.countdown > 0 ? "Keep changes" : "Apply"
                            primary: true
                            enabled: win.countdown > 0 || win.dirty
                            onClicked: win.countdown > 0 ? win.keep() : win.apply()
                        }
                    }
                }
            }

            // ---- small controls ----
            component Label: Text {
                font.family: Theme.font; font.pixelSize: Theme.fontSize
                color: Theme.dim
            }

            component Button: Rectangle {
                id: btn
                property string text
                property bool primary: false
                signal clicked()
                implicitWidth: btnText.implicitWidth + 32
                implicitHeight: 36
                radius: 18
                opacity: enabled ? 1 : 0.4
                color: primary ? Theme.accent : (btnArea.containsMouse ? Qt.lighter(Theme.surface, 1.25) : Theme.surface)
                Text {
                    id: btnText
                    anchors.centerIn: parent
                    text: btn.text
                    font.family: Theme.font; font.pixelSize: Theme.fontSize; font.bold: btn.primary
                    color: btn.primary ? Theme.bg : Theme.fg
                }
                MouseArea {
                    id: btnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: btn.clicked()
                }
            }

            component Toggle: Rectangle {
                id: tog
                property bool checked
                property bool locked: false
                signal toggled()
                implicitWidth: 44
                implicitHeight: 24
                radius: 12
                color: checked ? Theme.accent : Theme.surface
                opacity: locked ? 0.5 : 1
                Rectangle {
                    width: 18; height: 18; radius: 9
                    anchors.verticalCenter: parent.verticalCenter
                    x: tog.checked ? parent.width - width - 3 : 3
                    color: tog.checked ? Theme.bg : Theme.fg
                    Behavior on x { NumberAnimation { duration: 120 } }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !tog.locked
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tog.toggled()
                }
            }

            component Segmented: Row {
                id: seg
                property var options: []
                property var value
                signal picked(var v)
                spacing: 4
                Repeater {
                    model: seg.options
                    Rectangle {
                        id: opt
                        required property var modelData
                        readonly property bool current: String(seg.value) === String(modelData.value)
                        width: optText.implicitWidth + 24
                        height: 32
                        radius: 16
                        color: current ? Theme.accent : (optArea.containsMouse ? Qt.lighter(Theme.surface, 1.25) : Theme.surface)
                        Text {
                            id: optText
                            anchors.centerIn: parent
                            text: opt.modelData.label
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 1; font.bold: opt.current
                            color: opt.current ? Theme.bg : Theme.fg
                        }
                        MouseArea {
                            id: optArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: seg.picked(opt.modelData.value)
                        }
                    }
                }
            }

            component Select: C.ComboBox {
                id: box
                textRole: "label"
                valueRole: "value"
                implicitHeight: 36
                font.family: Theme.font
                font.pixelSize: Theme.fontSize

                background: Rectangle {
                    radius: 10
                    color: box.hovered ? Qt.lighter(Theme.surface, 1.2) : Theme.surface
                }
                contentItem: Text {
                    leftPadding: 14
                    rightPadding: 30
                    text: box.displayText
                    font: box.font
                    color: Theme.fg
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
                indicator: Icon {
                    x: box.width - width - 12
                    y: (box.height - height) / 2
                    name: "chevron"
                    rotation: 90
                    size: 14
                    color: Theme.dim
                }
                delegate: C.ItemDelegate {
                    id: item
                    required property var modelData
                    required property int index
                    width: box.width - 8
                    x: 4
                    highlighted: box.highlightedIndex === index
                    contentItem: Text {
                        text: item.modelData.label
                        font: box.font
                        color: item.highlighted ? Theme.accent : Theme.fg
                    }
                    background: Rectangle {
                        radius: 6
                        color: item.highlighted ? Theme.surface : "transparent"
                    }
                }
                popup.background: Rectangle {
                    radius: 10
                    color: Theme.bg
                    border.width: 1
                    border.color: Theme.surface
                }
            }
        }
    }
}
