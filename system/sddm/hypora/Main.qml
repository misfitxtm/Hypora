import QtQuick

// Hypora login screen (SDDM). Colors come from theme.conf, which install.sh
// generates from the active Hypora theme.
Rectangle {
    id: root
    width: 1280
    height: 800
    color: config.bg || "#2e3440"

    readonly property color surface: config.surface || "#3b4252"
    readonly property color fg: config.fg || "#eceff4"
    readonly property color dim: config.dim || "#7b88a1"
    readonly property color accent: config.accent || "#88c0d0"
    readonly property color error: config.error || "#bf616a"
    readonly property string font: config.font || "JetBrains Mono"

    // UserModel roles: name = UserRole + 1, realName = UserRole + 2
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
    property date now: new Date()

    function cycleUser(step) {
        const n = userModel.rowCount()
        if (n > 1) userIndex = (userIndex + step + n) % n
        password.text = ""
    }

    function login() {
        if (busy || password.text === "" || userName === "") return
        busy = true
        sddm.login(userName, password.text, sessionIndex)
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

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: root.now = new Date()
    }

    Column {
        anchors.centerIn: parent
        spacing: 0

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.now, "HH:mm")
            font.family: root.font; font.pixelSize: 96; font.weight: Font.Light
            color: root.fg
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(root.now, "dddd, MMMM d")
            font.family: root.font; font.pixelSize: 16
            color: root.dim
        }

        Item { width: 1; height: 64 }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.realName || root.userName
            font.family: root.font; font.pixelSize: 18
            color: root.fg
            MouseArea {
                anchors.fill: parent
                enabled: userModel.rowCount() > 1
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.cycleUser(1)
            }
        }

        Item { width: 1; height: 16 }

        Rectangle {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            width: 300; height: 44; radius: 22
            color: root.surface
            border.width: 1
            border.color: root.failed ? root.error : (password.activeFocus ? root.accent : "transparent")
            opacity: root.busy ? 0.6 : 1
            Behavior on border.color { ColorAnimation { duration: 150 } }

            transform: Translate { id: offset }
            SequentialAnimation {
                id: shake
                loops: 2
                NumberAnimation { target: offset; property: "x"; to: -8; duration: 40 }
                NumberAnimation { target: offset; property: "x"; to: 8; duration: 80 }
                NumberAnimation { target: offset; property: "x"; to: 0; duration: 40 }
            }

            Text {
                anchors.centerIn: parent
                visible: password.text === ""
                text: root.failed ? "Wrong password" : "Password"
                font.family: root.font; font.pixelSize: 14
                color: root.failed ? root.error : root.dim
            }

            TextInput {
                id: password
                anchors { fill: parent; leftMargin: 20; rightMargin: 20 }
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                echoMode: TextInput.Password
                passwordCharacter: "•"
                font.family: root.font; font.pixelSize: 16; font.letterSpacing: 2
                color: root.fg
                selectionColor: root.accent
                clip: true
                focus: true
                enabled: !root.busy

                onTextChanged: if (text !== "") root.failed = false
                onAccepted: root.login()
                Keys.onUpPressed: root.cycleUser(-1)
                Keys.onDownPressed: root.cycleUser(1)
            }
        }
    }

    // Bottom right: power actions
    Row {
        anchors { right: parent.right; bottom: parent.bottom; margins: 32 }
        spacing: 24

        Repeater {
            model: [
                { label: "Reboot",    show: sddm.canReboot,   act: () => sddm.reboot() },
                { label: "Power off", show: sddm.canPowerOff, act: () => sddm.powerOff() }
            ]
            Text {
                required property var modelData
                visible: modelData.show
                text: modelData.label
                font.family: root.font; font.pixelSize: 13
                color: area.containsMouse ? root.fg : root.dim
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: parent.modelData.act()
                }
            }
        }
    }

    Component.onCompleted: password.forceActiveFocus()
}
