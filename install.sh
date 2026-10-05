#!/usr/bin/env bash
# Minimal installer for testing on a fresh Fedora install.
# Covers: packages, Hyprland (Lua) config, Quickshell config, theme, SDDM login screen.
# NOT included: packages/ lists.
#
# Safe to re-run. Config files are COPIED into place, so the clone can be moved or deleted
# afterwards. To update: git pull (or re-clone) and run this again.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$HOME/.config"
# Keep the theme picked last time (hypora-theme) unless THEME is given
THEME="${THEME:-$(cat "$CONF/hypora/current/name" 2>/dev/null || echo Nord)}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- sanity checks ----------
[ "$(id -u)" -ne 0 ] || die "Run as your normal user, not root (sudo is used where needed)."
. /etc/os-release
[ "${ID:-}" = "fedora" ] || die "This script targets Fedora (found: ${ID:-unknown})."
[ -f "$REPO/themes/$THEME/colors.toml" ] || die "Theme '$THEME' not found in $REPO/themes/"
[ -d "$REPO/config/quickshell" ] || die "Missing $REPO/config/quickshell"

# ---------- helpers ----------
# Every file the installer copies is recorded with its checksum, so a re-run can tell
# files you edited (backed up before replacing) from ones it can update quietly.
MANIFEST="$CONF/hypora/installed.sha256"
NEW_MANIFEST=$(mktemp)
trap 'rm -f "$NEW_MANIFEST"' EXIT

sha() { sha256sum "$1" | cut -c1-64; }
installed_sha() { [ -f "$MANIFEST" ] && awk -v p="$1" 'substr($0, 67) == p { print substr($0, 1, 64) }' "$MANIFEST"; }

# put <src> <dest> [mode]: copy a file into place
put() {
    local src=$1 dest=$2 mode=${3:-644} new
    new=$(sha "$src")
    mkdir -p "$(dirname "$dest")"
    if [ -L "$dest" ]; then
        rm "$dest"   # older Hypora installs symlinked into the clone
    elif [ -f "$dest" ]; then
        local cur; cur=$(sha "$dest")
        if [ "$cur" != "$new" ] && [ "$cur" != "$(installed_sha "$dest")" ]; then
            mv "$dest" "$dest.bak.$(date +%s)"
            warn "Backed up your edited $dest"
        fi
    elif [ -e "$dest" ]; then
        mv "$dest" "$dest.bak.$(date +%s)"
        warn "Backed up existing $dest"
    fi
    install -m "$mode" "$src" "$dest"
    printf '%s  %s\n' "$new" "$dest" >> "$NEW_MANIFEST"
}

# Remove files a previous run installed that Hypora no longer ships (unless you edited them)
prune() {
    [ -f "$MANIFEST" ] || return 0
    local h p
    while IFS= read -r line; do
        h=${line:0:64}; p=${line:66}
        grep -qxF "$line" "$NEW_MANIFEST" && continue
        awk -v p="$p" 'substr($0, 67) == p { f = 1 } END { exit !f }' "$NEW_MANIFEST" && continue
        if [ -f "$p" ] && [ "$(sha "$p")" = "$h" ]; then rm "$p"; fi
    done < "$MANIFEST"
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
    hyprland hyprland-guiutils uwsm quickshell kitty firefox git
    python3-pillow
    polkit sddm qt6-qtsvg gnupg2 curl tar xz
    # Fonts, icons and app theming (JetBrainsMono Nerd Font is downloaded below)
    liberation-sans-fonts liberation-serif-fonts papirus-icon-theme adwaita-icon-theme
    adw-gtk3-theme qt6ct
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-user-dirs xdg-utils
    # Network: NetworkManager on the iwd Wi-Fi backend (impala, the Wi-Fi TUI, needs iwd)
    NetworkManager NetworkManager-tui NetworkManager-wifi iwd
    # Sound: PipeWire + WirePlumber, wiremix (sound TUI), pulseaudio compatibility
    pipewire wireplumber pipewire-pulseaudio wiremix
    # Bluetooth (bluetui, the Bluetooth TUI, is downloaded below)
    bluez
    # Battery and power modes
    upower
)
# Nice to have; a missing one only produces a warning
OPTIONAL=(
    hyprlock hypridle hyprsunset brightnessctl
    pamixer playerctl pavucontrol nautilus
    wl-clipboard grim slurp google-noto-emoji-fonts
    # Network and security tools
    nmap aircrack-ng wireshark wireshark-cli
)

log "Installing required packages"
sudo dnf install -y "${REQUIRED[@]}"

log "Installing virtualization (@virtualization group)"
sudo dnf group install -y virtualization || warn "Could not install the virtualization group"

log "Installing optional packages"
for p in "${OPTIONAL[@]}"; do
    sudo dnf install -y "$p" || warn "Skipped optional package: $p"
done
# 'install' leaves an already-installed (possibly old) Hyprland alone
sudo dnf upgrade -y hyprland uwsm || true

# Power modes: Fedora's default is tuned-ppd (same D-Bus API as power-profiles-daemon).
# Keep power-profiles-daemon if it's already there; the two conflict.
if ! rpm -q power-profiles-daemon >/dev/null 2>&1; then
    sudo dnf install -y tuned-ppd || warn "Could not install tuned-ppd (power modes unavailable)"
fi

# impala (Wi-Fi) and bluetui (Bluetooth) aren't packaged for Fedora; install their static
# release builds from GitHub into /usr/local/bin. Re-running the installer updates them.
install_release() {   # install_release <name> <github repo> <asset name>
    local tmp; tmp=$(mktemp)
    if curl -fsSL "https://github.com/$2/releases/latest/download/$3" -o "$tmp"; then
        sudo install -m755 "$tmp" "/usr/local/bin/$1"
    else
        warn "Could not download $1 from github.com/$2"
    fi
    rm -f "$tmp"
}
log "Installing impala and bluetui"
arch=$(uname -m)
install_release impala  pythops/impala  "impala-$arch-unknown-linux-musl"
install_release bluetui pythops/bluetui "bluetui-$arch-linux-musl"

# Hyprland reads hyprland.lua only from 0.55 on; older versions ignore it entirely
# (no autostart, no keybinds) and generate a default hyprland.conf instead.
hypr_ver=$(Hyprland --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [ -n "$hypr_ver" ] && [ "$(printf '%s\n' 0.55.0 "$hypr_ver" | sort -V | head -1)" != 0.55.0 ]; then
    die "Hyprland $hypr_ver is too old for hyprland.lua (need 0.55+). Run: sudo dnf upgrade --refresh hyprland"
fi

# ---------- fonts ----------
# Same as Omarchy: JetBrainsMono Nerd Font for monospace and the shell UI, Liberation for
# sans-serif and serif. The Nerd Font isn't packaged for Fedora; install the official
# release system-wide so the login screen (which runs as the sddm user) can use it too.
NERD_FONT_DIR=/usr/local/share/fonts/JetBrainsMonoNerdFont
if ! ls "$NERD_FONT_DIR"/*.ttf >/dev/null 2>&1; then
    log "Installing JetBrainsMono Nerd Font"
    tmp=$(mktemp -d)
    if curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz -o "$tmp/font.tar.xz" \
        && tar -xJf "$tmp/font.tar.xz" -C "$tmp"; then
        sudo install -d "$NERD_FONT_DIR"
        sudo install -m644 "$tmp"/*.ttf "$NERD_FONT_DIR/"
    else
        warn "Could not download JetBrainsMono Nerd Font"
    fi
    rm -rf "$tmp"
fi
sudo install -m644 "$REPO/system/fontconfig/50-hypora.conf" /etc/fonts/conf.d/50-hypora.conf
sudo fc-cache -f >/dev/null 2>&1 || true

# ---------- AI tools ----------
# Claude Code from Anthropic's signed dnf repository (stable channel). The signing key is
# checked against the fingerprint Anthropic publishes before rpm trusts it.
CLAUDE_KEY_FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
log "Installing Claude Code"
key=$(mktemp)
if curl -fsSL https://downloads.claude.ai/keys/claude-code.asc -o "$key" \
    && [ "$(gpg --show-keys --with-colons "$key" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')" = "$CLAUDE_KEY_FPR" ]; then
    sudo rpm --import "$key"
    sudo install -m644 "$REPO/system/yum.repos.d/claude-code.repo" /etc/yum.repos.d/claude-code.repo
    sudo dnf install -y claude-code || warn "Could not install claude-code"
else
    warn "Claude Code signing key missing or fingerprint mismatch; skipped Claude Code"
fi
rm -f "$key"

# Hermes Agent (Nous Research) has no dnf repository; it installs per-user under ~/.hermes
# with its official script, which must not run as root. Run 'hermes setup' afterwards.
if command -v hermes >/dev/null 2>&1 || [ -x "$HOME/.local/bin/hermes" ]; then
    log "Hermes Agent already installed (update it with: hermes update)"
else
    log "Installing Hermes Agent"
    script=$(mktemp)
    if curl -fsSL https://hermes-agent.nousresearch.com/install.sh -o "$script"; then
        bash "$script" --non-interactive || warn "Hermes Agent install failed; retry with: curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash"
    else
        warn "Could not download the Hermes Agent installer"
    fi
    rm -f "$script"
fi

# ---------- services ----------
log "Enabling services"
sudo systemctl enable --now NetworkManager || warn "Could not enable NetworkManager"
sudo systemctl enable --now upower || warn "Could not enable upower (battery widget may show nothing)"
sudo systemctl enable --now bluetooth 2>/dev/null || warn "No bluetooth service (the Bluetooth tile will show Unavailable)"
if rpm -q tuned-ppd >/dev/null 2>&1; then
    sudo systemctl enable --now tuned tuned-ppd || warn "Could not enable tuned-ppd"
else
    sudo systemctl enable --now power-profiles-daemon || warn "Could not enable power-profiles-daemon"
fi

if rpm -q libvirt-daemon >/dev/null 2>&1; then
    sudo systemctl enable --now libvirtd || warn "Could not enable libvirtd"
    sudo usermod -aG libvirt "$USER" || true
fi
# Capturing with wireshark/tshark as a normal user needs the wireshark group
if getent group wireshark >/dev/null; then
    sudo usermod -aG wireshark "$USER" || true
fi

# Wi-Fi through iwd so impala works. NetworkManager keeps managing connections (the bar
# and nmcli still work); this takes effect after a reboot so the install isn't cut off.
sudo install -d /etc/NetworkManager/conf.d
printf '[device]\nwifi.backend=iwd\n' | sudo tee /etc/NetworkManager/conf.d/hypora-iwd.conf >/dev/null
sudo systemctl enable iwd || warn "Could not enable iwd"
sudo systemctl disable wpa_supplicant 2>/dev/null || true
sudo systemctl set-default graphical.target

# ---------- themes ----------
# Palettes and templates; bin/hypora-theme renders them (applied at the end)
log "Installing themes"
for f in "$REPO"/themes/*/colors.toml; do
    put "$f" "$CONF/hypora/themes/$(basename "$(dirname "$f")")/colors.toml"
done
for f in "$REPO"/themes/templates/*.tpl; do
    put "$f" "$CONF/hypora/templates/$(basename "$f")"
done

# Older installs kept a 'current' symlink here; the rendered theme now lives in hypora/current/
if [ -L "$CONF/hypora/themes/current" ]; then rm "$CONF/hypora/themes/current"; fi

# ---------- Hyprland ----------
# Hyprland 0.55+ uses a Lua config (hyprland.lua); the old hyprland.conf format is deprecated.
log "Installing Hyprland config"
if [ -f "$REPO/config/hypr/hyprland.lua" ]; then
    put "$REPO/config/hypr/hyprland.lua" "$CONF/hypr/hyprland.lua"
    grep -Eq 'exec_cmd\(.*\b(qs|quickshell)\b' "$REPO/config/hypr/hyprland.lua" \
        || warn "hyprland.lua has no hl.exec_cmd line for Quickshell (e.g. hl.exec_cmd(\"uwsm app -- qs\"))"
    [ -e "$CONF/hypr/hyprland.conf" ] \
        && warn "A legacy ~/.config/hypr/hyprland.conf exists; move it away if Hyprland misbehaves"
else
    warn "No config/hypr/hyprland.lua found; skipping"
fi

# ---------- Quickshell ----------
# Each file is copied into ~/.config/quickshell; Theme.qml points at the current theme.
log "Installing Quickshell config"
mkdir -p "$CONF/quickshell"
# Older installs symlinked into the clone; drop links that no longer resolve
find "$CONF/quickshell" -maxdepth 1 -type l ! -exec test -e {} \; -delete
for f in "$REPO"/config/quickshell/*; do
    [ -f "$f" ] && put "$f" "$CONF/quickshell/$(basename "$f")"
done
# (Theme.qml is linked in by hypora-theme)

# ---------- login screen (SDDM) ----------
# Same setup as Omarchy: SDDM on a minimal Hyprland session with a small QML theme.
# The theme's colors are generated from the active Hypora theme.
log "Installing SDDM login screen"
SDDM_THEME=/usr/share/sddm/themes/hypora
sudo install -d "$SDDM_THEME" /etc/sddm.conf.d
sudo install -m644 "$REPO"/system/sddm/hypora/{Main.qml,metadata.desktop} "$SDDM_THEME/"
sudo install -m644 "$REPO/system/sddm/hyprland.lua" "$SDDM_THEME/hyprland.lua"
# Its colors (theme.conf) are written by hypora-theme. The file is owned by you so the theme
# picker can update it without a password; it only holds colors and a font name.
sudo touch "$SDDM_THEME/theme.conf"
sudo chown "$USER" "$SDDM_THEME/theme.conf"
sudo install -m644 "$REPO/system/sddm/10-hypora.conf" /etc/sddm.conf.d/10-hypora.conf

for dm in gdm lightdm greetd; do
    if systemctl is-enabled -q "$dm" 2>/dev/null; then
        sudo systemctl disable "$dm"
        warn "Disabled $dm (Hypora uses SDDM)"
    fi
done
sudo systemctl enable sddm

# ---------- terminal and session environment ----------
log "Installing kitty and uwsm settings"
put "$REPO/config/kitty/kitty.conf" "$CONF/kitty/kitty.conf"
put "$REPO/config/uwsm/env" "$CONF/uwsm/env"

# ---------- app entries ----------
# e.g. "Display Settings", so it shows up in the launcher and app menu
log "Installing app entries"
for f in "$REPO"/applications/*.desktop; do
    [ -f "$f" ] && put "$f" "$HOME/.local/share/applications/$(basename "$f")"
done

# ---------- bin (optional) ----------
shopt -s nullglob
bin_files=("$REPO"/bin/*)
if [ ${#bin_files[@]} -gt 0 ]; then
    log "Installing bin scripts to ~/.local/bin"
    for f in "${bin_files[@]}"; do
        put "$f" "$HOME/.local/bin/$(basename "$f")" 755
    done
fi

# ---------- wallpapers ----------
# Pixel art drawn from each theme's own palette (bin/hypora-wallgen). Only the files it
# generates are replaced, so your own images in those folders are left alone.
log "Drawing wallpapers"
"$HOME/.local/bin/hypora-wallgen" || warn "Could not draw wallpapers (is python3-pillow installed?)"

# ---------- apply the theme ----------
# Renders the palette into Quickshell, kitty, Hyprland, hyprlock, GTK, Qt and the login screen
log "Applying theme: $THEME"
"$HOME/.local/bin/hypora-theme" "$THEME"

# ---------- bookkeeping ----------
prune
mkdir -p "$(dirname "$MANIFEST")"
mv "$NEW_MANIFEST" "$MANIFEST"

# ---------- done ----------
log "Done."
cat <<EOF

Next steps:
  1. Reboot (this also switches Wi-Fi to iwd). The Hypora login screen (SDDM) starts the
     uwsm-managed Hyprland session. Log out and back in for the libvirt and wireshark
     group memberships to take effect.
     If it doesn't come up: Ctrl+Alt+F2, log in, and check 'journalctl -b -u sddm'.
  2. If the bar doesn't appear, run 'qs' in a terminal to see QML errors.
     If keybinds don't work, run 'hyprctl configerrors'.
  3. Test notifications:  notify-send "Test" "Hello"
     Test polkit:         pkexec true

Your configs are copies, so this folder can be moved or deleted. To update Hypora later,
git pull (or clone it again) and re-run ./install.sh. Files you had edited were saved as
<name>.bak.<timestamp>.
EOF
