import Quickshell
import Quickshell.Services.UPower
import QtQuick

// Low battery warnings, and a suspend before the machine dies mid-write.
//
// Battery.qml only colours the bar indicator red, which you have to be looking at. This
// watches the charge and says something: a notification at 20% and 10%, and at 5% it
// suspends, because a laptop that runs flat while writing to disk is how filesystems get
// damaged. Suspending is recoverable; losing power is not always.
//
// Each threshold fires once per discharge. Plugging in resets them, so a battery hovering
// around a threshold can't produce a stream of notifications.
Scope {
    id: root

    readonly property var dev: UPower.displayDevice
    readonly property bool isBattery: dev && dev.isLaptopBattery
    readonly property bool discharging: dev && dev.state === UPowerDeviceState.Discharging
    readonly property real charge: dev ? dev.percentage : 1.0

    // Fractions, not percentages, to match UPower's own scale
    readonly property real warnAt: 0.20
    readonly property real urgentAt: 0.10
    readonly property real suspendAt: 0.05

    property bool warned: false
    property bool urged: false
    property bool suspending: false

    function notify(urgency, title, body) {
        Quickshell.execDetached(["notify-send", "-a", "Hypora", "-u", urgency,
                                 "-i", "battery-caution", title, body])
    }

    function minutesLeft() {
        // UPower reports seconds; it is 0 while it still has no estimate
        const s = dev ? dev.timeToEmpty : 0
        if (!s || s <= 0) return ""
        const m = Math.round(s / 60)
        return m >= 60 ? ` About ${Math.floor(m / 60)}h ${m % 60}m left.`
                       : ` About ${m} minutes left.`
    }

    onChargeChanged: check()
    onDischargingChanged: check()

    function check() {
        if (!isBattery) return

        // Back on mains: forget what we've said so the next discharge warns again
        if (!discharging) {
            warned = false
            urged = false
            suspending = false
            return
        }

        const pct = Math.round(charge * 100)

        if (charge <= suspendAt && !suspending) {
            suspending = true
            notify("critical", "Battery critically low",
                   `${pct}% — suspending now so nothing is lost. Plug in before resuming.`)
            // A moment for the notification to be seen, then save the session
            suspendSoon.start()
        } else if (charge <= urgentAt && !urged) {
            urged = true
            notify("critical", "Battery very low",
                   `${pct}% left.${minutesLeft()} The machine will suspend itself at 5%.`)
        } else if (charge <= warnAt && !warned) {
            warned = true
            notify("normal", "Battery low", `${pct}% left.${minutesLeft()}`)
        }
    }

    Timer {
        id: suspendSoon
        interval: 8000
        onTriggered: if (root.discharging && root.charge <= root.suspendAt)
                         Quickshell.execDetached(["systemctl", "suspend"])
    }
}
