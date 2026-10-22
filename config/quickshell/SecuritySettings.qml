import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts

// Security and privacy: privileged changes go through the root-owned /usr/local/bin/hypora-security via pkexec.
Scope {
    id: root

    IpcHandler {
        target: "security"
        function open(): void { ShellState.securitySettingsOpen = true }
        function close(): void { ShellState.securitySettingsOpen = false }
    }

    LazyLoader {
        active: ShellState.securitySettingsOpen

        FloatingWindow {
            id: win
            title: "Security & Privacy"
            implicitWidth: 620
            implicitHeight: 760
            color: Theme.bg
            onClosed: ShellState.securitySettingsOpen = false

            property var info: null
            property var deepInfo: null        // result of the one privileged pass, if run
            property bool deepRunning: false
            // Tracked per reading, not as one flag: the pass can return one half and not the other.
            readonly property bool haveFirmware: deepInfo !== null && !!deepInfo.firmware
            readonly property bool haveFirewallDetail: deepInfo !== null
                                                       && !!deepInfo.firewallDetail
                                                       && !deepInfo.firewallDetail.note
            readonly property bool deep: haveFirmware || haveFirewallDetail
            property bool loading: true
            property string notice: ""

            readonly property var source: Pipewire.defaultAudioSource
            readonly property var micAudio: source ? source.audio : null
            PwObjectTracker { objects: win.source ? [win.source] : [] }

            // Only the unprivileged pass; deepInfo is separate so a refresh never blanks rows or re-asks for a password.
            function refresh() {
                if (probe.running) return
                loading = info === null
                probe.running = true
            }

            // Privileged changes use pkexec with an argv list, not a shell string, and the helper checks each value.
            readonly property string helper: "/usr/local/bin/hypora-security"

            // What the user just asked for, shown before the system catches up; the next reading clears it and failure rolls it back.
            property var pending: ({})

            function setPending(key, value) {
                pending = Object.assign({}, pending, { [key]: value })
            }
            function dropPending(keys) {
                const p = Object.assign({}, pending)
                for (const k of keys) delete p[k]
                pending = p
            }
            // Rows call this instead of reading the status object directly
            function shown(key, actual) {
                return pending[key] === undefined ? actual : pending[key]
            }

            // One process for changes, so the refresh runs as soon as the change is done (no timer).
            Process {
                id: action
                property var keys: []
                property string label: ""
                stderr: StdioCollector { id: actionErr }
                onExited: code => {
                    if (code === 0) {
                        // Show the output even when the command worked: it can still hold a warning worth reading.
                        const said = actionErr.text.trim()
                        win.notice = said !== "" ? said.split("\n")[0] : ""
                    } else {
                        // It did not happen, so stop claiming it did
                        win.dropPending(action.keys)
                        const why = actionErr.text.trim()
                        win.notice = code === 126 ? "Authentication cancelled."
                                   : why !== "" ? why
                                   : action.label + " did not work."
                    }
                    win.refresh()
                }
            }

            // `key` and `optimistic` are optional: pass them only for a row whose control should move at once.
            function admin(args, what, key, optimistic) {
                if (action.running) return
                notice = what
                action.keys = key === undefined ? [] : [key]
                if (key !== undefined) setPending(key, optimistic)
                action.label = what
                action.command = ["pkexec", helper].concat(args)
                action.running = true
            }

            // Same as admin(), without pkexec: these are the user's own settings.
            Process {
                id: userAction
                property var keys: []
                onExited: code => {
                    if (code !== 0) win.dropPending(userAction.keys)
                    win.refresh()
                }
            }

            function userRun(args, key, optimistic) {
                if (userAction.running) return
                userAction.keys = key === undefined ? [] : [key]
                if (key !== undefined) setPending(key, optimistic)
                userAction.command = args
                userAction.running = true
            }

            function gsettingsSet(key, value, pendingKey, optimistic) {
                userRun(["gsettings", "set", "org.gnome.desktop.privacy", key, value],
                        pendingKey, optimistic)
            }

            // Plain `status` cannot reach polkit, so it is safe any time; the two privileged readings come below.
            Process {
                id: probe
                command: [win.helper, "status"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try { win.info = JSON.parse(text) } catch (e) { win.info = null }
                        win.loading = false
                        // This reading is now the truth, but not while a change is running or it would flip the control back.
                        if (!action.running && !userAction.running) win.pending = ({})
                    }
                }
                onExited: code => { if (code !== 0 && win.info === null) win.loading = false }
            }

            // The two root readings go in one process for one password prompt; the shell itself never runs as root.
            Process {
                id: deepProbe
                command: ["pkexec", win.helper, "deep"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try { win.deepInfo = JSON.parse(text) } catch (e) { win.deepInfo = null }
                    }
                }
                onExited: code => {
                    win.deepRunning = false
                    // 126 is pkexec's "dismissed or not authorised"; saying so beats a blank row
                    win.notice = win.deepInfo !== null ? ""
                               : code === 126 ? "Authentication cancelled."
                               : "The deeper checks did not complete."
                }
            }

            function runDeep() {
                if (deepProbe.running) return
                deepRunning = true
                notice = "Asking for permission…"
                deepProbe.running = true
            }

            // No periodic refresh: a timer once caused a password prompt every fifteen seconds.
            Component.onCompleted: refresh()

            Rectangle {
                id: page
                anchors.fill: parent
                color: Theme.bg

                ColumnLayout {
                    anchors { fill: parent; margins: 22 }
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: "Security & Privacy"
                            font.family: Theme.font; font.pixelSize: Theme.fontSize + 9; font.bold: true
                            color: Theme.fg
                        }
                        Text {
                            visible: win.notice !== ""
                            text: win.notice
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                            color: Theme.dim
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: win.loading || win.info === null
                        text: win.loading ? "Checking…"
                                          : "Could not read the system's security state. Try running hypora-security status in a terminal."
                        wrapMode: Text.Wrap
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                        color: Theme.dim
                    }

                    Flickable {
                        id: scroller
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        // Page Up / Page Down without the mouse. Focus is safe here: no text input competes.
                        focus: true
                        Keys.onPressed: event => event.accepted = PageScroll.handle(event, scroller)
                        visible: win.info !== null
                        clip: true
                        contentHeight: body.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: body
                            width: parent.width
                            spacing: 4

                            // A banner, not a small button: it unlocks rows in two sections.
                            Rectangle {
                                id: deepBanner
                                Layout.fillWidth: true
                                Layout.bottomMargin: 12
                                implicitHeight: deepRow.implicitHeight + 28
                                radius: 12
                                visible: !win.haveFirmware || !win.haveFirewallDetail
                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.10)
                                border.width: 1
                                border.color: Theme.accent

                                RowLayout {
                                    id: deepRow
                                    anchors { fill: parent; leftMargin: 16; rightMargin: 16;
                                              topMargin: 14; bottomMargin: 14 }
                                    spacing: 14

                                    Icon {
                                        Layout.alignment: Qt.AlignTop
                                        name: "shield-alert"
                                        size: 20
                                        color: Theme.accent
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3
                                        Text {
                                            text: "Two checks still to run"
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontSize
                                            font.bold: true
                                            color: Theme.fg
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: "The firmware security attributes and the firewall's zone need root. "
                                                + "One password prompt covers both; nothing else on this page asks."
                                            wrapMode: Text.Wrap
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontSize - 3
                                            color: Theme.dim
                                        }
                                    }
                                    Pill {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: win.deepRunning ? "Checking…" : "Run checks"
                                        current: !win.deepRunning      // filled, so it reads as the action
                                        enabled: !win.deepRunning
                                        onClicked: win.runDeep()
                                    }
                                }
                            }

                            // Security: the state of the machine; things about you are under Privacy.
                            Heading { text: "Security" }

                            StatusRow {
                                readonly property var sb: win.info ? win.info.secureBoot : null
                                // Setup Mode is its own state, shown amber, because the firmware says Enabled but verifies nothing.
                                readonly property bool sbSetup: sb !== null && !sb.enabled
                                                                && sb.setupMode === true
                                icon: !sb ? "shield" : sb.enabled ? "shield-check" : "shield-alert"
                                tone: !sb ? Theme.dim
                                    : sb.enabled ? Theme.accent
                                    : sbSetup ? Theme.warn : Theme.error
                                title: "Secure Boot"
                                value: !sb ? ""
                                     : !sb.supported ? "Not available"
                                     : sb.enabled ? "On"
                                     : sbSetup ? "Setup Mode"
                                     : "Off"
                                detail: !sb ? ""
                                      : sb.note ? sb.note
                                      : sb.enabled
                                        ? "The firmware checks that the bootloader and kernel are signed before running them."
                                        : "The firmware will run any bootloader. Turn Secure Boot on in your UEFI setup screen."
                            }

                            // Report / and /home separately: encrypting only the volume your files are on is a valid layout.
                            StatusRow {
                                readonly property var enc: win.info ? win.info.encryption : null
                                readonly property int exposed: enc && enc.unencryptedSwap ? enc.unencryptedSwap.length : 0
                                // Your files decide the colour; an unencrypted system volume is only a warning.
                                readonly property bool dataSafe: enc !== null && enc.homeEncrypted
                                readonly property bool allSafe: dataSafe && enc.rootEncrypted && exposed === 0

                                icon: !enc || !enc.available ? "shield"
                                    : allSafe ? "shield-check" : "shield-alert"
                                tone: !enc || !enc.available ? Theme.dim
                                    : !dataSafe ? Theme.error
                                    : allSafe ? Theme.accent : Theme.warn
                                title: "Disk encryption"
                                value: !enc ? "" : !enc.available ? "Unknown"
                                     : enc.rootEncrypted && enc.homeEncrypted ? "On"
                                     : enc.homeEncrypted ? "Home only"
                                     : enc.rootEncrypted ? "System only"
                                     : "Off"
                                detail: {
                                    const e = win.info ? win.info.encryption : null
                                    if (!e) return ""
                                    if (!e.available) return e.note || ""

                                    let where = ""
                                    if (e.rootEncrypted && e.homeEncrypted) {
                                        where = e.homeSeparate
                                            ? `This system (${e.rootDevice}) and your home directory (${e.homeDevice}) are both on encrypted volumes.`
                                            : `This system is on an encrypted volume (${e.rootDevice}).`
                                    } else if (e.homeEncrypted) {
                                        where = `Your home directory is encrypted (${e.homeDevice}), so your own files are protected. `
                                              + `The system volume (${e.rootDevice}) is not: /etc — where NetworkManager keeps Wi-Fi keys — `
                                              + "and /var/log stay readable, and anyone holding the drive can modify the system itself.";
                                    } else if (e.rootEncrypted) {
                                        where = `This system is encrypted (${e.rootDevice}), but /home (${e.homeDevice}) is not, `
                                              + "so your own files are the part that can be read.";
                                    } else {
                                        where = "Nothing is encrypted, so anyone holding the drive can read it. "
                                              + "Encryption can only be turned on when Fedora is installed.";
                                    }

                                    let swap = ""
                                    if (e.unencryptedSwap.length > 0) {
                                        swap = ` Swap on ${e.unencryptedSwap.join(", ")} is not encrypted, `
                                             + "so memory can reach the disk in the clear."
                                    } else {
                                        const rand = (e.swap || []).filter(s => s.randomKey)
                                        if (rand.length > 0)
                                            swap = ` Swap on ${rand.map(s => s.name).join(", ")} is encrypted with `
                                                 + "a key taken from /dev/urandom at boot, so it cannot be read back "
                                                 + "once the machine is off."
                                    }
                                    const files = (e.swapFiles || []).length > 0 && !e.rootEncrypted
                                        ? ` Swap is also in a file (${e.swapFiles.join(", ")}) on an unencrypted filesystem.`
                                        : ""
                                    return where + swap + files
                                }
                            }

                            // Plaintext swap defeats disk encryption, so offer a swapfile on the encrypted root (one nofail fstab line).
                            ColumnLayout {
                                id: swapFix
                                Layout.fillWidth: true
                                Layout.leftMargin: 12
                                Layout.topMargin: 2
                                Layout.bottomMargin: 10
                                spacing: 8

                                readonly property var enc: win.info ? win.info.encryption : null
                                readonly property var sf: enc ? enc.swapfile : null
                                readonly property bool canAdd:
                                    sf !== null && !sf.exists && sf.rootEncrypted && sf.supported
                                readonly property bool haveFile: sf !== null && sf.exists
                                readonly property string exposed:
                                    enc && enc.unencryptedSwap ? enc.unencryptedSwap.join(", ") : ""

                                visible: canAdd || haveFile || exposed !== ""
                                property bool confirming: false

                                // Plaintext swap partitions are reported, not fixed, since removing a partition is destructive.
                                Text {
                                    Layout.fillWidth: true
                                    visible: swapFix.exposed !== ""
                                    text: `Swap on ${swapFix.exposed} is a partition outside the encrypted volume. `
                                        + "The clean fix is to stop using it — remove it at your next install and let "
                                        + "zram handle swap, adding a swapfile here if you ever need more."
                                    wrapMode: Text.Wrap
                                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
                                    color: Theme.warn
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    visible: !swapFix.confirming && (swapFix.canAdd || swapFix.haveFile)
                                    Pill {
                                        text: swapFix.haveFile ? "Remove swapfile" : "Add swapfile"
                                        small: true
                                        onClicked: {
                                            if (swapFix.haveFile)
                                                win.admin(["remove-swapfile"], "Removing the swapfile…")
                                            else
                                                swapFix.confirming = true
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: swapFix.haveFile
                                            ? `${swapFix.sf.path} is in use. It lives inside the encrypted root, so it is encrypted with everything else.`
                                            : "Adds a 4 GB swapfile inside the encrypted root, for when zram is not enough."
                                        wrapMode: Text.Wrap
                                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
                                        color: Theme.dim
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    visible: swapFix.confirming
                                    implicitHeight: confirmCol.implicitHeight + 26
                                    radius: 10
                                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.10)
                                    border.width: 1
                                    border.color: Theme.accent

                                    ColumnLayout {
                                        id: confirmCol
                                        anchors { fill: parent; margins: 13 }
                                        spacing: 6

                                        Text {
                                            text: "Add a 4 GB swapfile?"
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontSize
                                            font.bold: true
                                            color: Theme.fg
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: `Creates ${swapFix.sf ? swapFix.sf.path : "/swap/swapfile"} and switches it on. `
                                                + "On btrfs it goes in a subvolume of its own so snapshots never capture it — "
                                                + "a swapfile caught in a snapshot pins its full size for as long as that "
                                                + "snapshot lives. Nothing else on disk changes except one line in /etc/fstab, "
                                                + "which is backed up first and carries nofail."
                                            wrapMode: Text.Wrap
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontSize - 3
                                            color: Theme.dim
                                        }
                                        RowLayout {
                                            Layout.topMargin: 2
                                            spacing: 8
                                            Pill {
                                                text: "Add swapfile"
                                                current: true
                                                small: true
                                                onClicked: {
                                                    swapFix.confirming = false
                                                    win.admin(["add-swapfile"], "Creating the swapfile…")
                                                }
                                            }
                                            Pill {
                                                text: "Cancel"
                                                small: true
                                                onClicked: swapFix.confirming = false
                                            }
                                            Item { Layout.fillWidth: true }
                                        }
                                    }
                                }
                            }

                            StatusRow {
                                readonly property var fw: win.deepInfo ? win.deepInfo.firmware : null
                                icon: !fw || !fw.available ? "shield"
                                    : fw.failed.length === 0 ? "shield-check" : "shield-alert"
                                tone: !fw || !fw.available ? Theme.dim
                                    : fw.failed.length === 0 ? Theme.accent : Theme.warn
                                title: "Firmware checks"
                                value: win.deepRunning ? "Checking…" : !fw ? "Not checked yet"
                                     : !fw.available ? "Unavailable"
                                     : `${fw.passed} of ${fw.total} passed` + (fw.hsi ? `  ·  ${fw.hsi}` : "")
                                detail: !fw ? "fwupd reads these through a privileged call, so they are left out of "
                                            + "the automatic reading. Use \"Run the deeper checks\" above."
                                      : !fw.available ? fw.note
                                      : fw.failed.length === 0
                                        ? "Every check fwupd knows about passed."
                                        : "Not passing: " + fw.failed.map(f => `${f.name} (${f.result})`).join(", ")
                            }

                            // Firmware updates write to the hardware, so they are a button, never automatic.
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 12
                                Layout.topMargin: 2
                                Layout.bottomMargin: 10
                                spacing: 10
                                Pill {
                                    text: "Check for firmware updates"
                                    small: true
                                    onClicked: {
                                        win.notice = "Firmware updater opened."
                                        // Use --title: Hyprland decides float/pin at map time; Apps.run is used because the script already waits for a key.
                                        Apps.run([Theme.terminal, "--title", "Firmware Update",
                                                  "-e", "hypora-firmware"])
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "Opens a terminal. Checks fwupd.org, then installs what applies."
                                    wrapMode: Text.Wrap
                                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
                                    color: Theme.dim
                                }
                            }

                            StatusRow {
                                readonly property var dns: win.info ? win.info.dns : null
                                icon: !dns || !dns.available ? "shield-alert"
                                    : dns.strict ? "shield-check"
                                    : dns.encrypted ? "shield" : "shield-alert"
                                tone: !dns || !dns.available ? Theme.error
                                    : dns.encrypted ? Theme.accent : Theme.error
                                title: "Encrypted DNS"
                                value: !dns ? "" : !dns.available ? "Off"
                                     : dns.strict ? "On"
                                     : dns.mode === "opportunistic" ? "Opportunistic"
                                     : dns.mode === "unknown" ? "Unknown" : "Off"
                                detail: {
                                    const d = win.info ? win.info.dns : null
                                    if (!d) return ""
                                    if (!d.available) return d.note || ""
                                    const via = d.server ? ` Queries go to ${d.server}.` : ""
                                    if (d.strict) return "Lookups are encrypted to a verified resolver, and fail rather "
                                        + "than falling back to plaintext." + via
                                        + " Captive portals need this relaxed first: resolvectl dnsovertls <interface> opportunistic."
                                    if (d.mode === "opportunistic") return "Lookups are encrypted when the resolver "
                                        + "answers on port 853, and sent in plaintext when it doesn't — which a network "
                                        + "can force by blocking that port, and which a resolver on your own network "
                                        + "(a Pi-hole, a router) normally needs." + via
                                        + " Set DNSOverTLS=yes in /etc/systemd/resolved.conf.d/hypora-dns.conf to refuse plaintext."
                                    if (d.mode === "unknown") return "systemd-resolved is running but didn't say "
                                        + "whether DNS-over-TLS is on." + via
                                    return "Lookups are sent in plaintext, so the network can read and rewrite "
                                        + "which sites you visit." + via
                                }
                            }

                            StatusRow {
                                readonly property var mac: win.info ? win.info.mac : null
                                readonly property int leaks: mac && mac.activeLeaks ? mac.activeLeaks.length : 0
                                readonly property int hidden: mac && mac.devices
                                    ? mac.devices.filter(d => d.randomized).length : 0
                                visible: mac === null || mac.available
                                icon: !mac || !mac.available ? "shield"
                                    : leaks > 0 ? "shield-alert" : "shield-check"
                                tone: !mac || !mac.available ? Theme.dim
                                    : leaks > 0 ? Theme.warn : Theme.accent
                                title: "MAC address"
                                value: !mac ? "" : !mac.available ? "Unknown"
                                     : leaks > 0 ? "Permanent" : hidden > 0 ? "Randomized" : "Idle"
                                detail: {
                                    const m = win.info ? win.info.mac : null
                                    if (!m) return ""
                                    if (!m.available) return m.note || ""
                                    const on = m.devices.filter(d => d.randomized).map(d => d.name)
                                    if (m.activeLeaks.length > 0)
                                        return `${m.activeLeaks.join(", ")} is on the network using the card's permanent `
                                            + "address, which identifies this machine to every network it joins."
                                    if (on.length > 0)
                                        return `${on.join(", ")} presents a per-network address instead of the card's `
                                            + "permanent one, so the same machine isn't recognisable across networks."
                                    return "Nothing is connected, so no address is being broadcast. Each card will take "
                                         + "a per-network address when it joins one."
                                }
                            }

                            StatusRow {
                                // Running state is cheap; zone and ports come from the privileged pass
                                readonly property var fwl: {
                                    const base = win.info ? win.info.firewall : null
                                    if (!base) return null
                                    const d = win.deepInfo ? win.deepInfo.firewallDetail : null
                                    return (d && !d.note) ? Object.assign({}, base, d, { deep: true }) : base
                                }
                                readonly property bool good: fwl && fwl.available && fwl.running
                                                             && (!fwl.deep || !fwl.permissive)
                                icon: !fwl ? "shield" : good ? "shield-check" : "shield-alert"
                                tone: !fwl ? Theme.dim
                                    : good ? Theme.accent
                                    : fwl.running ? Theme.warn : Theme.error
                                title: "Firewall"
                                value: !fwl ? "" : !fwl.available ? "Not installed"
                                     : !fwl.running ? "Off"
                                     : fwl.deep ? (fwl.zone || "On") : "On"
                                detail: {
                                    const f = fwl        // the merged object, not win.info.firewall
                                    if (!f) return ""
                                    if (!f.available || !f.running) return f.note || ""
                                    if (!f.deep) {
                                        const d = win.deepInfo ? win.deepInfo.firewallDetail : null
                                        if (d && d.note) return "Running. " + d.note
                                        return "Running. Which zone it uses and which ports are open is read from "
                                             + "firewalld's own configuration, which only root can see. "
                                             + "Use \"Run the deeper checks\" above."
                                    }
                                    const open = f.openPorts && f.openPorts.length > 0
                                        ? ` Open: ${f.openPorts.join(", ")}.` : ""
                                    return (f.permissive
                                        ? "The FedoraWorkstation zone leaves ports 1025-65535 open on TCP and UDP. "
                                          + "Hypora uses the public zone instead."
                                        : "Incoming connections are refused except where a service was allowed.") + open
                                }
                            }

                            StatusRow {
                                readonly property var up: win.info ? win.info.updates : null
                                readonly property bool good: up && up.packagesEnabled && up.packagesApply
                                icon: !up ? "shield" : good ? "shield-check" : "shield-alert"
                                tone: !up ? Theme.dim : good ? Theme.accent : Theme.warn
                                title: "System packages"
                                value: !up ? "" : !up.packagesEnabled ? "Manual"
                                     : !up.packagesApply ? "Download only"
                                     : up.upgradeType === "security" ? "Security only" : "All updates"
                                detail: {
                                    const u = win.info ? win.info.updates : null
                                    if (!u) return ""
                                    if (u.packagesNote) return u.packagesNote
                                         + " Run sudo dnf upgrade yourself, or see the readme."
                                    const when = u.packagesLastRun ? ` Last run: ${u.packagesLastRun}.` : ""
                                    return (u.upgradeType === "security"
                                        ? "Fedora security advisories install on their own, daily. Updates tagged as "
                                          + "bugfixes, and anything from a COPR, still wait for you to run dnf."
                                        : "Every available update installs on its own, daily, including third-party "
                                          + "repositories.") + when
                                }
                            }

                            StatusRow {
                                readonly property var up: win.info ? win.info.updates : null
                                icon: !up ? "shield" : up.flatpakEnabled ? "shield-check" : "shield-alert"
                                tone: !up ? Theme.dim : up.flatpakEnabled ? Theme.accent : Theme.warn
                                title: "Flatpak apps"
                                value: !up ? "" : up.flatpakEnabled ? "Daily" : "Manual"
                                detail: !up ? ""
                                      : up.flatpakEnabled
                                        ? "Firefox and the other sandboxed apps update on their own, daily. dnf never "
                                          + "sees these, which is why they have a timer of their own."
                                        : "Nothing updates the flatpaks, including the browser. Run flatpak update, or "
                                          + "enable hypora-flatpak-update.timer."
                            }

                            StatusRow {
                                readonly property var se: win.info ? win.info.selinux : null
                                icon: !se || !se.available ? "shield"
                                    : se.mode === "enforcing" ? "shield-check" : "shield-alert"
                                tone: !se || !se.available ? Theme.dim
                                    : se.mode === "enforcing" ? Theme.accent
                                    : se.mode === "permissive" ? Theme.warn : Theme.error
                                // "Mode" alone meant nothing once the SELinux heading above it was removed
                                title: "SELinux"
                                value: !se ? "" : !se.available ? "Not installed"
                                     : se.mode.charAt(0).toUpperCase() + se.mode.slice(1)
                                detail: {
                                    const se = win.info ? win.info.selinux : null
                                    if (!se) return ""
                                    if (!se.available) return se.note
                                    if (se.boot && se.boot !== se.mode)
                                        return `Set to ${se.boot} for the next boot (policy: ${se.policy || "unknown"}).`
                                    return se.mode === "enforcing"
                                        ? "Policy is applied and violations are blocked."
                                        : se.mode === "permissive"
                                          ? "Violations are logged but allowed through."
                                          : "SELinux is off; nothing is confined."
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 12
                                Layout.topMargin: 2
                                Layout.bottomMargin: 6
                                spacing: 8
                                visible: win.info !== null && win.info.selinux.available

                                Repeater {
                                    model: ["Enforcing", "Permissive"]
                                    Pill {
                                        required property string modelData
                                        readonly property string want: modelData.toLowerCase()
                                        text: modelData
                                        // Changing the running mode only works if SELinux is already on
                                        enabled: win.info && win.info.selinux.mode !== "disabled"
                                        current: win.shown("selinux",
                                                    win.info ? win.info.selinux.mode : "") === want
                                        onClicked: win.admin(["selinux", want], `Switching to ${want}…`,
                                                             "selinux", want)
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    visible: win.info && win.info.selinux.needsRelabel
                                    text: "Turning SELinux on needs a reboot"
                                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
                                    color: Theme.dim
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 12
                                Layout.bottomMargin: 8
                                spacing: 8
                                visible: win.info !== null && win.info.selinux.available

                                Text {
                                    text: "At boot:"
                                    font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                                    color: Theme.dim
                                }
                                Repeater {
                                    model: ["Enforcing", "Permissive"]
                                    Pill {
                                        required property string modelData
                                        readonly property string want: modelData.toLowerCase()
                                        text: modelData
                                        small: true
                                        current: win.shown("selinuxBoot",
                                                    win.info ? win.info.selinux.boot : "") === want
                                        onClicked: win.admin(["selinux-boot", want],
                                            "Will relabel on the next boot…",
                                            "selinuxBoot", want)
                                    }
                                }
                            }

                            // Privacy: sensors that can observe you and what you opened, grouped by subject.
                            Heading { text: "Privacy" }

                            ToggleRow {
                                readonly property var loc: win.info ? win.info.location : null
                                icon: "map-pin"
                                title: "Location Services"
                                available: loc !== null && loc.available
                                checked: win.shown("location",
                                                   loc !== null && loc.available && loc.enabled)
                                detail: !loc ? ""
                                      : !loc.available ? loc.note
                                      : loc.enabled
                                        ? "GeoClue may give your approximate location to apps that ask."
                                        : "GeoClue is masked, so nothing can start it."
                                onToggled: win.admin(["location", checked ? "off" : "on"],
                                                     checked ? "Masking GeoClue…" : "Unmasking GeoClue…",
                                                     "location", !checked)
                            }

                            ToggleRow {
                                readonly property var cam: win.info ? win.info.camera : null
                                icon: "camera"
                                title: "Camera"
                                // `present` and `controllable` differ: a non-USB camera cannot be unloaded, and a switched-off camera is still present.
                                available: cam !== null && cam.present && cam.controllable
                                checked: win.shown("camera", cam !== null && cam.enabled)
                                detail: !cam ? ""
                                      : !cam.present ? "No camera found on this machine."
                                      : !cam.controllable ? (cam.note || "")
                                      : cam.enabled
                                        ? `Available to apps (${cam.devices.join(", ")}). Turning this off unloads the ${cam.driver || "camera"} driver.`
                                        : (cam.uvc && cam.uvc.length > 0
                                           ? `${cam.uvc.join(", ")} is connected, but the uvcvideo driver is not loaded, so no app can open it.`
                                           : "The camera driver is unloaded, so no app can open it.")
                                onToggled: win.admin(["camera", checked ? "off" : "on"],
                                                     checked ? "Unloading the camera driver…" : "Loading the camera driver…",
                                                     "camera", !checked)
                            }

                            // Instant: this sets a PipeWire property directly, so nothing needs to be optimistic.
                            ToggleRow {
                                icon: win.micAudio && win.micAudio.muted ? "mic-off" : "mic"
                                title: "Microphone"
                                available: win.micAudio !== null
                                checked: win.micAudio !== null && !win.micAudio.muted
                                detail: !win.micAudio ? "No input device."
                                      : win.micAudio.muted
                                        ? "Muted in PipeWire, so apps record silence."
                                        : "Apps that ask PipeWire for input can hear you."
                                onToggled: if (win.micAudio) win.micAudio.muted = !win.micAudio.muted
                            }

                            ToggleRow {
                                readonly property var fh: win.info ? win.info.fileHistory : null
                                icon: "history"
                                title: "File History"
                                available: fh !== null && fh.available
                                checked: win.shown("fileHistory", fh !== null && fh.remember === true)
                                detail: !fh ? ""
                                      : !fh.available ? fh.note
                                      : `${fh.entries} recently-opened file${fh.entries === 1 ? "" : "s"} remembered. `
                                        + "Applies to GTK apps, which is where this list is kept."
                                onToggled: win.gsettingsSet("remember-recent-files",
                                                            checked ? "false" : "true",
                                                            "fileHistory", !checked)
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 12
                                Layout.bottomMargin: 14
                                visible: win.info !== null && win.info.fileHistory.available
                                Pill {
                                    text: "Clear file history"
                                    small: true
                                    onClicked: {
                                        win.notice = "File history cleared."
                                        win.userRun(["sh", "-c",
                                            'rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/recently-used.xbel"'])
                                    }
                                }
                                Item { Layout.fillWidth: true }
                            }
                        }
                    }
                }
            }

            // ---------- pieces ----------
            component Heading: Text {
                Layout.topMargin: 14
                Layout.leftMargin: 4
                Layout.bottomMargin: 2
                font.family: Theme.font; font.pixelSize: Theme.fontSize - 3; font.bold: true
                font.capitalization: Font.AllUppercase; font.letterSpacing: 1
                color: Theme.dim
            }

            component StatusRow: Rectangle {
                id: sr
                property string icon
                property string title
                property string value
                property string detail
                property color tone: Theme.fg

                Layout.fillWidth: true
                implicitHeight: srCol.implicitHeight + 22
                radius: 10
                color: Theme.surface

                Icon {
                    id: srIcon
                    anchors { left: parent.left; leftMargin: 14; top: parent.top; topMargin: 14 }
                    name: sr.icon
                    size: 18
                    color: sr.tone
                }
                ColumnLayout {
                    id: srCol
                    anchors { left: srIcon.right; right: parent.right; top: parent.top; leftMargin: 14; rightMargin: 14; topMargin: 11 }
                    spacing: 2
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: sr.title
                            font.family: Theme.font; font.pixelSize: Theme.fontSize; font.bold: true
                            color: Theme.fg
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: sr.value
                            font.family: Theme.font; font.pixelSize: Theme.fontSize - 1; font.bold: true
                            color: sr.tone
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: sr.detail
                        wrapMode: Text.Wrap
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
                        color: Theme.dim
                    }
                }
            }

            component ToggleRow: Rectangle {
                id: tr
                property string icon
                property string title
                property string detail
                property bool checked: false
                property bool available: true
                signal toggled()

                Layout.fillWidth: true
                implicitHeight: trCol.implicitHeight + 22
                radius: 10
                color: Theme.surface
                opacity: available ? 1 : 0.55

                Icon {
                    id: trIcon
                    anchors { left: parent.left; leftMargin: 14; top: parent.top; topMargin: 14 }
                    name: tr.icon
                    size: 18
                    color: tr.available && tr.checked ? Theme.accent : Theme.dim
                }
                ColumnLayout {
                    id: trCol
                    anchors { left: trIcon.right; right: trSwitch.left; top: parent.top; leftMargin: 14; rightMargin: 12; topMargin: 11 }
                    spacing: 2
                    Text {
                        text: tr.title
                        font.family: Theme.font; font.pixelSize: Theme.fontSize; font.bold: true
                        color: Theme.fg
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: tr.detail
                        wrapMode: Text.Wrap
                        font.family: Theme.font; font.pixelSize: Theme.fontSize - 3
                        color: Theme.dim
                    }
                }
                Rectangle {
                    id: trSwitch
                    anchors { right: parent.right; rightMargin: 14; top: parent.top; topMargin: 14 }
                    width: 44; height: 24; radius: 12
                    color: tr.available && tr.checked ? Theme.accent : Theme.bg
                    Rectangle {
                        width: 18; height: 18; radius: 9
                        anchors.verticalCenter: parent.verticalCenter
                        x: tr.checked ? parent.width - width - 3 : 3
                        color: tr.checked ? Theme.bg : Theme.dim
                        Behavior on x { NumberAnimation { duration: 120 } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: tr.available
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tr.toggled()
                    }
                }
            }

            component Pill: Rectangle {
                id: pill
                property string text
                property bool current: false
                property bool small: false
                signal clicked()

                implicitWidth: pillText.implicitWidth + (small ? 20 : 28)
                implicitHeight: small ? 26 : 32
                radius: height / 2
                opacity: enabled ? 1 : 0.45
                color: current ? Theme.accent : (pillArea.containsMouse && pill.enabled ? Qt.lighter(Theme.surface, 1.3) : Theme.surface)
                Text {
                    id: pillText
                    anchors.centerIn: parent
                    text: pill.text
                    font.family: Theme.font; font.pixelSize: Theme.fontSize - (pill.small ? 3 : 2); font.bold: pill.current
                    color: pill.current ? Theme.bg : Theme.fg
                }
                MouseArea {
                    id: pillArea
                    anchors.fill: parent
                    enabled: pill.enabled
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pill.clicked()
                }
            }
        }
    }
}
