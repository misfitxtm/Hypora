#!/usr/bin/env bash
# Minimal installer for testing on a fresh Fedora install.
# Covers: packages, Hyprland (Lua) config, Quickshell config, theme, SDDM login screen.
# NOT included: packages/ lists.
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

# Fedora doesn't ship Hyprland or uwsm; sdegler/hyprland tracks current releases
# (the old solopasha COPR stopped at 0.49, before Lua configs existed).
sudo dnf copr disable -y solopasha/hyprland >/dev/null 2>&1 || true
log "Enabling COPR sdegler/hyprland"
sudo dnf copr enable -y sdegler/hyprland
available quickshell || die "quickshell not found in enabled repos (it ships in Fedora 42+)."

# ---------- packages ----------
REQUIRED=(
    hyprland uwsm quickshell kitty git
    NetworkManager NetworkManager-tui
    pipewire wireplumber upower
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    polkit jetbrains-mono-fonts sddm
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
# 'install' leaves an already-installed (possibly old) Hyprland alone
sudo dnf upgrade -y hyprland uwsm || true

# Hyprland reads hyprland.lua only from 0.55 on; older versions ignore it entirely
# (no autostart, no keybinds) and generate a default hyprland.conf instead.
hypr_ver=$(Hyprland --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [ -n "$hypr_ver" ] && [ "$(printf '%s\n' 0.55.0 "$hypr_ver" | sort -V | head -1)" != 0.55.0 ]; then
    die "Hyprland $hypr_ver is too old for hyprland.lua (need 0.55+). Run: sudo dnf upgrade --refresh hyprland"
fi

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
# Drop links to files that were removed from the repo (e.g. the old qmldir)
for l in "$CONF"/quickshell/*; do
    if [ -L "$l" ] && [ ! -e "$l" ] && [[ "$(readlink "$l")" == "$REPO"/* ]]; then rm "$l"; fi
done
link "$CONF/hypora/themes/current/Theme.qml" "$CONF/quickshell/Theme.qml"

# ---------- login screen (SDDM) ----------
# Same setup as Omarchy: SDDM on a minimal Hyprland session with a small QML theme.
# The theme's colors are generated from the active Hypora theme.
log "Installing SDDM login screen"
SDDM_THEME=/usr/share/sddm/themes/hypora
sudo install -d "$SDDM_THEME" /etc/sddm.conf.d
sudo install -m644 "$REPO"/system/sddm/hypora/{Main.qml,metadata.desktop} "$SDDM_THEME/"
sudo install -m644 "$REPO/system/sddm/hyprland.lua" "$SDDM_THEME/hyprland.lua"
{
    echo "[General]"
    sed -nE 's/.*property (color|string) (bg|surface|fg|dim|accent|error|font): *("[^"]*").*/\2=\3/p' \
        "$REPO/themes/$THEME/Theme.qml"
} | sudo tee "$SDDM_THEME/theme.conf" >/dev/null
sudo install -m644 "$REPO/system/sddm/10-hypora.conf" /etc/sddm.conf.d/10-hypora.conf

for dm in gdm lightdm greetd; do
    if systemctl is-enabled -q "$dm" 2>/dev/null; then
        sudo systemctl disable "$dm"
        warn "Disabled $dm (Hypora uses SDDM)"
    fi
done
sudo systemctl enable sddm

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
  1. Reboot. The Hypora login screen (SDDM) starts the uwsm-managed Hyprland session.
     If it doesn't come up: Ctrl+Alt+F2, log in, and check 'journalctl -b -u sddm'.
  2. If the bar doesn't appear, run 'qs' in a terminal to see QML errors.
     If keybinds don't work, run 'hyprctl configerrors'.
  3. Test notifications:  notify-send "Test" "Hello"
     Test polkit:         pkexec true

Existing files that were replaced were saved as <name>.bak.<timestamp>.
EOF
