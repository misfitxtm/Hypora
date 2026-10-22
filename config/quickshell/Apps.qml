pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Installed applications: search, categories and launching, shared by the launcher and the app menu.
Singleton {
    id: root
    property bool useUwsm: false

    // Main freedesktop categories shown in the app menu, in display order
    readonly property var allCategories: [
        { id: "Network", label: "Internet" },
        { id: "Office", label: "Office" },
        { id: "Graphics", label: "Graphics" },
        { id: "AudioVideo", label: "Multimedia" },
        { id: "Development", label: "Development" },
        { id: "Game", label: "Games" },
        { id: "Education", label: "Education" },
        { id: "Science", label: "Science" },
        { id: "Utility", label: "Utilities" },
        { id: "System", label: "System" },
        { id: "Settings", label: "Settings" }
    ]

    // Leave control panels out: the Settings category is the only signal Quickshell exposes, and they are GNOME panels.
    function isSettings(entry) { return entry.categories.includes("Settings") }

    readonly property var byName: DesktopEntries.applications.values
        .filter(e => !e.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))

    // Everyday apps: what the launcher and the menu's Apps section show
    readonly property var all: byName.filter(e => !isSettings(e))

    // Categories that at least one installed app belongs to
    readonly property var categories: allCategories.filter(c => all.some(e => e.categories.includes(c.id)))

    // Order categories by how specific they are; System and Utility are fallbacks, so they go last.
    readonly property var describeCategories: [
        "AudioVideo", "Audio", "Video", "Development", "Education", "Game",
        "Graphics", "Network", "Office", "Science", "Settings", "System", "Utility"
    ]

    // One short phrase per app: GenericName, then Comment, then the main category, since under half set GenericName.
    function describe(entry) {
        if (!entry) return ""
        if (entry.genericName) return entry.genericName
        if (entry.comment) return entry.comment
        const cats = entry.categories || []
        for (const c of describeCategories)
            if (cats.includes(c)) return c
        return ""
    }

    // Lower rank = better match; -1 = no match
    function rank(entry, q) {
        const name = entry.name.toLowerCase()
        if (name.startsWith(q)) return 0
        if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q))) return 1
        if (name.includes(q)) return 2
        const extra = [entry.genericName, entry.comment, ...entry.keywords].join(" ").toLowerCase()
        return extra.includes(q) ? 3 : -1
    }

    // Apps matching `text` (ranked), or every app in `category` ("" = all) when text is empty
    function query(text, category) {
        const q = text.trim().toLowerCase()
        if (q === "") return category ? all.filter(e => e.categories.includes(category)) : all
        return all.map(e => ({ e, r: rank(e, q) }))
                  .filter(x => x.r >= 0)
                  .sort((a, b) => a.r - b.r || a.e.name.localeCompare(b.e.name))
                  .map(x => x.e)
    }

    // Run a command; in a uwsm session each app gets its own systemd unit
    function run(argv) {
        Quickshell.execDetached(useUwsm ? ["uwsm", "app", "--", ...argv] : argv)
    }

    // Run a command line in the theme's terminal and keep the window open on a non-zero exit.
    readonly property string holdOnError:
        '; rc=$?; if [ $rc -ne 0 ]; then printf "\\n[exited with status %s]\\nPress Enter to close. " "$rc"; read _; fi'

    function inTerminal(cmd) {
        run([Theme.terminal, "-e", "sh", "-c", cmd + holdOnError])
    }

    function launch(entry) {
        if (entry.runInTerminal) run([Theme.terminal, "-e", ...entry.command])
        else if (useUwsm) run([entry.id + ".desktop"])
        else entry.execute()
    }

    Process {
        command: ["uwsm", "check", "is-active"]
        running: true
        onExited: code => root.useUwsm = code === 0
    }

    // The installer asks before installing Claude Code, so check once at startup; reload the shell after installing.
    property bool hasClaude: false
    Process {
        command: ["sh", "-c", "command -v claude"]
        running: true
        onExited: code => root.hasClaude = code === 0
    }

    // Both must hold or the entry is a dead end: fprintd installed and reporting a device, since a reader may not be supported.
    property bool hasFingerprint: false
    Process {
        command: ["sh", "-c",
                  "command -v fprintd-enroll >/dev/null && hypora-hardware fingerprint >/dev/null 2>&1"]
        running: true
        onExited: code => root.hasFingerprint = code === 0
    }
}
