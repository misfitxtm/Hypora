import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// Keyboard shortcuts: what they are, and a way to change them.
// Changes are written to ~/.config/hypr/keybinds.lua, which hyprland.lua merges over its
// defaults, then Hyprland is reloaded. The action names below must match the `keys` table
// in config/hypr/hyprland.lua.
// Open from the menu (Help > Keybindings) or:  qs ipc call help open
Scope {
    id: root

    IpcHandler {
        target: "help"
        function open(): void { ShellState.keybindHelpOpen = true }
        function close(): void { ShellState.keybindHelpOpen = false }
    }

    LazyLoader {
        active: ShellState.keybindHelpOpen

        FloatingWindow {
            id: win
            title: "Keyboard Shortcuts"
            implicitWidth: 560
            implicitHeight: 680
            color: Theme.bg
            // Clearing `capturing` first matters: its handler is what gives the keyboard back
            onClosed: {
                capturing = ""
                ShellState.keybindHelpOpen = false
            }

            // Rebindable actions, grouped the way they're explained
            readonly property var groups: [
                { title: "Apps", items: [
                    { action: "terminal",    label: "Terminal",        def: "SUPER + Return" },
                    { action: "browser",     label: "Browser",         def: "SUPER + B" },
                    { action: "files",       label: "Files",           def: "SUPER + E" },
                    { action: "launcher",    label: "App launcher",    def: "SUPER + R" },
                    { action: "menu",        label: "Hypora menu",     def: "SUPER + A" },
                    { action: "themePicker", label: "Theme picker",    def: "SUPER + ALT + T" },
                    { action: "clipboard",   label: "Clipboard history", def: "SUPER + SHIFT + V" },
                    { action: "screenshot",  label: "Screenshot a region", def: "SUPER + SHIFT + S" }
                ]},
                { title: "Windows", items: [
                    { action: "closeWindow", label: "Close window",    def: "SUPER + Q" },
                    { action: "toggleFloat", label: "Toggle floating", def: "SUPER + V" },
                    { action: "fullscreen",  label: "Fullscreen",      def: "SUPER + F" },
                    { action: "toggleSplit", label: "Toggle split",    def: "SUPER + J" },
                    { action: "pseudo",      label: "Pseudo-tile",     def: "SUPER + P" },
                    { action: "focusLeft",   label: "Focus left",      def: "SUPER + left" },
                    { action: "focusRight",  label: "Focus right",     def: "SUPER + right" },
                    { action: "focusUp",     label: "Focus up",        def: "SUPER + up" },
                    { action: "focusDown",   label: "Focus down",      def: "SUPER + down" },
                    { action: "monitorLeft",  label: "Send to left monitor",  def: "SUPER + SHIFT + left" },
                    { action: "monitorRight", label: "Send to right monitor", def: "SUPER + SHIFT + right" },
                    { action: "monitorUp",    label: "Send to monitor above", def: "SUPER + SHIFT + up" },
                    { action: "monitorDown",  label: "Send to monitor below", def: "SUPER + SHIFT + down" }
                ]},
                { title: "Scratchpad", items: [
                    { action: "scratchpad",       label: "Show / hide scratchpad", def: "SUPER + S" },
                    { action: "moveToScratchpad", label: "Move window to scratchpad", def: "SUPER + ALT + S" }
                ]},
                { title: "Session", items: [
                    { action: "lock",   label: "Lock screen", def: "SUPER + L" },
                    { action: "logout", label: "Log out",     def: "SUPER + M" }
                ]}
            ]

            // Shown for reference; these aren't single keys, so they're set in hyprland.lua
            readonly property var fixed: [
                { label: "Switch to workspace 1-10",     key: "SUPER + 1 … 0" },
                { label: "Move window to workspace",     key: "SUPER + SHIFT + 1 … 0" },
                { label: "Cycle through workspaces",     key: "SUPER + scroll" },
                { label: "Move window",                  key: "SUPER + drag" },
                { label: "Resize window",                key: "SUPER + right-drag" },
                { label: "Volume up / down / mute",      key: "volume keys" },
                { label: "Mute the microphone",          key: "mic mute key" },
                { label: "Screen brightness",            key: "brightness keys" },
                { label: "Play / pause, next, previous", key: "media keys" }
            ]

            property var overrides: ({})     // action -> key, only where changed
            property string capturing: ""    // action currently waiting for a key
            property string notice: ""

            function keyFor(action, fallback) { return overrides[action] || fallback }

            // ---------- holding the keyboard while we wait for a chord ----------
            //
            // Hyprland handles binds itself, before any client is offered the key. So while
            // this window waits for a new chord, every combination that is already bound
            // runs its action instead of reaching us: pressing SUPER + Q to rebind "Close
            // window" closed the window, and SUPER + Q was never captured.
            //
            // keyboard-shortcuts-inhibit is the Wayland protocol built for precisely this —
            // a client asks the compositor to stop acting on its own shortcuts while this
            // surface has keyboard focus. Two things make it the right tool rather than the
            // `hyprctl dispatch submap` trick that was here before:
            //
            //   * `active` reports whether the compositor actually agreed. The submap call
            //     had no return path at all, so when Hyprland ignored it — which it did,
            //     because the submap was never defined anywhere — nothing said so and the
            //     binds simply kept firing.
            //   * The inhibition is tied to this surface. When the window closes, or the
            //     shell exits, or it crashes, the compositor drops it and shortcuts come
            //     back on their own. The submap was global state that had to be unwound by
            //     hand, and anything that killed the shell mid-capture left a desktop with
            //     no working keys.
            ShortcutInhibitor {
                id: inhibitor
                window: win
                enabled: win.capturing !== ""

                // The compositor can revoke it; say so rather than silently capturing the
                // action a key is bound to.
                onCancelled: {
                    win.capturing = ""
                    win.notice = "The compositor took the keyboard back, so nothing changed."
                    clearNotice.restart()
                }
            }

            // A chord takes a moment to press, not a quarter of an hour. If capture is still
            // open after this, assume it was forgotten and release the keyboard.
            Timer {
                id: captureTimeout
                interval: 15000
                running: win.capturing !== ""
                onTriggered: {
                    win.capturing = ""
                    win.notice = "Stopped waiting, so your shortcuts still work. Click one to try again."
                    clearNotice.restart()
                }
            }

            // Every chord more than one action now wants. A duplicate is allowed — refusing
            // the edit made it impossible to swap two shortcuts, since whichever you set
            // first collided with the other — but Hyprland keeps only the last bind for a
            // chord, so the earlier one silently stops working. Hence saying so, loudly and
            // for as long as it's true, rather than a notice that fades after two seconds.
            readonly property var clashes: {
                const byKey = {}
                for (const g of groups)
                    for (const it of g.items) {
                        const k = keyFor(it.action, it.def)
                        if (!byKey[k]) byKey[k] = []
                        byKey[k].push(it.label)
                    }
                const out = []
                for (const k in byKey)
                    if (byKey[k].length > 1) out.push({ key: k, labels: byKey[k] })
                return out
            }
            readonly property var clashKeys: clashes.map(c => c.key)

            function setKey(action, key, deflt) {
                const next = Object.assign({}, overrides)
                if (key === deflt) delete next[action]
                else next[action] = key
                overrides = next
                save()
            }

            function resetAll() {
                overrides = ({})
                save()
            }

            function save() {
                let out = "-- Written by Hypora (menu > Help > Keybindings).\n"
                    + "-- Merged over the defaults in hyprland.lua. Delete this file to restore them.\n"
                    + "return {\n"
                for (const [action, key] of Object.entries(overrides))
                    out += `    ${action} = "${key}",\n`
                out += "}\n"
                file.setText(out)
                reload.running = true
                notice = "Saved. Hyprland reloaded."
                clearNotice.restart()
            }

            Process { id: reload; command: ["hyprctl", "reload"] }
            Timer { id: clearNotice; interval: 2500; onTriggered: win.notice = "" }

            FileView {
                id: file
                path: Quickshell.env("HOME") + "/.config/hypr/keybinds.lua"
                blockLoading: true
                printErrors: false
                onLoaded: {
                    // Our own format: one `action = "KEY",` per line
                    const found = {}
                    const re = /([A-Za-z]+)\s*=\s*"([^"]*)"/g
                    let m
                    while ((m = re.exec(text())) !== null) found[m[1]] = m[2]
                    win.overrides = found
                }
            }

            // Turn a key press into the name Hyprland uses
            function keyName(event) {
                const k = event.key
                const modifierKeys = [Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_Control, Qt.Key_Alt,
                                      Qt.Key_Shift, Qt.Key_Meta, Qt.Key_AltGr, Qt.Key_CapsLock]
                if (modifierKeys.indexOf(k) !== -1) return ""      // still waiting for a real key

                let name = ""
                if (k >= Qt.Key_A && k <= Qt.Key_Z) name = String.fromCharCode(65 + k - Qt.Key_A)
                else if (k >= Qt.Key_0 && k <= Qt.Key_9) name = String(k - Qt.Key_0)
                else if (k >= Qt.Key_F1 && k <= Qt.Key_F12) name = "F" + (1 + k - Qt.Key_F1)
                else switch (k) {
                    case Qt.Key_Return:
                    case Qt.Key_Enter:     name = "Return"; break
                    case Qt.Key_Space:     name = "Space"; break
                    case Qt.Key_Tab:       name = "Tab"; break
                    case Qt.Key_Backspace: name = "BackSpace"; break
                    case Qt.Key_Delete:    name = "Delete"; break
                    case Qt.Key_Home:      name = "Home"; break
                    case Qt.Key_End:       name = "End"; break
                    case Qt.Key_PageUp:    name = "Prior"; break
                    case Qt.Key_PageDown:  name = "Next"; break
                    case Qt.Key_Left:      name = "left"; break
                    case Qt.Key_Right:     name = "right"; break
                    case Qt.Key_Up:        name = "up"; break
                    case Qt.Key_Down:      name = "down"; break
                    case Qt.Key_Comma:     name = "comma"; break
                    case Qt.Key_Period:    name = "period"; break
                    case Qt.Key_Slash:     name = "slash"; break
                    case Qt.Key_Minus:     name = "minus"; break
                    case Qt.Key_Equal:     name = "equal"; break
                    default: return ""
                }

                const mods = []
                if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
                if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
                if (event.modifiers & Qt.AltModifier) mods.push("ALT")
                if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
                return mods.concat([name]).join(" + ")
            }

            Rectangle {
                id: page
                anchors.fill: parent
                color: Theme.bg
                focus: true

                Keys.onPressed: event => {
                    // Not waiting for a chord: Page Up / Page Down scroll the list. Handled
                    // here rather than on the Flickable because this item already owns the
                    // window's focus for key capture, and two focus holders would fight.
                    if (win.capturing === "") {
                        event.accepted = PageScroll.handle(event, scroller)
                        return
                    }
                    event.accepted = true
                    if (event.key === Qt.Key_Escape) { win.capturing = ""; return }
                    const name = win.keyName(event)
                    if (name === "") return
                    const item = win.groups.reduce((f, g) => f || g.items.find(i => i.action === win.capturing), null)
                    // Taken keys are accepted; the banner below reports the overlap
                    win.setKey(win.capturing, name, item ? item.def : "")
                    win.capturing = ""
                }

                ColumnLayout {
                    anchors { fill: parent; margins: 22 }
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: "Keyboard Shortcuts"
                            font.family: Theme.font; font.pixelSize: Theme.fontSize + 9; font.bold: true
                            color: Theme.fg
                        }
                        Rectangle {
                            visible: Object.keys(win.overrides).length > 0
                            implicitWidth: resetText.implicitWidth + 24
                            implicitHeight: 30
                            radius: 15
                            color: resetArea.containsMouse ? Qt.lighter(Theme.surface, 1.25) : Theme.surface
                            Text {
                                id: resetText
                                anchors.centerIn: parent
                                text: "Reset all"
                                font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                                color: Theme.fg
                            }
                            MouseArea {
                                id: resetArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.resetAll()
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        // When capture is armed the text reports whether the compositor
                        // actually handed the keyboard over. If it didn't, saying so beats
                        // letting you discover it by having a window close under you.
                        text: win.notice !== "" ? win.notice
                            : win.capturing === "" ? "Click a shortcut to change it."
                            : inhibitor.active
                              ? "Press the new key combination, or Esc to cancel. Your shortcuts "
                                + "are paused until you do, so the one you press is read instead "
                                + "of firing."
                              : "Press the new key combination, or Esc to cancel. The compositor "
                                + "did not pause shortcuts, so a combination already in use will "
                                + "run its action instead of being captured."
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                        color: win.capturing === "" ? Theme.dim
                             : inhibitor.active ? Theme.accent : Theme.warn
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        visible: win.clashes.length > 0
                        implicitHeight: clashCol.implicitHeight + 24
                        radius: 10
                        color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.12)
                        border.width: 1
                        border.color: Theme.error

                        Column {
                            id: clashCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 4
                            Text {
                                text: win.clashes.length === 1 ? "One shortcut is used twice"
                                                               : `${win.clashes.length} shortcuts are used twice`
                                font.family: Theme.font; font.pixelSize: Theme.fontSize - 1; font.bold: true
                                color: Theme.error
                            }
                            Repeater {
                                model: win.clashes
                                Text {
                                    required property var modelData
                                    width: clashCol.width
                                    wrapMode: Text.Wrap
                                    text: `${modelData.key} — ${modelData.labels.join(", ")}`
                                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                                    color: Theme.fg
                                }
                            }
                            Text {
                                width: clashCol.width
                                wrapMode: Text.Wrap
                                text: "Hyprland keeps only the last binding for a chord, so the others "
                                    + "won't fire until you change one of them."
                                font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
                                color: Theme.dim
                            }
                        }
                    }

                    Flickable {
                        id: scroller
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentHeight: list.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: list
                            width: parent.width
                            spacing: 2

                            Repeater {
                                model: win.groups
                                ColumnLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        Layout.topMargin: 10
                                        Layout.leftMargin: 4
                                        Layout.bottomMargin: 2
                                        text: parent.modelData.title
                                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 3; font.bold: true
                                        font.capitalization: Font.AllUppercase; font.letterSpacing: 1
                                        color: Theme.dim
                                    }

                                    Repeater {
                                        model: parent.modelData.items
                                        Rectangle {
                                            id: row
                                            required property var modelData
                                            readonly property bool active: win.capturing === modelData.action
                                            readonly property string key: win.keyFor(modelData.action, modelData.def)
                                            readonly property bool changed: key !== modelData.def
                                            readonly property bool clashing: win.clashKeys.indexOf(key) !== -1

                                            Layout.fillWidth: true
                                            implicitHeight: 38
                                            radius: 8
                                            color: active ? Theme.surface
                                                 : rowArea.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent"

                                            Text {
                                                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                                text: row.modelData.label
                                                font.family: Theme.font; font.pixelSize: Theme.fontSize
                                                color: Theme.fg
                                            }
                                            Rectangle {
                                                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                                implicitWidth: keyText.implicitWidth + 20
                                                implicitHeight: 26
                                                radius: 6
                                                color: row.active ? Theme.accent : Theme.surface
                                                border.width: row.active ? 0 : (row.clashing || row.changed ? 1 : 0)
                                                border.color: row.clashing ? Theme.error : Theme.accent
                                                Text {
                                                    id: keyText
                                                    anchors.centerIn: parent
                                                    text: row.active ? "Press a key…" : row.key
                                                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                                                    color: row.active ? Theme.bg
                                                         : row.clashing ? Theme.error : Theme.fg
                                                }
                                            }
                                            MouseArea {
                                                id: rowArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    win.notice = ""
                                                    win.capturing = row.active ? "" : row.modelData.action
                                                    page.forceActiveFocus()
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.topMargin: 14
                                Layout.leftMargin: 4
                                Layout.bottomMargin: 2
                                text: "Built in"
                                font.family: Theme.font; font.pixelSize: Theme.fontSize - 3; font.bold: true
                                font.capitalization: Font.AllUppercase; font.letterSpacing: 1
                                color: Theme.dim
                            }
                            Repeater {
                                model: win.fixed
                                RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 30
                                    Text {
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 12
                                        text: parent.modelData.label
                                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                                        color: Theme.dim
                                    }
                                    Text {
                                        Layout.rightMargin: 12
                                        text: parent.modelData.key
                                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                                        color: Theme.dim
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
