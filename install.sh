#!/usr/bin/env bash
# Minimal installer for testing on a fresh Fedora install.
# Covers: packages, Hyprland (Lua) config, Quickshell config, theme.
# NOT included: greeter (run ./install-greeter.sh separately), packages/ lists.
#
# Safe to re-run. Config files are SYMLINKED into the repo, so keep the repo where it is.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME="${THEME:-Nord}"
CONF="$HOME/.config"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- sanity checks ----------
[ "$(id -u)" -ne 0 ] || die "Run as your normal user, not root (sudo is used where needed)."
. /etc/os-release
[ "${ID:-}" = "fedora" ] || die "This script targets Fedora (found: ${ID:-unknown})."
[ -f "$REPO/themes/$THEME/Theme.qml" ] || die "Theme '$THEME' not found in $REPO/themes/"
[ -d "$REPO/config/quickshell" ] || die "Missing $REPO/config/quickshell"

# ---------- helpers ----------
# link <src> <dest>: symlink, backing up anything already at dest
link() {
    local src=$1 dest=$2
    mkdir -p "$(dirname "$dest")"
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then return 0; fi
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        mv "$dest" "$dest.bak.$(date +%s)"
        warn "Backed up existing $dest"
    fi
    ln -s "$src" "$dest"
}

# available_in_repos <pkg>: true if dnf can find it
available() { [ -n "$(dnf repoquery --quiet "$1" 2>/dev/null)" ]; }

# ---------- repos ----------
log "Preparing repositories"
sudo dnf install -y dnf-plugins-core

if ! available hyprland; then
    log "hyprland not in enabled repos; enabling COPR solopasha/hyprland"
    sudo dnf copr enable -y solopasha/hyprland
fi
if ! available quickshell; then
    # Verify this COPR is current before relying on it; Terra or a source build also work.
    log "quickshell not in enabled repos; enabling COPR errornosugar/quickshell"
    sudo dnf copr enable -y errornosugar/quickshell
fi

# ---------- packages ----------
REQUIRED=(
    hyprland uwsm quickshell kitty git
    NetworkManager NetworkManager-tui
    pipewire wireplumber upower
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    polkit jetbrains-mono-fonts
)
# Nice to have; a missing one only produces a warning
OPTIONAL=(
    hyprlock hypridle pavucontrol brightnessctl
    wl-clipboard grim slurp google-noto-emoji-fonts
)

log "Installing required packages"
sudo dnf install -y "${REQUIRED[@]}"

log "Installing optional packages"
for p in "${OPTIONAL[@]}"; do
    sudo dnf install -y "$p" || warn "Skipped optional package: $p"
done

# ---------- services ----------
log "Enabling services"
sudo systemctl enable --now NetworkManager || warn "Could not enable NetworkManager"
sudo systemctl enable --now upower || warn "Could not enable upower (battery widget may show nothing)"
sudo systemctl set-default graphical.target
fc-cache -f >/dev/null 2>&1 || true

# ---------- theme ----------
log "Setting theme: $THEME"
mkdir -p "$CONF/hypora/themes"
ln -sfn "$REPO/themes/$THEME" "$CONF/hypora/themes/current"

# ---------- Hyprland ----------
# Hyprland 0.55+ uses a Lua config (hyprland.lua); the old hyprland.conf format is deprecated.
log "Linking Hyprland config"
if [ -f "$REPO/config/hypr/hyprland.lua" ]; then
    link "$REPO/config/hypr/hyprland.lua" "$CONF/hypr/hyprland.lua"
    grep -Eq 'exec_cmd\(.*\b(qs|quickshell)\b' "$REPO/config/hypr/hyprland.lua" \
        || warn "hyprland.lua has no hl.exec_cmd line for Quickshell (e.g. hl.exec_cmd(\"uwsm app -- qs\"))"
    [ -e "$CONF/hypr/hyprland.conf" ] \
        && warn "A legacy ~/.config/hypr/hyprland.conf exists; move it away if Hyprland misbehaves"
else
    warn "No config/hypr/hyprland.lua found; skipping"
fi

# ---------- Quickshell ----------
# ~/.config/quickshell is a real directory: each file links into the repo,
# and Theme.qml links to whichever theme is current.
log "Linking Quickshell config"
mkdir -p "$CONF/quickshell"
for f in "$REPO"/config/quickshell/*; do
    [ -f "$f" ] && link "$f" "$CONF/quickshell/$(basename "$f")"
done
link "$CONF/hypora/themes/current/Theme.qml" "$CONF/quickshell/Theme.qml"

# ---------- bin (optional) ----------
shopt -s nullglob
bin_files=("$REPO"/bin/*)
if [ ${#bin_files[@]} -gt 0 ]; then
    log "Linking bin scripts to ~/.local/bin"
    for f in "${bin_files[@]}"; do
        chmod +x "$f"
        link "$f" "$HOME/.local/bin/$(basename "$f")"
    done
fi

# ---------- done ----------
log "Done."
cat <<EOF

Next steps:
  1. No login screen is installed yet. From a text console (TTY), start the desktop with:
         uwsm start hyprland-uwsm.desktop
     (or just 'Hyprland' if uwsm gives you trouble)
  2. If the bar doesn't appear, run 'qs' in a terminal to see QML errors.
  3. Test notifications:  notify-send "Test" "Hello"
     Test polkit:         pkexec true

Existing files that were replaced were saved as <name>.bak.<timestamp>.
EOF
