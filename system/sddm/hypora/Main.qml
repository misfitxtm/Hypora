import QtQuick

// Hypora login screen (SDDM), styled after Omarchy's: a block-letter logo over a
// password box. The user name only appears when there is more than one user.
// Colors come from theme.conf, which install.sh generates from the active Hypora theme.
Rectangle {
    id: root
    width: 1280
    height: 800
    color: config.bg || "#2e3440"

    readonly property color fg: config.fg || "#eceff4"
    readonly property color dim: config.dim || "#7b88a1"
    readonly property color accent: config.accent || "#88c0d0"
    readonly property color error: config.error || "#bf616a"
    readonly property string font: config.font || "JetBrains Mono"

    // UserModel roles: name = UserRole + 1, realName = UserRole + 2
    readonly property int userCount: userModel.rowCount()
    property int userIndex: Math.max(0, userModel.lastIndex)
    readonly property string userName: userModel.data(userModel.index(userIndex, 0), Qt.UserRole + 1) || ""
    readonly property string realName: userModel.data(userModel.index(userIndex, 0), Qt.UserRole + 2) || ""

    // Prefer the uwsm-managed Hyprland session, like Omarchy does
    readonly property int sessionIndex: {
        let fallback = sessionModel.lastIndex
        for (let i = 0; i < sessionModel.rowCount(); i++) {
            const name = String(sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "")
            if (name.indexOf("uwsm") !== -1) return i
            if (name.indexOf("Hyprland") !== -1) fallback = i
        }
        return fallback
    }

    property bool failed: false
    property bool busy: false

    function cycleUser(step) {
        if (userCount > 1) userIndex = (userIndex + step + userCount) % userCount
        password.text = ""
    }

    function login() {
        if (busy || password.text === "" || userName === "") return
        busy = true
        sddm.login(userName, password.text, sessionIndex)
    }

    // Inline SVG lock (Feather, MIT), recolored on failure
    function lockIcon(c) {
        const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="' + c + '" '
                  + 'stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
                  + '<rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>'
        return "data:image/svg+xml;utf8," + encodeURIComponent(svg)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false
            root.failed = true
            password.text = ""
            shake.restart()
            password.forceActiveFocus()
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 48

        // "HYPORA" in terminal-style blocks with a drop shadow, drawn as shapes so it
        // doesn't depend on font metrics. Each '#' is one cell.
        Canvas {
            id: logo
            readonly property var rows: [
                "##   ##  ##    ##  ######    #####   ######    ##### ",
                "##   ##   ##  ##   ##   ##  ##   ##  ##   ##  ##   ##",
                "#######    ####    ######   ##   ##  ######   #######",
                "##   ##     ##     ##       ##   ##  ##  ##   ##   ##",
                "##   ##     ##     ##        #####   ##   ##  ##   ##"
            ]
            readonly property real cw: 9      // cell width
            readonly property real ch: 18     // cell height (terminal cells are ~1:2)
            readonly property real drop: 4    // shadow offset

            anchors.horizontalCenter: parent.horizontalCenter
            width: rows[0].length * cw + drop
            height: rows.length * ch + drop

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const pass = (color, d) => {
                    ctx.fillStyle = color
                    rows.forEach((row, y) => {
                        for (let x = 0; x < row.length; x++)
                            if (row[x] === "#") ctx.fillRect(x * cw + d, y * ch + d, cw + 0.5, ch + 0.5)
                    })
                }
                pass(Qt.rgba(root.dim.r, root.dim.g, root.dim.b, 0.35), drop)
                pass(root.accent, 0)
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 14

            // Only on multi-user machines: click or Up/Down to switch
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.userCount > 1
                text: root.realName || root.userName
                font.family: root.font; font.pixelSize: 16
                color: root.dim
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cycleUser(1)
                }
            }

            Row {
                id: entry
                spacing: 16
                transform: Translate { id: offset }

                SequentialAnimation {
                    id: shake
                    loops: 2
                    NumberAnimation { target: offset; property: "x"; to: -10; duration: 40 }
                    NumberAnimation { target: offset; property: "x"; to: 10; duration: 80 }
                    NumberAnimation { target: offset; property: "x"; to: 0; duration: 40 }
                }

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 30
                    sourceSize: Qt.size(30, 30)
                    source: root.lockIcon(root.failed ? root.error : root.fg)
                }

                Rectangle {
                    width: 380; height: 50
                    color: "transparent"
                    border.width: 2
                    border.color: root.failed ? root.error : root.fg
                    opacity: root.busy ? 0.6 : 1

                    TextInput {
                        id: password
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        passwordCharacter: "•"
                        font.family: root.font; font.pixelSize: 22; font.letterSpacing: 4
                        color: root.failed ? root.error : root.fg
                        selectionColor: "transparent"
                        selectedTextColor: color
                        clip: true
                        focus: true
                        enabled: !root.busy

                        // Blinking block cursor, terminal style
                        cursorDelegate: Rectangle {
                            width: 10
                            color: root.accent
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                running: password.activeFocus
                                NumberAnimation { to: 1; duration: 0 }
                                PauseAnimation { duration: 530 }
                                NumberAnimation { to: 0; duration: 0 }
                                PauseAnimation { duration: 530 }
                            }
                        }

                        onTextChanged: if (text !== "") root.failed = false
                        onAccepted: root.login()
                        Keys.onUpPressed: root.cycleUser(-1)
                        Keys.onDownPressed: root.cycleUser(1)
                    }
                }
            }
        }
    }

    Component.onCompleted: password.forceActiveFocus()
}
