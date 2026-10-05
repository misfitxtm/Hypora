pragma Singleton
import Quickshell
import QtQuick

// Central palette. Later, your theme-set script can rewrite this file
// and Quickshell live-reloads on change.
Singleton {
    readonly property color bg: "#1a1b26"
    readonly property color surface: "#24283b"
    readonly property color fg: "#c0caf5"
    readonly property color dim: "#565f89"
    readonly property color accent: "#7aa2f7"
    readonly property color error: "#f7768e"
    readonly property string font: "JetBrains Mono"
    readonly property int fontSize: 13

    // Apps launched from widget clicks. The last three are commands run in the terminal
    // (the same TUIs Omarchy uses); impala falls back to nmtui when iwd isn't running.
    readonly property string terminal: "kitty"
    readonly property string mixer: "wiremix"
    readonly property string network: "impala || nmtui"
    readonly property string bluetooth: "bluetui"
}
