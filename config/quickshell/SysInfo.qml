pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Live RAM / CPU / GPU readings, plus which of them the bar widget shows.
// The numbers come from bin/hypora-sysinfo, which prints a line of JSON on a timer.
// Your choice of readings is kept in ~/.config/hypora/sysinfo.json.
Singleton {
    id: root

    property var ram: null      // { pct, usedGb, totalGb }
    property var cpu: null      // { pct, temp }
    property var gpu: null      // { pct, temp, name }
    property bool ready: false

    readonly property bool hasGpu: gpu !== null
    readonly property bool hasCpuTemp: cpu !== null && cpu.temp !== null
    readonly property bool hasGpuTemp: gpu !== null && gpu.temp !== null
    readonly property bool hasGpuUsage: gpu !== null && gpu.pct !== null

    // Every reading the widget can show, in the order it shows them
    readonly property var items: [
        { key: "ram",      label: "RAM usage",   icon: "memory",      available: ram !== null },
        { key: "cpuUsage", label: "CPU usage",   icon: "cpu",         available: cpu !== null && cpu.pct !== null },
        { key: "cpuTemp",  label: "CPU temp",    icon: "thermometer", available: hasCpuTemp },
        { key: "gpuUsage", label: "GPU usage",   icon: "gpu",         available: hasGpuUsage },
        { key: "gpuTemp",  label: "GPU temp",    icon: "thermometer", available: hasGpuTemp }
    ]

    // Defaults: the three that exist on nearly every machine
    property var shown: ({ ram: true, cpuUsage: true, cpuTemp: true, gpuUsage: false, gpuTemp: false })

    function enabled(key) { return shown[key] === true }

    function toggle(key) {
        const next = Object.assign({}, shown)
        next[key] = !next[key]
        shown = next
        settings.setText(JSON.stringify(next, null, 2) + "\n")
    }

    // Text shown next to each icon
    function value(key) {
        switch (key) {
        case "ram":      return ram ? Math.round(ram.pct) + "%" : "--"
        case "cpuUsage": return cpu && cpu.pct !== null ? Math.round(cpu.pct) + "%" : "--"
        case "cpuTemp":  return cpu && cpu.temp !== null ? Math.round(cpu.temp) + "°" : "--"
        case "gpuUsage": return gpu && gpu.pct !== null ? Math.round(gpu.pct) + "%" : "--"
        case "gpuTemp":  return gpu && gpu.temp !== null ? Math.round(gpu.temp) + "°" : "--"
        }
        return ""
    }

    // Longer text for the menu rows
    function detail(key) {
        switch (key) {
        case "ram":      return ram ? `${ram.usedGb} / ${ram.totalGb} GB` : ""
        case "gpuUsage":
        case "gpuTemp":  return gpu && gpu.name ? gpu.name : ""
        }
        return ""
    }

    // Warm colours once a reading gets high
    function tone(key) {
        const v = key === "ram" ? ram?.pct
                : key === "cpuUsage" ? cpu?.pct
                : key === "cpuTemp" ? cpu?.temp
                : key === "gpuUsage" ? gpu?.pct
                : gpu?.temp
        if (v === null || v === undefined) return Theme.dim
        const hot = key.endsWith("Temp") ? 85 : 90
        const warm = key.endsWith("Temp") ? 70 : 75
        return v >= hot ? Theme.error : v >= warm ? Theme.accent : Theme.fg
    }

    FileView {
        id: settings
        path: Quickshell.env("HOME") + "/.config/hypora/sysinfo.json"
        watchChanges: true
        printErrors: false
        // Read synchronously: this singleton is created on first use, so an async load
        // would briefly hand the bar the defaults instead of your saved choice.
        blockLoading: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const saved = JSON.parse(text())
                if (saved && typeof saved === "object") root.shown = Object.assign({}, root.shown, saved)
            } catch (e) {
                // keep the defaults if the file is missing or malformed
            }
        }
    }

    Process {
        id: poll
        command: [Quickshell.env("HOME") + "/.local/bin/hypora-sysinfo", "2"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const d = JSON.parse(line)
                    root.ram = d.ram
                    root.cpu = d.cpu
                    root.gpu = d.gpu
                    root.ready = true
                } catch (e) {
                    // a partial line; the next one will be whole
                }
            }
        }
        // If it dies (killed, or the script is missing), try again rather than go silent
        onRunningChanged: if (!running) restart.start()
    }
    Timer { id: restart; interval: 10000; onTriggered: poll.running = true }
}
