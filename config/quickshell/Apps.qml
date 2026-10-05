pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Installed applications: search, categories and launching.
// Shared by the launcher (SUPER + R) and the app menu.
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

    readonly property var all: DesktopEntries.applications.values
        .filter(e => !e.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))

    // Categories that at least one installed app belongs to
    readonly property var categories: allCategories.filter(c => all.some(e => e.categories.includes(c.id)))

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

    // Run a shell command line in the theme's terminal. If it exits non-zero, hold the
    // window open: terminal tools like impala and bluetui print why they can't start and
    // quit straight away, and without this the window vanishes before you can read it.
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
}
