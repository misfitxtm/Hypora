import QtQuick

// Line icon drawn from inline SVG and colored from the theme. No icon font needed.
// Shapes are from Feather (MIT, feathericons.com) unless noted.
// `level` (0..1) drives the wifi, volume and battery variants.
Image {
    id: root
    property string name
    property color color: Theme.fg
    property real size: 16
    property real level: 1
    property bool charging: false

    width: size
    height: size
    sourceSize: Qt.size(size, size)
    smooth: true

    function hex(c) {
        const h = v => Math.round(v * 255).toString(16).padStart(2, "0")
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }

    function body(name, level, charging, c) {
        const speaker = '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/>'
        const dim = on => on ? '' : ' opacity="0.3"'
        switch (name) {
        case "wifi":
            return `<path d="M1.42 9a16 16 0 0 1 21.16 0"${dim(level > 0.75)}/>`
                 + `<path d="M5 12.55a11 11 0 0 1 14.08 0"${dim(level > 0.5)}/>`
                 + `<path d="M8.53 16.11a6 6 0 0 1 6.95 0"${dim(level > 0.25)}/>`
                 + '<line x1="12" y1="20" x2="12.01" y2="20"/>'
        case "wifi-off":
            return '<line x1="1" y1="1" x2="23" y2="23"/><path d="M16.72 11.06A10.94 10.94 0 0 1 19 12.55"/>'
                 + '<path d="M5 12.55a10.94 10.94 0 0 1 5.17-2.39"/><path d="M10.71 5.05A16 16 0 0 1 22.58 9"/>'
                 + '<path d="M1.42 9a15.91 15.91 0 0 1 4.7-2.88"/><path d="M8.53 16.11a6 6 0 0 1 6.95 0"/>'
                 + '<line x1="12" y1="20" x2="12.01" y2="20"/>'
        case "ethernet":   // after Lucide "ethernet-port" (ISC)
            return '<path d="M15 20l3-3h2a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h2l3 3z"/>'
                 + '<path d="M6 8v1M10 8v1M14 8v1M18 8v1"/>'
        case "volume":
            if (level <= 0) return speaker + '<line x1="23" y1="9" x2="17" y2="15"/><line x1="17" y1="9" x2="23" y2="15"/>'
            return speaker + '<path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>'
                 + `<path d="M19.07 4.93a10 10 0 0 1 0 14.14"${dim(level > 0.5)}/>`
        case "battery":
            return '<rect x="1" y="6" width="18" height="12" rx="2" ry="2"/><line x1="23" y1="13" x2="23" y2="11"/>'
                 + (charging ? '<polyline points="11 8.5 8 12 12 12 9 15.5" stroke-width="1.6"/>'
                             : `<rect x="3.5" y="8.5" width="${Math.max(0.5, 13 * level)}" height="7" rx="0.5" fill="${c}" stroke="none"/>`)
        case "bluetooth":
            return '<polyline points="6.5 6.5 17.5 17.5 12 23 12 1 17.5 6.5 6.5 17.5"/>'
        case "bell":
            return '<path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/>'
        case "bell-off":
            return '<path d="M13.73 21a2 2 0 0 1-3.46 0"/><path d="M18.63 13A17.89 17.89 0 0 1 18 8"/>'
                 + '<path d="M6.26 6.26A5.86 5.86 0 0 0 6 8c0 7-3 9-3 9h14"/><path d="M18 8a6 6 0 0 0-9.33-5"/>'
                 + '<line x1="1" y1="1" x2="23" y2="23"/>'
        case "sun":
            return '<circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/>'
                 + '<line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/>'
                 + '<line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/>'
                 + '<line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/>'
        case "moon":
            return '<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>'
        case "lock":
            return '<rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>'
        case "logout":
            return '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/>'
                 + '<line x1="21" y1="12" x2="9" y2="12"/>'
        case "reboot":
            return '<polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/>'
        case "power":
            return '<path d="M18.36 6.64a9 9 0 1 1-12.73 0"/><line x1="12" y1="2" x2="12" y2="12"/>'
        case "chevron":
            return '<polyline points="9 18 15 12 9 6"/>'
        default:
            return '<circle cx="12" cy="12" r="9"/>'
        }
    }

    source: {
        const c = hex(color)
        const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
                  + `stroke="${c}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">`
                  + body(name, level, charging, c) + '</svg>'
        return "data:image/svg+xml;utf8," + encodeURIComponent(svg)
    }
}
