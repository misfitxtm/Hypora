import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// Default apps: which app opens each kind of file, and a box to add a type of your own
// (".qml opens in Neovim"). Everything goes through bin/hypora-defaults, which writes only
// your ~/.config/mimeapps.list — the file Files, Firefox and xdg-open all read — so a
// choice here holds everywhere and needs no password. Run `hypora-defaults list` to see
// exactly what this window reads.
// Open from the menu (Settings > Default Apps) or:  qs ipc call defaults open
Scope {
    id: root

    IpcHandler {
        target: "defaults"
        function open(): void { ShellState.defaultAppsOpen = true }
        function close(): void { ShellState.defaultAppsOpen = false }
    }

    LazyLoader {
        active: ShellState.defaultAppsOpen

        FloatingWindow {
            id: win
            title: "Default Apps"
            implicitWidth: 600
            implicitHeight: 700
            color: Theme.bg
            onClosed: ShellState.defaultAppsOpen = false

            readonly property string helper: Quickshell.env("HOME") + "/.local/bin/hypora-defaults"

            property var rows: []
            property var apps: []          // every app that can open a file, for "Show all"
            property var added: null       // the row a lookup produced, until it's in `rows`
            property string expanded: ""   // ext of the row whose app list is open
            property bool showAll: false
            property bool loading: true
            property string notice: ""
            property bool noticeIsError: false

            Component.onCompleted: refresh()

            function refresh() { if (!listProc.running) listProc.running = true }

            Process {
                id: listProc
                command: [win.helper, "list"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const d = JSON.parse(text)
                            win.rows = d.rows
                            win.apps = d.apps
                        } catch (e) {
                            win.notice = "Could not read the current defaults."
                            win.noticeIsError = true
                        }
                        win.loading = false
                        // Once an added type has a default it is listed with the rest
                        if (win.added && win.rows.some(r => r.mime === win.added.mime)) win.added = null
                    }
                }
                onExited: code => { if (code !== 0) win.loading = false }
            }

            function lookup(raw) {
                const ext = raw.trim().toLowerCase().replace(/^\.+/, "")
                if (ext === "") return
                // The helper validates too; this just answers a typo without a round trip
                if (!/^[a-z0-9][a-z0-9_+.-]{0,15}$/.test(ext)) {
                    say("Use just the extension, like qml or tar.gz.", true)
                    return
                }
                const listed = rows.find(r => r.ext === ext || r.alsoCovers.includes(ext))
                if (listed) {
                    added = null
                    expanded = listed.ext
                    showAll = false
                    say("." + ext + " is already listed below.", false)
                    return
                }
                lookupProc.command = [helper, "lookup", ext]
                lookupProc.running = true
            }

            Process {
                id: lookupProc
                stdout: StdioCollector {
                    onStreamFinished: {
                        try { win.added = JSON.parse(text) } catch (e) { win.added = null; return }
                        win.expanded = win.added.ext
                        // Nothing declares a type nobody has heard of, so start with every app
                        win.showAll = win.added.candidates.length === 0
                        win.say("", false)
                        addField.text = ""
                    }
                }
                stderr: StdioCollector {
                    onStreamFinished: if (text.trim() !== "") win.say(text.trim().split("\n")[0], true)
                }
            }

            function choose(ext, appId) { act(["set", ext, appId]) }
            function reset(ext) { act(["reset", ext]) }

            function act(args) {
                if (actionProc.running) return
                actionProc.command = [helper].concat(args)
                actionProc.running = true
            }

            Process {
                id: actionProc
                stdout: StdioCollector { id: actionOut }
                stderr: StdioCollector { id: actionErr }
                onExited: code => {
                    const said = (code === 0 ? actionOut.text : actionErr.text).trim().split("\n")[0]
                    win.say(said || (code === 0 ? "" : "That did not work."), code !== 0)
                    if (code === 0) win.expanded = ""
                    win.refresh()
                }
            }

            function say(text, isError) { notice = text; noticeIsError = isError }

            Rectangle {
                anchors.fill: parent
                color: Theme.bg

                ColumnLayout {
                    anchors { fill: parent; margins: 22 }
                    spacing: 12

                    Text {
                        text: "Default Apps"
                        font.family: Theme.font; font.pixelSize: Theme.fontSize + 9; font.bold: true
                        color: Theme.fg
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Which app opens each kind of file. Changes apply straight away, "
                              + "everywhere — Files, Firefox and anything using xdg-open read the same list."
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                        color: Theme.dim
                    }

                    // ---------- add a type ----------
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 8
                        Rectangle {
                            Layout.fillWidth: true
                            height: 34
                            radius: 8
                            color: Theme.surface
                            TextInput {
                                id: addField
                                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                verticalAlignment: TextInput.AlignVCenter
                                font.family: Theme.font; font.pixelSize: Theme.fontSize
                                color: Theme.fg
                                selectionColor: Theme.accent
                                clip: true
                                onAccepted: win.lookup(text)
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: addField.text === "" && !addField.activeFocus
                                    text: "Add a file type, e.g. .qml"
                                    font: addField.font
                                    color: Theme.dim
                                }
                            }
                        }
                        Button { text: "Add"; primary: true; onClicked: win.lookup(addField.text) }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: win.notice !== ""
                        wrapMode: Text.WordWrap
                        text: win.notice
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                        color: win.noticeIsError ? Theme.error : Theme.accent
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentHeight: body.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: body
                            width: parent.width
                            spacing: 4

                            Heading { text: "New file type"; visible: win.added !== null }
                            TypeRow { visible: win.added !== null; data_: win.added }

                            Heading { text: "File types" }
                            Text {
                                Layout.leftMargin: 4
                                visible: win.loading
                                text: "Reading the current defaults…"
                                font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                                color: Theme.dim
                            }
                            Repeater {
                                model: win.rows
                                TypeRow {
                                    required property var modelData
                                    data_: modelData
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

            // One file type: what opens it now, and — when expanded — what could instead
            component TypeRow: ColumnLayout {
                id: tr
                property var data_: null
                readonly property bool open: data_ !== null && win.expanded === data_.ext
                // The apps that declare this type first; the rest only under "Show all"
                readonly property var others: data_ === null ? []
                    : win.apps.filter(a => !data_.candidates.some(c => c.id === a.id))
                readonly property var choices: data_ === null ? []
                    : (win.showAll ? data_.candidates.concat(others) : data_.candidates)

                Layout.fillWidth: true
                spacing: 2

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 54
                    radius: 10
                    color: trArea.containsMouse || tr.open ? Qt.lighter(Theme.surface, 1.12) : Theme.surface

                    Column {
                        anchors { left: parent.left; leftMargin: 14; right: trApp.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: tr.data_ ? "." + tr.data_.ext : ""
                            font.family: Theme.font; font.pixelSize: Theme.fontSize; font.bold: true
                            color: Theme.fg
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            // A default belongs to the MIME type, so say which other
                            // extensions a choice here also changes
                            text: !tr.data_ ? ""
                                : tr.data_.description + (tr.data_.alsoCovers.length
                                    ? " · also ." + tr.data_.alsoCovers.join(", .") : "")
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
                            color: Theme.dim
                        }
                    }
                    Text {
                        id: trApp
                        anchors { right: trChevron.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        width: Math.min(implicitWidth, parent.width * 0.45)
                        elide: Text.ElideRight
                        text: !tr.data_ ? ""
                            : tr.data_.currentName === "" ? "Nothing set"
                            : tr.data_.currentName + (tr.data_.chosen ? "" : " (automatic)")
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                        color: tr.data_ && tr.data_.chosen ? Theme.accent : Theme.dim
                    }
                    Icon {
                        id: trChevron
                        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                        name: "chevron"
                        rotation: tr.open ? 90 : 0
                        size: 14
                        color: Theme.dim
                    }
                    MouseArea {
                        id: trArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            win.showAll = tr.data_.candidates.length === 0
                            win.expanded = tr.open ? "" : tr.data_.ext
                        }
                    }
                }

                // ---------- the choices, when open ----------
                Text {
                    Layout.leftMargin: 16
                    Layout.topMargin: 4
                    visible: tr.open && tr.choices.length === 0
                    text: "No installed app says it opens this type."
                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                    color: Theme.dim
                }
                Repeater {
                    model: tr.open ? tr.choices : []
                    AppRow {
                        required property var modelData
                        text: modelData.name
                        current: tr.data_.chosen && modelData.id === tr.data_.current
                        onPicked: win.choose(tr.data_.ext, modelData.id)
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.bottomMargin: 6
                    visible: tr.open
                    spacing: 16
                    Link {
                        visible: !win.showAll && tr.others.length > 0
                        text: "Show all apps"
                        onClicked: win.showAll = true
                    }
                    Item { Layout.fillWidth: true }
                    Link {
                        visible: tr.data_ !== null && tr.data_.chosen
                        text: "Reset to automatic"
                        onClicked: win.reset(tr.data_.ext)
                    }
                }
            }

            // An app that could open the type; the dot marks the one you chose
            component AppRow: Rectangle {
                id: ar
                property bool current: false
                property string text: ""
                signal picked()

                Layout.fillWidth: true
                Layout.leftMargin: 12
                implicitHeight: 32
                radius: 8
                color: arArea.containsMouse ? Theme.surface : "transparent"

                Rectangle {
                    id: arDot
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    width: 12; height: 12; radius: 6
                    color: ar.current ? Theme.accent : "transparent"
                    border.width: ar.current ? 0 : 1.5
                    border.color: Theme.dim
                }
                Text {
                    anchors { left: arDot.right; right: parent.right; leftMargin: 12; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    text: ar.text
                    elide: Text.ElideRight
                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                    color: ar.current ? Theme.fg : Theme.dim
                }
                MouseArea {
                    id: arArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ar.picked()
                }
            }

            component Link: Text {
                id: link
                signal clicked()
                font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                color: linkArea.containsMouse ? Theme.accent : Theme.dim
                MouseArea {
                    id: linkArea
                    anchors { fill: parent; margins: -6 }
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: link.clicked()
                }
            }

            component Button: Rectangle {
                id: btn
                property string text
                property bool primary: false
                signal clicked()
                implicitWidth: btnText.implicitWidth + 28
                implicitHeight: 34
                radius: 17
                color: primary ? Theme.accent : (btnArea.containsMouse ? Qt.lighter(Theme.surface, 1.25) : Theme.surface)
                Text {
                    id: btnText
                    anchors.centerIn: parent
                    text: btn.text
                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 1; font.bold: btn.primary
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
        }
    }
}
