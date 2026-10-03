#!/usr/bin/env bash
# Installs the Quickshell greetd greeter (login screen). Run from the repo root.
# Sources:  system/greetd/*  +  config/quickshell/PowerButton.qml  +  the current theme.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO/system/greetd"
THEME_FILE="$HOME/.config/hypora/themes/current/Theme.qml"
[ -f "$THEME_FILE" ] || THEME_FILE="$REPO/themes/Nord/Theme.qml"

for f in "$SRC/config.toml" "$SRC/hyprland.lua" \
         "$SRC/quickshell/shell.qml" "$SRC/quickshell/qmldir" \
         "$REPO/config/quickshell/PowerButton.qml" "$THEME_FILE"; do
    [ -f "$f" ] || { echo "Missing required file: $f" >&2; exit 1; }
done

sudo dnf install -y greetd hyprland quickshell uwsm

getent passwd greetd >/dev/null || {
    echo "No 'greetd' user found; edit system/greetd/config.toml 'user =' to match" >&2
    exit 1
}

sudo install -d /etc/greetd/quickshell
sudo install -m644 "$SRC/quickshell/shell.qml" "$SRC/quickshell/qmldir" /etc/greetd/quickshell/
sudo install -m644 "$REPO/config/quickshell/PowerButton.qml" /etc/greetd/quickshell/
sudo install -m644 "$THEME_FILE" /etc/greetd/quickshell/Theme.qml   # copy of the active theme

sudo install -m644 "$SRC/hyprland.lua" /etc/greetd/hyprland.lua
[ -f /etc/greetd/config.toml ] && sudo cp -n /etc/greetd/config.toml /etc/greetd/config.toml.bak
sudo install -m644 "$SRC/config.toml" /etc/greetd/config.toml

for dm in sddm gdm lightdm; do sudo systemctl disable "$dm" 2>/dev/null || true; done
sudo systemctl enable --force greetd
sudo systemctl set-default graphical.target

echo "Done. Test with: sudo systemctl stop <old-dm>; sudo systemctl start greetd"
echo "If it fails: Ctrl+Alt+F2, then 'journalctl -u greetd -b'. Old config: /etc/greetd/config.toml.bak"
