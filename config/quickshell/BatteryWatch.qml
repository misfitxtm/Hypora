import Quickshell
import Quickshell.Services.UPower
import QtQuick

// Low battery warnings at 20% and 10% and a suspend at 5% to protect the filesystem; each fires once per discharge.
Scope {
    id: root

    // UPower's DisplayDevice is a made-up composite, so prefer a real battery from UPower.devices.
    readonly property var dev: {
        const real = (UPower.devices?.values ?? []).find(d => d && d.isLaptopBattery && d.ready)
        return real ?? UPower.displayDevice
    }

    // `ready` tells a real reading from a placeholder that would show 100% while the battery drains.
    readonly property bool valid: dev !== null && dev !== undefined
                                  && dev.ready === true && dev.isLaptopBattery === true
    readonly property bool isBattery: valid
    readonly property bool discharging: valid && dev.state === UPowerDeviceState.Discharging
    // No numeric fallback: 1.0 would hide the warning and 0.0 would suspend, so everything checks `valid`.
    readonly property real charge: valid ? dev.percentage : -1

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

        if (charge < 0) return          // no usable reading; say nothing
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
        // Check `valid` again when it fires: a suspend on a reading that has gone away cannot be undone.
        onTriggered: if (root.valid && root.discharging && root.charge >= 0
                         && root.charge <= root.suspendAt)
                         Quickshell.execDetached(["systemctl", "suspend"])
    }
}
