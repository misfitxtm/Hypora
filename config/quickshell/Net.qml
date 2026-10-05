pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// NetworkManager status via nmcli. Refreshes on every `nmcli monitor` event, plus a slow poll.
Singleton {
    id: root
    property string type: ""          // "wifi", "ethernet", or "" when offline
    property string ssid: ""
    property real strength: 0         // wifi signal, 0..1
    property bool hasWifi: false
    property bool wifiEnabled: false

    readonly property string icon: type === "ethernet" ? "ethernet"
                                 : type === "wifi" ? "wifi" : "wifi-off"

    function refresh() { if (!poll.running) poll.running = true }

    function setWifiEnabled(on) {
        wifiEnabled = on
        Quickshell.execDetached(["nmcli", "radio", "wifi", on ? "on" : "off"])
    }

    function parse(text) {
        const [devices, radio, scan] = text.split("\n--\n")
        let type = "", ssid = "", hasWifi = false
        for (const line of (devices ?? "").split("\n")) {
            // -t output escapes ':' inside fields as '\:'
            const [t, state, ...rest] = line.split(/(?<!\\):/)
            if (t === "wifi") hasWifi = true
            if (!state?.startsWith("connected")) continue
            if (t === "wifi" && type !== "ethernet") { type = "wifi"; ssid = rest.join(":").replace(/\\:/g, ":") }
            if (t === "ethernet") type = "ethernet"
        }
        let strength = 0
        for (const line of (scan ?? "").split("\n"))
            if (line.startsWith("*:")) strength = parseInt(line.slice(2)) / 100
        root.type = type
        root.ssid = ssid
        root.hasWifi = hasWifi
        root.wifiEnabled = (radio ?? "").trim() === "enabled"
        root.strength = strength
    }

    Process {
        id: poll
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE,CONNECTION device status; echo --; nmcli radio wifi; echo --; "
                            + "nmcli -t -f IN-USE,SIGNAL device wifi list --rescan no"]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }

    Process {
        id: monitor
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser { onRead: soon.restart() }
        onRunningChanged: if (!running) restartMonitor.start()   // NetworkManager restarted
    }
    Timer { id: restartMonitor; interval: 5000; onTriggered: monitor.running = true }

    Timer { id: soon; interval: 300; onTriggered: root.refresh() }
    Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
}
