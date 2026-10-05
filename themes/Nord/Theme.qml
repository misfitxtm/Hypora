pragma Singleton
import Quickshell
import QtQuick

// Central palette. Later, your theme-set script can rewrite this file
// and Quickshell live-reloads on change.
Singleton {
    readonly property color bg: "#2e3440"
    readonly property color surface: "#3b4252"
    readonly property color fg: "#eceff4"
    readonly property color dim: "#7b88a1"
    readonly property color accent: "#88c0d0"
    readonly property color error: "#bf616a"
    readonly property string font: "JetBrains Mono"
    readonly property int fontSize: 13

    // Apps launched from widget clicks. The last three are commands run in the terminal
    // (the same TUIs Omarchy uses); impala falls back to nmtui when iwd isn't running.
    readonly property string terminal: "kitty"
    readonly property string mixer: "wiremix"
    readonly property string network: "impala || nmtui"
    readonly property string bluetooth: "bluetui"
}
