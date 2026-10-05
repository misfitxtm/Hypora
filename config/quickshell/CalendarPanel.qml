import Quickshell
import QtQuick
import QtQuick.Layouts

// Clock and month calendar, opened from the clock in the middle of the bar.
// Arrows (or scrolling) change the month; clicking the month name returns to today.
Rectangle {
    id: root

    property int viewYear: clock.date.getFullYear()
    property int viewMonth: clock.date.getMonth()    // 0-11

    // Called each time the panel opens
    function reset() {
        viewYear = clock.date.getFullYear()
        viewMonth = clock.date.getMonth()
    }

    function shift(months) {
        const d = new Date(viewYear, viewMonth + months, 1)
        viewYear = d.getFullYear()
        viewMonth = d.getMonth()
    }

    readonly property int firstDay: Qt.locale().firstDayOfWeek % 7    // 0 = Sunday

    // 6 weeks of dates covering the viewed month
    readonly property var days: {
        const first = new Date(viewYear, viewMonth, 1)
        const offset = (first.getDay() - firstDay + 7) % 7
        return Array.from({ length: 42 }, (_, i) => new Date(viewYear, viewMonth, 1 - offset + i))
    }

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
    }

    SystemClock { id: clock; precision: SystemClock.Seconds }

    implicitWidth: 300
    implicitHeight: column.implicitHeight + 36
    radius: 16
    color: Theme.bg
    border.width: 1
    border.color: Theme.surface

    ColumnLayout {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
        spacing: 4

        // Clock
        Row {
            Layout.alignment: Qt.AlignHCenter
            Text {
                text: Qt.formatTime(clock.date, "HH:mm")
                font.family: Theme.font; font.pixelSize: 44; font.weight: Font.Light
                color: Theme.fg
            }
            Text {
                anchors.baseline: parent.children[0].baseline
                leftPadding: 4
                text: Qt.formatTime(clock.date, "ss")
                font.family: Theme.font; font.pixelSize: 18
                color: Theme.dim
            }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 14
            text: Qt.formatDate(clock.date, "dddd, MMMM d, yyyy")
            font.family: Theme.font; font.pixelSize: Theme.fontSize
            color: Theme.accent
        }

        // Month header
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 6

            NavButton { icon: "chevron-left"; onClicked: root.shift(-1) }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
                font.family: Theme.font; font.pixelSize: Theme.fontSize + 1; font.bold: true
                color: Theme.fg
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.reset()
                }
            }
            NavButton { icon: "chevron"; onClicked: root.shift(1) }
        }

        // Weekday names and days
        Grid {
            id: grid
            Layout.alignment: Qt.AlignHCenter
            columns: 7
            columnSpacing: 2
            rowSpacing: 2

            readonly property real cell: 36

            Repeater {
                model: 7
                Text {
                    required property int index
                    width: grid.cell
                    height: 24
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.locale().dayName((root.firstDay + index) % 7, Locale.ShortFormat).slice(0, 2)
                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 3; font.bold: true
                    color: Theme.dim
                }
            }

            Repeater {
                model: root.days
                Rectangle {
                    id: day
                    required property var modelData
                    readonly property bool today: root.sameDay(modelData, clock.date)
                    readonly property bool inMonth: modelData.getMonth() === root.viewMonth
                    width: grid.cell
                    height: grid.cell - 4
                    radius: height / 2
                    color: today ? Theme.accent : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: day.modelData.getDate()
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1; font.bold: day.today
                        color: day.today ? Theme.bg : day.inMonth ? Theme.fg : Theme.dim
                        opacity: day.inMonth || day.today ? 1 : 0.5
                    }
                }
            }
        }
    }

    // Scroll anywhere on the panel to change month
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: w => root.shift(w.angleDelta.y > 0 ? -1 : 1)
    }

    component NavButton: Rectangle {
        id: nav
        property string icon
        signal clicked()
        implicitWidth: 30
        implicitHeight: 30
        radius: 15
        color: navArea.containsMouse ? Theme.surface : "transparent"
        Icon {
            anchors.centerIn: parent
            name: nav.icon
            size: 16
            color: Theme.fg
        }
        MouseArea {
            id: navArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: nav.clicked()
        }
    }
}
