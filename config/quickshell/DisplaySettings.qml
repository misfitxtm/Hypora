import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as C

// Display Settings: resolution, refresh rate, scale, rotation, arrangement, which screen is
// the main one, and on/off per monitor.
//
// Position is set by dragging a monitor on the map rather than from a control: a dropdown of
// "left of the others" cannot express a stacked or deliberately offset layout, and having two
// ways to set one value means they drift apart. Edges snap, overlaps are refused, and the
// whole arrangement is shifted so the top-left screen sits at 0,0.
//
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

    // Keep-or-revert, as a full-screen overlay on every monitor rather than a line in the
    // settings window. A display change is the one setting that can hide its own undo: put
    // a panel on the wrong mode or the wrong output and the window holding "Revert" may be
    // off-screen, mirrored away or on a monitor that just went black. Drawing this on every
    // screen means whichever one still works has the way out.
    //
    // It reads the loader's item because countdown, keep() and revert() live on the window
    // inside it, and this has to outlive being unable to see that window.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: confirm
            required property var modelData
            readonly property var dlg: loader.item ?? null
            readonly property int left: dlg ? dlg.countdown : 0

            screen: modelData
            visible: left > 0
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "hypora-display-confirm"
            color: "#b3000000"

            Rectangle {
                anchors.centerIn: parent
                width: 420
                height: body.implicitHeight + 48
                radius: 16
                color: Theme.bg
                border.width: 1
                border.color: Theme.accent

                Column {
                    id: body
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                    spacing: 10

                    Text {
                        width: parent.width
                        text: "Keep these display settings?"
                        font.family: Theme.font; font.pixelSize: Theme.fontSize + 4; font.bold: true
                        color: Theme.fg
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: `Reverting to the previous settings in ${confirm.left} second`
                              + (confirm.left === 1 ? "." : "s.")
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                        color: Theme.dim
                    }

                    // A bar that drains, so the time left reads at a glance
                    Rectangle {
                        width: parent.width; height: 4; radius: 2
                        color: Theme.surface
                        Rectangle {
                            width: parent.width * (confirm.left / 15)
                            height: parent.height; radius: 2
                            color: Theme.accent
                            Behavior on width { NumberAnimation { duration: 950 } }
                        }
                    }

                    Item { width: 1; height: 6 }

                    Row {
                        anchors.right: parent.right
                        spacing: 10
                        Rectangle {
                            width: revertText.implicitWidth + 30; height: 36; radius: 18
                            color: revertArea.containsMouse ? Qt.lighter(Theme.surface, 1.3) : Theme.surface
                            Text {
                                id: revertText
                                anchors.centerIn: parent
                                text: "Revert"
                                font.family: Theme.font; font.pixelSize: Theme.fontSize
                                color: Theme.fg
                            }
                            MouseArea {
                                id: revertArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (confirm.dlg) confirm.dlg.revert()
                            }
                        }
                        Rectangle {
                            width: keepText.implicitWidth + 30; height: 36; radius: 18
                            color: Theme.accent
                            Text {
                                id: keepText
                                anchors.centerIn: parent
                                text: "Keep changes"
                                font.family: Theme.font; font.pixelSize: Theme.fontSize; font.bold: true
                                color: Theme.bg
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (confirm.dlg) confirm.dlg.keep()
                            }
                        }
                    }
                }
            }

            // Enter keeps, Esc reverts — the same answer from any keyboard on any screen
            Item {
                anchors.fill: parent
                focus: true
                Keys.onReturnPressed: if (confirm.dlg) confirm.dlg.keep()
                Keys.onEnterPressed: if (confirm.dlg) confirm.dlg.keep()
                Keys.onEscapePressed: if (confirm.dlg) confirm.dlg.revert()
                onVisibleChanged: if (visible) forceActiveFocus()
            }
        }
    }

    LazyLoader {
        id: loader
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
                                          || primary !== effectivePrimary

            // ---- main display ----
            // Hyprland has no "primary monitor" property, so this is Hypora's own notion and
            // it means two specific things: the session starts with the focus on it, and the
            // shell's single-instance panels (the app menu, clipboard history) open there
            // instead of on whichever output Quickshell happened to enumerate first.
            //
            // Stored in monitors.lua as HYPORA_PRIMARY so there is one file holding the
            // display layout rather than two. hyprland.lua reads the global; ShellState
            // reads the same line back out for the QML side.
            property string primary: ""          // what the toggle is showing
            property string savedPrimary: ""     // what monitors.lua currently says

            // With nothing saved yet, the main display is the one Hyprland has focused —
            // true on a single-monitor machine by definition. Compared against rather than
            // written eagerly, so opening the window doesn't look like an unsaved change.
            // The inner ?? chain is parenthesised because JavaScript refuses to mix ?? with
            // || or && at the same level — it is a SyntaxError, not a precedence question,
            // and QML reports it as "Left-hand side may not contain || or &&". Unparenthesised,
            // this one line stopped the whole shell from loading: shell.qml could not create
            // DisplaySettings, so nothing downstream of it existed either.
            readonly property string effectivePrimary:
                savedPrimary || ((monitors.find(m => m.focused) ?? monitors[0])?.name ?? "")

            function luaPrimary(name) {
                return name ? `HYPORA_PRIMARY = "${name}"` : "HYPORA_PRIMARY = nil"
            }

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

            // ---- arrangement geometry ----
            // Logical rectangles for the enabled monitors, taken from `edits` rather than
            // from hyprctl so the map reflects changes you haven't applied yet — a mode or
            // rotation change resizes the box straight away.
            readonly property var boxes: {
                const out = []
                for (const m of monitors) {
                    const e = edits[m.name]
                    if (!e || e.disabled) continue
                    const dim = String(e.mode).split("@")[0].split("x").map(Number)
                    const s = parseFloat(e.scale) || 1
                    const rotated = (e.transform % 2) === 1
                    const p = String(e.position).split("x").map(Number)
                    out.push({
                        name: m.name,
                        // A position Hyprland reported as "auto-right" has no coordinates to
                        // read, so fall back to where the monitor actually is.
                        x: isFinite(p[0]) ? p[0] : m.x,
                        y: isFinite(p[1]) ? p[1] : m.y,
                        w: (rotated ? dim[1] : dim[0]) / s,
                        h: (rotated ? dim[0] : dim[1]) / s
                    })
                }
                return out
            }

            // Boxes with the in-progress drag applied, so the map follows the pointer
            // without committing anything until the button comes up.
            readonly property var live: boxes.map(b => b.name === dragging
                ? ({ name: b.name, x: dragX, y: dragY, w: b.w, h: b.h }) : b)

            property string dragging: ""
            property real dragX: 0
            property real dragY: 0

            readonly property int snapDistance: 64      // logical px

            function snapAxis(v, size, others, lo, span) {
                let best = v, bd = snapDistance
                for (const o of others) {
                    const s = o[lo], e = o[lo] + o[span]
                    // Abut after, abut before, or align the near/far edges
                    for (const c of [e, s - size, s, e - size]) {
                        const d = Math.abs(v - c)
                        if (d < bd) { bd = d; best = c }
                    }
                }
                return best
            }

            function overlaps(a, b) {
                return a.x < b.x + b.w && b.x < a.x + a.w
                    && a.y < b.y + b.h && b.y < a.y + a.h
            }

            // Push `me` clear of `o` along whichever side costs the least movement.
            function pushOut(me, o) {
                let best = null, bd = Infinity
                for (const c of [{ x: o.x + o.w, y: me.y }, { x: o.x - me.w, y: me.y },
                                 { x: me.x, y: o.y + o.h }, { x: me.x, y: o.y - me.h }]) {
                    const d = Math.abs(c.x - me.x) + Math.abs(c.y - me.y)
                    if (d < bd) { bd = d; best = c }
                }
                return best
            }

            // Move `name` to (nx, ny): snap to its neighbours, refuse to overlap, and shift
            // the whole arrangement so the top-left monitor sits at 0,0. Hyprland accepts
            // negative coordinates, but letting them drift makes every later comparison and
            // every saved file harder to read for no gain.
            function placeMonitor(name, nx, ny) {
                const me = boxes.find(b => b.name === name)
                if (!me) return
                const others = boxes.filter(b => b.name !== name)
                let p = { name, x: nx, y: ny, w: me.w, h: me.h }
                if (others.length) {
                    p.x = snapAxis(nx, me.w, others, "x", "w")
                    p.y = snapAxis(ny, me.h, others, "y", "h")
                    for (let i = 0; i < 4; i++) {
                        const hit = others.find(o => overlaps(p, o))
                        if (!hit) break
                        const r = pushOut(p, hit)
                        p.x = r.x; p.y = r.y
                    }
                    // Still overlapping after four pushes: a layout this cramped has no
                    // sensible answer, so keep the position it had rather than inventing one.
                    if (others.some(o => overlaps(p, o))) return
                }
                const placed = boxes.map(b => b.name === name ? p : b)
                const minX = Math.min(...placed.map(b => b.x))
                const minY = Math.min(...placed.map(b => b.y))
                const all = Object.assign({}, edits)
                for (const b of placed)
                    all[b.name] = Object.assign({}, all[b.name],
                                                { position: `${b.x - minX}x${b.y - minY}` })
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
                appliedPrimary = effectivePrimary
                evalLua(lua(edits))
                focusPrimary()
                countdown = 15
            }
            function keep() {
                countdown = 0
                savedPrimary = primary
                saved.setText("-- Written by Hypora Display Settings. Loaded from hyprland.lua.\n"
                              + "-- HYPORA_PRIMARY is Hypora's main display: see DisplaySettings.qml.\n"
                              + luaPrimary(primary) + "\n" + lua(edits) + "\n")
                reloadSoon.restart()
            }
            function revert() {
                countdown = 0
                evalLua(lua(applied))
                edits = applied
                primary = appliedPrimary
                focusPrimary()
                reloadSoon.restart()
            }
            property string appliedPrimary: ""
            // Moving the focus is the half of "main display" that can be shown immediately;
            // the rest only means anything from the next session, which is what the file is for.
            function focusPrimary() {
                if (primary) Quickshell.execDetached(["hyprctl", "dispatch", "focusmonitor", primary])
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
                        // monitors.lua is read before hyprctl answers, so when nothing was
                        // saved there was no monitor list yet to fall back to. Settle it here,
                        // once, now that the outputs are known.
                        if (win.primary === "") {
                            win.primary = win.effectivePrimary
                            win.appliedPrimary = win.primary
                        }
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
                // Read back the one line the QML side cares about. A regex rather than a Lua
                // parser because this is a file Hypora writes itself and the shape is fixed;
                // anything unrecognised just leaves the main display unset, which falls back
                // to the focused monitor.
                onLoaded: {
                    const m = /^HYPORA_PRIMARY\s*=\s*"([^"]*)"/m.exec(text())
                    win.savedPrimary = m ? m[1] : ""
                    win.primary = win.effectivePrimary
                    win.appliedPrimary = win.primary
                }
                onLoadFailed: {
                    win.savedPrimary = ""
                    win.primary = win.effectivePrimary
                    win.appliedPrimary = win.primary
                }
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

                        // The live set includes the in-progress drag, so the map rescales as a
                        // monitor is pulled past the current bounds instead of clipping it.
                        readonly property var boxes: win.live
                        readonly property real minX: boxes.length ? Math.min(...boxes.map(b => b.x)) : 0
                        readonly property real minY: boxes.length ? Math.min(...boxes.map(b => b.y)) : 0
                        readonly property real spanW: boxes.length ? Math.max(...boxes.map(b => b.x + b.w)) - minX : 1
                        readonly property real spanH: boxes.length ? Math.max(...boxes.map(b => b.y + b.h)) - minY : 1
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
                                    readonly property bool isPrimary: modelData.name === win.primary
                                    readonly property bool isDragging: modelData.name === win.dragging
                                    x: (modelData.x - arrangement.minX) * arrangement.fit + 2
                                    y: (modelData.y - arrangement.minY) * arrangement.fit + 2
                                    width: modelData.w * arrangement.fit - 4
                                    height: modelData.h * arrangement.fit - 4
                                    radius: 6
                                    color: isSelected ? Theme.accent : Theme.bg
                                    border.width: isPrimary ? 2 : 1
                                    border.color: isSelected ? Theme.accent
                                                             : (isPrimary ? Theme.accent : Theme.dim)
                                    opacity: isDragging ? 0.85 : 1
                                    z: isDragging ? 1 : 0

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 1
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: box.modelData.name
                                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 1; font.bold: true
                                            color: box.isSelected ? Theme.bg : Theme.fg
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            visible: box.isPrimary && box.height > 34
                                            text: "main"
                                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
                                            color: box.isSelected ? Theme.bg : Theme.accent
                                        }
                                    }

                                    // Drag to arrange. The press selects, so a plain click still
                                    // works; the move is tracked in logical pixels (screen
                                    // coordinates divided by the map's scale) and only committed
                                    // on release, where the snapping happens.
                                    MouseArea {
                                        id: dragArea
                                        anchors.fill: parent
                                        cursorShape: win.monitors.length > 1
                                            ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                                            : Qt.PointingHandCursor
                                        enabled: win.countdown === 0
                                        property real startX: 0
                                        property real startY: 0
                                        property real originX: 0
                                        property real originY: 0

                                        onPressed: mouse => {
                                            win.selected = box.modelData.name
                                            if (win.monitors.length < 2) return
                                            startX = mouse.x; startY = mouse.y
                                            originX = box.modelData.x; originY = box.modelData.y
                                            win.dragX = originX; win.dragY = originY
                                            win.dragging = box.modelData.name
                                        }
                                        onPositionChanged: mouse => {
                                            if (win.dragging !== box.modelData.name) return
                                            const f = arrangement.fit || 1
                                            win.dragX = originX + (mouse.x - startX) / f
                                            win.dragY = originY + (mouse.y - startY) / f
                                        }
                                        onReleased: {
                                            if (win.dragging !== box.modelData.name) return
                                            const name = box.modelData.name
                                            const nx = win.dragX, ny = win.dragY
                                            win.dragging = ""
                                            win.placeMonitor(name, Math.round(nx), Math.round(ny))
                                        }
                                        onCanceled: win.dragging = ""
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

                        // Live read-out while dragging: the snap only lands on release, so
                        // without this there is no way to tell a deliberate gap from a
                        // near-miss that is about to be snapped shut.
                        Text {
                            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 6 }
                            visible: win.monitors.length > 1
                            text: win.dragging
                                ? `${win.dragging} at ${Math.round(win.dragX)}, ${Math.round(win.dragY)}`
                                : "Drag a display to arrange it — edges snap together"
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                            color: win.dragging ? Theme.accent : Theme.dim
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

                        // Position is set by dragging the map above, so there is no control
                        // here for it — a dropdown of "left of the others" could not express
                        // a stacked or offset layout, and two ways to set one value drift.

                        Label {
                            text: "Main display"
                            visible: win.monitors.length > 1
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: win.monitors.length > 1
                            spacing: 10
                            Toggle {
                                checked: win.primary === win.selected
                                // Turning it off would leave no main display at all, so the
                                // only move is turning a different one on.
                                locked: win.primary === win.selected || win.countdown > 0
                                onToggled: win.primary = win.selected
                            }
                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: win.primary === win.selected
                                    ? "Starts focused, and Hypora's menu and clipboard open here."
                                    : `Currently ${win.primary || "unset"}.`
                                font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                                color: Theme.dim
                            }
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
                            text: win.countdown > 0 ? "Waiting for you to confirm on screen…"
                                                    : "Changes apply right away and can be reverted."
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                            color: Theme.dim
                        }
                        Button {
                            text: "Reset"
                            enabled: win.countdown === 0 && win.dirty
                            onClicked: win.edits = win.current()
                        }
                        Button {
                            text: "Apply"
                            primary: true
                            enabled: win.countdown === 0 && win.dirty
                            onClicked: win.apply()
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
