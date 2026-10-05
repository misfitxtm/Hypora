import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts

// Security and privacy: what the machine's security state actually is, and the switches
// that genuinely change it. Every switch says what it covers — and what it doesn't.
//
// Readings and privileged changes go through /usr/local/bin/hypora-security. That path is
// root-owned on purpose: pkexec runs it as root, and a helper sitting somewhere the user
// can write would turn any write access to $HOME into root. Run `hypora-security status`
// yourself to see exactly what this window is reading.
// Open from the menu (Security) or:  qs ipc call security open
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
            title: "Security"
            implicitWidth: 620
            implicitHeight: 760
            color: Theme.bg
            onClosed: ShellState.securitySettingsOpen = false

            property var info: null
            property bool loading: true
            property string notice: ""

            readonly property var source: Pipewire.defaultAudioSource
            readonly property var micAudio: source ? source.audio : null
            PwObjectTracker { objects: win.source ? [win.source] : [] }

            function refresh() { if (!probe.running) { loading = info === null; probe.running = true } }

            // Privileged changes go through pkexec, which raises Hypora's polkit prompt.
            // argv, not a shell string: nothing here is word-split or glob-expanded, and
            // the helper validates each value against a fixed list anyway.
            readonly property string helper: "/usr/local/bin/hypora-security"

            function admin(args, what) {
                notice = what
                Quickshell.execDetached(["pkexec", helper].concat(args))
                recheck.restart()
            }

            function gsettingsSet(key, value) {
                Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.privacy", key, value])
                recheck.restart()
            }

            Process {
                id: probe
                command: [win.helper, "status"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try { win.info = JSON.parse(text) } catch (e) { win.info = null }
                        win.loading = false
                    }
                }
                onExited: code => { if (code !== 0 && win.info === null) win.loading = false }
            }
            Timer { id: recheck; interval: 1500; onTriggered: win.refresh() }
            Timer { running: true; repeat: true; interval: 15000; onTriggered: win.refresh() }
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
                            text: "Security"
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
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: win.info !== null
                        clip: true
                        contentHeight: body.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: body
                            width: parent.width
                            spacing: 4

                            // ---------- Device security ----------
                            Heading { text: "Device Security" }

                            StatusRow {
                                readonly property var sb: win.info ? win.info.secureBoot : null
                                icon: !sb ? "shield" : sb.enabled ? "shield-check" : "shield-alert"
                                tone: !sb ? Theme.dim : sb.enabled ? Theme.accent : Theme.error
                                title: "Secure Boot"
                                value: !sb ? ""
                                     : !sb.supported ? "Not available"
                                     : sb.enabled ? "On" : "Off"
                                detail: !sb ? ""
                                      : sb.note ? sb.note
                                      : sb.enabled
                                        ? "The firmware checks that the bootloader and kernel are signed before running them."
                                        : "The firmware will run any bootloader. Turn Secure Boot on in your UEFI setup screen."
                            }

                            StatusRow {
                                readonly property var enc: win.info ? win.info.encryption : null
                                readonly property int exposed: enc && enc.unencryptedSwap ? enc.unencryptedSwap.length : 0
                                icon: !enc || !enc.available ? "shield"
                                    : enc.rootEncrypted && exposed === 0 ? "shield-check" : "shield-alert"
                                tone: !enc || !enc.available ? Theme.dim
                                    : !enc.rootEncrypted ? Theme.error
                                    : exposed > 0 ? Theme.warn : Theme.accent
                                title: "Disk encryption"
                                value: !enc ? "" : !enc.available ? "Unknown"
                                     : enc.rootEncrypted ? "On" : "Off"
                                detail: {
                                    const e = win.info ? win.info.encryption : null
                                    if (!e) return ""
                                    if (!e.available) return e.note || ""
                                    const swap = e.unencryptedSwap.length > 0
                                        ? ` Swap on ${e.unencryptedSwap.join(", ")} is not encrypted, so memory can reach the disk in the clear.`
                                        : ""
                                    return (e.rootEncrypted
                                        ? `This system is on an encrypted volume (${e.rootDevice}).`
                                        : "This system is not encrypted, so anyone holding the drive can read it. "
                                          + "Encryption can only be turned on when Fedora is installed.") + swap
                                }
                            }

                            StatusRow {
                                readonly property var fw: win.info ? win.info.firmware : null
                                visible: fw !== null
                                icon: !fw || !fw.available ? "shield"
                                    : fw.failed.length === 0 ? "shield-check" : "shield-alert"
                                tone: !fw || !fw.available ? Theme.dim
                                    : fw.failed.length === 0 ? Theme.accent : Theme.warn
                                title: "Firmware checks"
                                value: !fw ? "" : !fw.available ? "Unavailable"
                                     : `${fw.passed} of ${fw.total} passed` + (fw.hsi ? `  ·  ${fw.hsi}` : "")
                                detail: !fw ? "" : !fw.available ? fw.note
                                      : fw.failed.length === 0
                                        ? "Every check fwupd knows about passed."
                                        : "Not passing: " + fw.failed.map(f => `${f.name} (${f.result})`).join(", ")
                            }

                            // ---------- Network ----------
                            Heading { text: "Network" }

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
                                readonly property var fwl: win.info ? win.info.firewall : null
                                readonly property bool good: fwl && fwl.available && fwl.running && !fwl.permissive
                                icon: !fwl ? "shield" : good ? "shield-check" : "shield-alert"
                                tone: !fwl ? Theme.dim
                                    : good ? Theme.accent
                                    : fwl.running ? Theme.warn : Theme.error
                                title: "Firewall"
                                value: !fwl ? "" : !fwl.available ? "Not installed"
                                     : !fwl.running ? "Off" : fwl.zone || "On"
                                detail: {
                                    const f = win.info ? win.info.firewall : null
                                    if (!f) return ""
                                    if (!f.available || !f.running) return f.note || ""
                                    const open = f.openPorts && f.openPorts.length > 0
                                        ? ` Open: ${f.openPorts.join(", ")}.` : ""
                                    return (f.permissive
                                        ? "The FedoraWorkstation zone leaves ports 1025-65535 open on TCP and UDP. "
                                          + "Hypora uses the public zone instead."
                                        : "Incoming connections are refused except where a service was allowed.") + open
                                }
                            }

                            // ---------- Updates ----------
                            Heading { text: "Updates" }

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

                            // ---------- SELinux ----------
                            Heading { text: "SELinux" }

                            StatusRow {
                                readonly property var se: win.info ? win.info.selinux : null
                                icon: !se || !se.available ? "shield"
                                    : se.mode === "enforcing" ? "shield-check" : "shield-alert"
                                tone: !se || !se.available ? Theme.dim
                                    : se.mode === "enforcing" ? Theme.accent
                                    : se.mode === "permissive" ? Theme.warn : Theme.error
                                title: "Mode"
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
                                        current: win.info && win.info.selinux.mode === want
                                        onClicked: win.admin(["selinux", want], `Switching to ${want}…`)
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
                                    model: ["Enforcing", "Permissive", "Disabled"]
                                    Pill {
                                        required property string modelData
                                        readonly property string want: modelData.toLowerCase()
                                        text: modelData
                                        small: true
                                        current: win.info && win.info.selinux.boot === want
                                        onClicked: win.admin(["selinux-boot", want],
                                            want === "disabled" ? "Will be off after a reboot…"
                                                                : "Will relabel on the next boot…")
                                    }
                                }
                            }

                            // ---------- Hardware ----------
                            Heading { text: "Hardware" }

                            ToggleRow {
                                readonly property var cam: win.info ? win.info.camera : null
                                icon: "camera"
                                title: "Camera"
                                available: cam !== null && cam.present
                                checked: cam !== null && cam.enabled
                                detail: !cam ? ""
                                      : !cam.present ? "No camera found on this machine."
                                      : cam.enabled
                                        ? `Available to apps (${cam.devices.join(", ")}). Turning this off unloads the ${cam.driver || "camera"} driver.`
                                        : "The camera driver is unloaded, so no app can open it."
                                onToggled: win.admin(["camera", checked ? "off" : "on"],
                                                     checked ? "Unloading the camera driver…" : "Loading the camera driver…")
                            }

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

                            // ---------- Privacy ----------
                            Heading { text: "Privacy" }

                            ToggleRow {
                                readonly property var loc: win.info ? win.info.location : null
                                icon: "map-pin"
                                title: "Location Services"
                                available: loc !== null && loc.available
                                checked: loc !== null && loc.available && loc.enabled
                                detail: !loc ? ""
                                      : !loc.available ? loc.note
                                      : loc.enabled
                                        ? "GeoClue may give your approximate location to apps that ask."
                                        : "GeoClue is masked, so nothing can start it."
                                onToggled: win.admin(["location", checked ? "off" : "on"],
                                                     checked ? "Masking GeoClue…" : "Unmasking GeoClue…")
                            }

                            ToggleRow {
                                readonly property var fh: win.info ? win.info.fileHistory : null
                                icon: "history"
                                title: "File History"
                                available: fh !== null && fh.available
                                checked: fh !== null && fh.remember === true
                                detail: !fh ? ""
                                      : !fh.available ? fh.note
                                      : `${fh.entries} recently-opened file${fh.entries === 1 ? "" : "s"} remembered. `
                                        + "Applies to GTK apps, which is where this list is kept."
                                onToggled: win.gsettingsSet("remember-recent-files", checked ? "false" : "true")
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
                                        Quickshell.execDetached(["sh", "-c",
                                            'rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/recently-used.xbel"'])
                                        win.notice = "File history cleared."
                                        recheck.restart()
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
