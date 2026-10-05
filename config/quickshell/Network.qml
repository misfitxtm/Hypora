import QtQuick

// Bar indicator: wifi (with signal strength), ethernet, or offline.
Icon {
    name: Net.icon
    level: Net.strength
    size: 15
    color: Net.type === "" ? Theme.dim : Theme.fg
}
