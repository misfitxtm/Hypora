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

    // Control panels are dropped from the menu and launcher entirely. The freedesktop
    // Settings category is the only signal available here — Quickshell doesn't expose
    // OnlyShowIn — and on a Hyprland session these are GNOME's own panels, built for a
    // shell that isn't running. Hypora's Settings section lists its own windows instead.
    // This does not touch Files, Calculator, Disks or Software, which are plain apps.
    function isSettings(entry) { return entry.categories.includes("Settings") }

    readonly property var byName: DesktopEntries.applications.values
        .filter(e => !e.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))

    // Everyday apps: what the launcher and the menu's Apps section show
    readonly property var all: byName.filter(e => !isSettings(e))

    // Categories that at least one installed app belongs to
    readonly property var categories: allCategories.filter(c => all.some(e => e.categories.includes(c.id)))

    // Categories in order of how much they actually say about an app. System and Utility
    // come last because they're what a .desktop file falls back to when it has nothing more
    // specific to offer, so "Network" is a better answer than "Utility" for something
    // claiming both.
    readonly property var describeCategories: [
        "AudioVideo", "Audio", "Video", "Development", "Education", "Game",
        "Graphics", "Network", "Office", "Science", "Settings", "System", "Utility"
    ]

    // One short phrase saying what an app is, for the launcher's right-hand column.
    //
    // GenericName is the field meant for exactly this, but fewer than half the .desktop
    // files on a Fedora system set it — so the column was simply blank for things like
    // Calculator, Disks and Document Viewer. Comment is set by most of the rest and reads
    // well enough here; failing both, the app's main category at least places it.
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

    // Run a shell command line in the theme's terminal. If it exits non-zero, hold the
    // window open: a terminal tool that can't start prints why and quits straight away,
    // and without this the window vanishes before you can read it.
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

    // The installer asks before installing Claude Code and defaults to no, so the menu has
    // to find out rather than assume. Checked once at startup; installing it later shows up
    // after a shell reload.
    property bool hasClaude: false
    Process {
        command: ["sh", "-c", "command -v claude"]
        running: true
        onExited: code => root.hasClaude = code === 0
    }
}
