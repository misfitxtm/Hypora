import QtQuick
import QtQuick.Window

// Hypora login screen (SDDM): the time, the date and a password field. The user name
// only appears when there is more than one user.
// Colors come from theme.conf, which hypora-theme generates from the active theme.
Rectangle {
    id: root
    // Fill whatever monitor SDDM puts this on, at its own resolution. SDDM sizes the
    // root item itself, but binding to Screen keeps it right on mixed-DPI setups and
    // when a monitor's mode is applied after the greeter has already started.
    width: Screen.width
    height: Screen.height
    color: config.bg || "#2e3440"

    readonly property color surface: config.surface || "#3b4252"
    readonly property color fg: config.fg || "#eceff4"
    readonly property color dim: config.dim || "#7b88a1"
    readonly property color accent: config.accent || "#88c0d0"
    readonly property color error: config.error || "#bf616a"
    readonly property string font: config.font || "JetBrainsMono Nerd Font"

    // UserModel roles: name = UserRole + 1, realName = UserRole + 2
    readonly property int userCount: userModel.rowCount()
    property int userIndex: Math.max(0, userModel.lastIndex)
    readonly property string userName: userModel.data(userModel.index(userIndex, 0), Qt.UserRole + 1) || ""
    readonly property string realName: userModel.data(userModel.index(userIndex, 0), Qt.UserRole + 2) || ""

    // Prefer the uwsm-managed Hyprland session
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
        if (userCount > 1) userIndex = (userIndex + step + userCount) % userCount
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
            font.family: root.font; font.pixelSize: 80; font.weight: Font.Light
            color: root.fg
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(root.now, "dddd, MMMM d")
            font.family: root.font; font.pixelSize: 15
            color: root.dim
        }

        Item { width: 1; height: 48 }

        // Only on multi-user machines: click it or press Up/Down to switch
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.userCount > 1
            bottomPadding: 12
            text: root.realName || root.userName
            font.family: root.font; font.pixelSize: 15
            color: root.fg
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cycleUser(1)
            }
        }

        Rectangle {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            width: 300; height: 44
            radius: height / 2
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
                text: "Password"
                font.family: root.font; font.pixelSize: 14
                color: root.dim
            }

            TextInput {
                id: password
                anchors { fill: parent; leftMargin: 22; rightMargin: 22 }
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                echoMode: TextInput.Password
                passwordCharacter: "•"
                font.family: root.font; font.pixelSize: 16; font.letterSpacing: 3
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

        // Fixed-height slot so the layout doesn't jump when the message appears
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: field.width; height: 32
            Text {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                visible: root.failed
                text: "Wrong password"
                font.family: root.font; font.pixelSize: 13
                color: root.error
            }
        }
    }

    Component.onCompleted: password.forceActiveFocus()
}
