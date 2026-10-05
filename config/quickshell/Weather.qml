import Quickshell
import Quickshell.Io
import QtQuick

// Weather, left of the clock. Click for conditions and a short forecast.
//
// Hypora never guesses where you are: there is no IP lookup. You pick a place by name,
// which is the only thing sent, and the coordinates are kept in
// ~/.config/hypora/weather.json. Until you pick one, no weather request is made at all.
Rectangle {
    id: root
    required property var window

    property var place: null        // { name, detail, latitude, longitude }
    property string unit: "C"
    property var report: null       // whatever hypora-weather fetch returned
                                // (not `data` — that's Item's own children list)
    property string error: ""
    property bool searching: false
    property var results: []

    readonly property string bin: Quickshell.env("HOME") + "/.local/bin/hypora-weather"
    readonly property bool configured: place !== null

    implicitWidth: configured ? row.implicitWidth + 16 : 26
    implicitHeight: 24
    radius: height / 2
    color: drop.open ? Theme.surface : (area.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")

    // At night a clear sky is a moon, not a sun
    function iconFor(name, isDay) {
        if (name === "clear") return isDay === false ? "moon" : "sun"
        return name
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.report ? root.iconFor(root.report.current.icon, root.report.current.isDay) : "cloud"
            size: 15
            color: root.configured && root.report ? Theme.fg : Theme.dim
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.configured
            text: root.report ? `${root.report.current.temp}°` : (root.error !== "" ? "--" : "…")
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            color: Theme.fg
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: drop.open = true
    }

    // ---------- saved place ----------
    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.config/hypora/weather.json"
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const saved = JSON.parse(text())
                if (saved && saved.latitude !== undefined) {
                    root.place = saved
                    root.unit = saved.unit || "C"
                    root.refresh()
                }
            } catch (e) {
                // no place picked yet
            }
        }
    }

    function save() {
        file.setText(JSON.stringify(Object.assign({}, place, { unit: unit }), null, 2) + "\n")
    }

    function choose(p) {
        place = p
        results = []
        query.text = ""
        save()
        refresh()
    }

    function setUnit(u) {
        if (unit === u) return
        unit = u
        if (place) { save(); refresh() }
    }

    function forget() {
        place = null
        report = null
        error = ""
        file.setText("{}\n")
    }

    // ---------- fetching ----------
    function refresh() {
        if (!place || fetch.running) return
        fetch.command = [bin, "fetch", String(place.latitude), String(place.longitude), unit.toLowerCase()]
        fetch.running = true
    }

    Process {
        id: fetch
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    if (d.error) { root.error = "Couldn't reach the weather service."; return }
                    root.report = d
                    root.error = ""
                } catch (e) {
                    root.error = "Couldn't read the weather reply."
                }
            }
        }
    }

    Process {
        id: search
        stdout: StdioCollector {
            onStreamFinished: {
                root.searching = false
                try {
                    const d = JSON.parse(text)
                    root.results = d.results || []
                } catch (e) {
                    root.results = []
                }
            }
        }
    }

    Timer { id: debounce; interval: 450; onTriggered: root.lookup() }
    function lookup() {
        const q = query.text.trim()
        if (q.length < 2) { results = []; searching = false; return }
        if (search.running) search.running = false
        searching = true
        search.command = [bin, "search", q]
        search.running = true
    }

    // Refresh every 15 minutes while a place is set
    Timer { running: root.configured; repeat: true; interval: 900000; onTriggered: root.refresh() }

    Dropdown {
        id: drop
        screen: root.window.screen
        barHeight: root.window.height
        onVisibleChanged: if (visible) { if (root.configured) root.refresh(); else query.forceActiveFocus() }

        Rectangle {
            implicitWidth: 320
            implicitHeight: content.implicitHeight + 32
            radius: 16
            color: Theme.bg
            border.width: 1
            border.color: Theme.surface

            Column {
                id: content
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 10

                // ---- current conditions ----
                Item {
                    width: parent.width
                    height: root.configured ? 64 : 0
                    visible: root.configured

                    Icon {
                        id: bigIcon
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        name: root.report ? root.iconFor(root.report.current.icon, root.report.current.isDay) : "cloud"
                        size: 42
                        color: Theme.accent
                    }
                    Column {
                        anchors { left: bigIcon.right; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        Text {
                            text: root.report ? `${root.report.current.temp}°${root.report.unit}` : "—"
                            font.family: Theme.font; font.pixelSize: 26
                            color: Theme.fg
                        }
                        Text {
                            text: root.report ? root.report.current.label : (root.error !== "" ? root.error : "Loading…")
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                            color: root.error !== "" ? Theme.error : Theme.dim
                        }
                    }
                    Column {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        visible: root.report !== null
                        Text {
                            anchors.right: parent.right
                            text: root.report ? `Feels ${root.report.current.feelsLike}°` : ""
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
                            color: Theme.dim
                        }
                        Text {
                            anchors.right: parent.right
                            text: root.report ? `${root.report.current.humidity}% humidity` : ""
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
                            color: Theme.dim
                        }
                        Text {
                            anchors.right: parent.right
                            text: root.report ? `${root.report.current.wind} ${root.report.windUnit}` : ""
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
                            color: Theme.dim
                        }
                    }
                }

                // ---- next few days ----
                Row {
                    width: parent.width
                    visible: root.report !== null && root.report.days.length > 1
                    spacing: 0

                    Repeater {
                        model: root.report ? root.report.days.slice(1) : []
                        Column {
                            required property var modelData
                            width: content.width / Math.max(1, (root.report ? root.report.days.length - 1 : 1))
                            spacing: 3
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Qt.formatDate(new Date(parent.modelData.date + "T12:00:00"), "ddd")
                                font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
                                color: Theme.dim
                            }
                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                name: parent.modelData.icon === "clear" ? "sun" : parent.modelData.icon
                                size: 18
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: `${parent.modelData.max}° ${parent.modelData.min}°`
                                font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
                                color: Theme.fg
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width; height: 1
                    visible: root.configured
                    color: Theme.surface
                }

                // ---- place and units ----
                Item {
                    width: parent.width
                    height: 24
                    visible: root.configured

                    Text {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        width: parent.width - 110
                        elide: Text.ElideRight
                        text: root.place ? root.place.name + (root.place.detail ? ", " + root.place.detail : "") : ""
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                        color: Theme.dim
                    }
                    Row {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: 4
                        Repeater {
                            model: ["C", "F"]
                            Rectangle {
                                required property string modelData
                                readonly property bool on: root.unit === modelData
                                width: 26; height: 22; radius: 11
                                color: on ? Theme.accent : Theme.surface
                                Text {
                                    anchors.centerIn: parent
                                    text: "°" + parent.modelData
                                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 3; font.bold: parent.on
                                    color: parent.on ? Theme.bg : Theme.fg
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setUnit(parent.modelData)
                                }
                            }
                        }
                        Rectangle {
                            width: 26; height: 22; radius: 11
                            color: changeArea.containsMouse ? Qt.lighter(Theme.surface, 1.3) : Theme.surface
                            Icon { anchors.centerIn: parent; name: "search"; size: 12; color: Theme.fg }
                            MouseArea {
                                id: changeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.forget(); query.forceActiveFocus() }
                            }
                        }
                    }
                }

                // ---- picking a place ----
                Text {
                    width: parent.width
                    visible: !root.configured
                    wrapMode: Text.Wrap
                    text: "Search for your city. Only the name you type is sent — Hypora never looks up your location from your IP address."
                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
                    color: Theme.dim
                }

                Rectangle {
                    width: parent.width
                    height: 36
                    visible: !root.configured
                    radius: 18
                    color: Theme.surface
                    border.width: 1
                    border.color: query.activeFocus ? Theme.accent : "transparent"

                    Icon {
                        id: qIcon
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        name: "search"; size: 13; color: Theme.dim
                    }
                    TextInput {
                        id: query
                        anchors { left: qIcon.right; right: parent.right; leftMargin: 10; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                        color: Theme.fg
                        selectionColor: Theme.accent
                        clip: true
                        onTextChanged: debounce.restart()
                        Keys.onEscapePressed: drop.open = false

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: query.text === ""
                            text: "City name"
                            font: query.font
                            color: Theme.dim
                        }
                    }
                }

                Column {
                    width: parent.width
                    visible: !root.configured
                    spacing: 1

                    Text {
                        visible: root.searching || (query.text.trim().length >= 2 && root.results.length === 0)
                        leftPadding: 10
                        topPadding: 6
                        text: root.searching ? "Searching…" : "Nothing found."
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                        color: Theme.dim
                    }

                    Repeater {
                        model: root.results
                        Rectangle {
                            required property var modelData
                            width: parent.width
                            height: 34
                            radius: 8
                            color: hit.containsMouse ? Theme.surface : "transparent"
                            Text {
                                anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                elide: Text.ElideRight
                                text: parent.modelData.name + (parent.modelData.detail ? "  ·  " + parent.modelData.detail : "")
                                font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                                color: Theme.fg
                            }
                            MouseArea {
                                id: hit
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.choose(parent.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
