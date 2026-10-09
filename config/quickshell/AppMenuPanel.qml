import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

// The Hypora menu: Apps, Style, Settings, Security, Tools and Help.
// Pick one to see its items; Esc, Left or the back arrow goes up a level.
// Typing searches installed apps from anywhere. Power actions live in the control center.
Rectangle {
    id: root
    signal closeRequested()

    property string page: ""    // "" = the section list

    readonly property var sections: [
        { icon: "grid", label: "Apps", page: "Apps" },
        { icon: "image", label: "Style", page: "Style" },
        { icon: "sliders", label: "Settings", page: "Settings" },
        { icon: "shield", label: "Security", page: "Security" },
        { icon: "tool", label: "Tools", page: "Tools" },
        { icon: "message", label: "Help", page: "Help" }
    ]

    readonly property var pages: ({
        "Style": [
            { icon: "image", label: "Theme", run: () => ShellState.themePickerOpen = true },
            { icon: "grid", label: "Icons", run: () => ShellState.iconPickerOpen = true },
            // Stays open so you can keep clicking through the theme's wallpapers
            { icon: "reboot", label: "Next wallpaper", stayOpen: true, run: () => ShellState.nextWallpaper() }
        ],
        "Settings": [
            { icon: "monitor", label: "Display", run: () => ShellState.displaySettingsOpen = true },
            { icon: "wifi", label: "Network", run: () => ShellState.networkSettingsOpen = true },
            { icon: "bluetooth", label: "Bluetooth", run: () => ShellState.bluetoothSettingsOpen = true },
            { icon: "volume", label: "Sound", run: () => ShellState.audioSettingsOpen = true },
            { icon: "folder", label: "Default Apps", run: () => ShellState.defaultAppsOpen = true }
        ],
        "Security": [
            { icon: "shield", label: "Security & Privacy", run: () => ShellState.securitySettingsOpen = true }
        ],
        "Tools": [
            { icon: "terminal", label: "Terminal", run: () => Apps.run([Theme.terminal]) },
            // Optional at install time: hidden entirely when it isn't installed
            { icon: "claude", label: "Claude Code", available: () => Apps.hasClaude,
              run: () => Apps.inTerminal("claude") },
            { icon: "camera", label: "Screenshot (region)", run: () => screenshot() },
            // Enrolment is per-user and interactive — it asks for the same finger several
            // times — so it belongs in a terminal rather than behind a progress bar that
            // cannot tell you to lift and press again. Hidden unless there is a reader and
            // fprintd to drive it.
            { icon: "lock", label: "Set up fingerprint", available: () => Apps.hasFingerprint,
              // Pauses at the end on purpose. inTerminal only holds the window open on a
              // non-zero exit, and a successful enrolment exits 0 — so the confirmation
              // would flash past on the one outcome you most want to read.
              run: () => Apps.inTerminal(
                  "fprintd-enroll; printf '\\nPress Enter to close. '; read _") }
        ],
        "Help": [
            { icon: "sliders", label: "Keybindings", run: () => ShellState.keybindHelpOpen = true },
            // xdg-open rather than a hardcoded browser: Hypora's own browser default is a
            // flatpak, and someone who has changed theirs should get the one they chose.
            { icon: "message", label: "Report a bug",
              run: () => Apps.run(["xdg-open", "https://github.com/misfitxtm/Hypora/issues/new"]) }
        ]
    })

    // What the list shows: app search results, all apps, a section's items, or the sections
    readonly property var items: search.text !== "" ? Apps.query(search.text, "").map(e => ({ app: e }))
                               : page === "Apps" ? Apps.all.map(e => ({ app: e }))
                               // A section's own items, minus any that declare an `available`
                               // test and fail it. Settings lists Hypora's own windows only:
                               // the system's control panels are GNOME's, built for a shell
                               // that isn't running here.
                               : page !== "" ? (pages[page] ?? []).filter(it => !it.available || it.available())
                               : sections

    // Called each time the menu opens
    function reset() {
        search.text = ""
        page = ""
        list.currentIndex = 0
        search.forceActiveFocus()
    }

    function open(page_) {
        page = page_
        search.text = ""
        list.currentIndex = 0
    }

    function back() {
        if (search.text !== "") search.text = ""
        else if (page !== "") open("")
        else return false
        return true
    }

    function activate(item) {
        if (!item) return
        if (item.page) { open(item.page); return }
        if (item.stayOpen) { item.run(); return }
        closeRequested()
        if (item.app) Apps.launch(item.app)
        else item.run()
    }

    // Same script the SUPER + SHIFT + S keybind runs
    function screenshot() { Quickshell.execDetached(["hypora-screenshot", "region"]) }

    implicitWidth: 320
    implicitHeight: column.implicitHeight + 24
    radius: 16
    color: Theme.bg
    border.width: 1
    border.color: Theme.surface

    ColumnLayout {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 8

        // Search
        Rectangle {
            Layout.fillWidth: true
            height: 38
            radius: 19
            color: Theme.surface
            border.width: 1
            border.color: search.activeFocus ? Theme.accent : "transparent"

            Icon {
                id: searchIcon
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                name: "search"
                size: 14
                color: Theme.dim
            }
            TextInput {
                id: search
                anchors { left: searchIcon.right; right: parent.right; leftMargin: 10; rightMargin: 14; verticalCenter: parent.verticalCenter }
                font.family: Theme.font; font.pixelSize: Theme.fontSize
                color: Theme.fg
                selectionColor: Theme.accent
                clip: true
                onTextChanged: list.currentIndex = 0
                onAccepted: root.activate(root.items[list.currentIndex])
                // Runs before the specific handlers below, and only claims the page keys,
                // so arrows and Tab still reach them. The search field owns focus here.
                Keys.onPressed: event => event.accepted = PageScroll.handle(event, list)
                Keys.onUpPressed: list.decrementCurrentIndex()
                Keys.onDownPressed: list.incrementCurrentIndex()
                Keys.onTabPressed: list.incrementCurrentIndex()
                Keys.onRightPressed: event => {
                    const item = root.items[list.currentIndex]
                    if (text === "" && item?.page) root.open(item.page)
                    else event.accepted = false
                }
                Keys.onLeftPressed: event => { event.accepted = text === "" && root.back() }
                Keys.onEscapePressed: event => { event.accepted = root.back() }   // at the top, Esc closes

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: search.text === ""
                    text: "Search apps"
                    font: search.font
                    color: Theme.dim
                }
            }
        }

        // Back row inside a section
        Rectangle {
            Layout.fillWidth: true
            visible: root.page !== "" && search.text === ""
            height: 32
            radius: 8
            color: backArea.containsMouse ? Theme.surface : "transparent"
            Icon {
                id: backIcon
                anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                name: "chevron-left"
                size: 16
                color: Theme.accent
            }
            Text {
                anchors { left: backIcon.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
                text: root.page
                font.family: Theme.font; font.pixelSize: Theme.fontSize; font.bold: true
                color: Theme.accent
            }
            MouseArea {
                id: backArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.back(); search.forceActiveFocus() }
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(1, Math.min(count, 10)) * 40
            clip: true
            model: root.items
            currentIndex: 0
            highlightMoveDuration: 0
            boundsBehavior: Flickable.StopAtBounds
            highlight: Rectangle { radius: 8; color: Theme.surface }

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool current: ListView.isCurrentItem
                width: ListView.view.width
                height: 40

                IconImage {
                    id: appIcon
                    visible: !!row.modelData.app
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    implicitSize: 22
                    source: row.modelData.app ? Quickshell.iconPath(row.modelData.app.icon, "application-x-executable") : ""
                }
                Icon {
                    visible: !row.modelData.app
                    anchors { left: parent.left; leftMargin: 13; verticalCenter: parent.verticalCenter }
                    name: row.modelData.icon ?? ""
                    size: 16
                    color: row.current ? Theme.accent : Theme.fg
                }
                Text {
                    anchors { left: parent.left; leftMargin: 44; right: chevron.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: row.modelData.app ? row.modelData.app.name : row.modelData.label
                    elide: Text.ElideRight
                    font.family: Theme.font; font.pixelSize: Theme.fontSize
                    color: row.current ? Theme.accent : Theme.fg
                }
                Icon {
                    id: chevron
                    visible: !!row.modelData.page
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    name: "chevron"
                    size: 14
                    color: Theme.dim
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: list.currentIndex = row.index
                    onClicked: { root.activate(row.modelData); search.forceActiveFocus() }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: list.count === 0
                text: "No apps found"
                font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                color: Theme.dim
            }
        }
    }
}
