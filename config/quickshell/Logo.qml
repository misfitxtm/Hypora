import QtQuick

// The Hypora mark: a hexagon around an "H" whose crossbar is an aurora wave,
// stroked with a gradient from the theme accent to a hue-shifted partner color.
// The SDDM theme (system/sddm/hypora/Main.qml) draws the same SVG; keep them in sync.
Image {
    id: root
    property real size: 18
    property color from: Theme.accent
    property color to: Qt.hsla((from.hslHue + 0.15) % 1, from.hslSaturation, from.hslLightness, 1)

    width: size
    height: size
    sourceSize: Qt.size(size, size)
    smooth: true

    function hex(c) {
        const h = v => Math.round(v * 255).toString(16).padStart(2, "0")
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }

    source: {
        const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="url(#g)" '
                  + 'stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">'
                  + '<defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="3" y1="2" x2="21" y2="22">'
                  + `<stop offset="0" stop-color="${hex(from)}"/><stop offset="1" stop-color="${hex(to)}"/>`
                  + '</linearGradient></defs>'
                  + '<polygon points="12 1.8 20.8 6.9 20.8 17.1 12 22.2 3.2 17.1 3.2 6.9"/>'
                  + '<line x1="8.4" y1="7.6" x2="8.4" y2="16.4"/><line x1="15.6" y1="7.6" x2="15.6" y2="16.4"/>'
                  + '<path d="M8.4 12c1.2-1.7 2.4-1.7 3.6 0s2.4 1.7 3.6 0"/>'
                  + '</svg>'
        return "data:image/svg+xml;utf8," + encodeURIComponent(svg)
    }
}
