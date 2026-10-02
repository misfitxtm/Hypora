#!/usr/bin/env bash
# Installs the Quickshell greetd greeter. Run from this directory.
set -euo pipefail
cd "$(dirname "$0")"

sudo dnf install -y greetd hyprland quickshell

getent passwd greetd >/dev/null || { echo "No 'greetd' user found; edit config.toml 'user =' to match"; exit 1; }

sudo install -d /etc/greetd/quickshell
sudo install -m644 shell.qml qmldir PowerButton.qml /etc/greetd/quickshell/

# Use your live theme if present, otherwise the bundled one
if [ -f "$HOME/.config/quickshell/Theme.qml" ]; then
    sudo install -m644 "$HOME/.config/quickshell/Theme.qml" /etc/greetd/quickshell/Theme.qml
else
    sudo install -m644 Theme.qml /etc/greetd/quickshell/Theme.qml
fi

sudo install -m644 hyprland.conf /etc/greetd/hyprland.conf
[ -f /etc/greetd/config.toml ] && sudo cp -n /etc/greetd/config.toml /etc/greetd/config.toml.bak
sudo install -m644 config.toml /etc/greetd/config.toml

for dm in sddm gdm lightdm; do sudo systemctl disable "$dm" 2>/dev/null || true; done
sudo systemctl enable --force greetd
sudo systemctl set-default graphical.target

echo "Done. Test with: sudo systemctl stop <old-dm>; sudo systemctl start greetd"
