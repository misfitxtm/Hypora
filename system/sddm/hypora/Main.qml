import QtQuick

// Hypora login screen (SDDM): the Hypora mark and wordmark over a
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

    // The Hypora mark: same SVG as config/quickshell/Logo.qml (keep them in sync)
    function logo(from, to) {
        const hex = c => "#" + [c.r, c.g, c.b].map(v => Math.round(v * 255).toString(16).padStart(2, "0")).join("")
        const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="url(#g)" '
                  + 'stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">'
                  + '<defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="3" y1="2" x2="21" y2="22">'
                  + '<stop offset="0" stop-color="' + hex(from) + '"/><stop offset="1" stop-color="' + hex(to) + '"/>'
                  + '</linearGradient></defs>'
                  + '<polygon points="12 1.8 20.8 6.9 20.8 17.1 12 22.2 3.2 17.1 3.2 6.9"/>'
                  + '<line x1="8.4" y1="7.6" x2="8.4" y2="16.4"/><line x1="15.6" y1="7.6" x2="15.6" y2="16.4"/>'
                  + '<path d="M8.4 12c1.2-1.7 2.4-1.7 3.6 0s2.4 1.7 3.6 0"/>'
                  + '</svg>'
        return "data:image/svg+xml;utf8," + encodeURIComponent(svg)
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

        // The Hypora mark and wordmark
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 18

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 96; height: 96
                sourceSize: Qt.size(96, 96)
                source: root.logo(root.accent, Qt.hsla((root.accent.hslHue + 0.15) % 1, root.accent.hslSaturation, root.accent.hslLightness, 1))
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "hypora"
                font.family: root.font; font.pixelSize: 30; font.weight: Font.Light; font.letterSpacing: 14
                leftPadding: 14   // balance the trailing letter spacing
                color: root.fg
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
                    width: 360; height: 50
                    radius: 25
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
                    border.width: 1.5
                    border.color: root.failed ? root.error : (password.activeFocus ? root.accent : root.dim)
                    opacity: root.busy ? 0.6 : 1

                    TextInput {
                        id: password
                        anchors { fill: parent; leftMargin: 24; rightMargin: 24 }
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

                        // Slim blinking cursor in the accent color
                        cursorDelegate: Rectangle {
                            width: 2
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
