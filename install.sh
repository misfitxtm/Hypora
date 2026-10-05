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

# fetch_verified <url> <dest> <sha256>: download, and refuse it unless the hash matches.
# Every version below is pinned deliberately. HTTPS proves you reached the right host; it
# says nothing about whether the file behind it changed, so each artifact is pinned to a
# release and checked against a hash recorded when it was reviewed. Bumping a version means
# updating its hash here on purpose.
fetch_verified() {
    local url=$1 dest=$2 want=$3 got
    curl -fsSL "$url" -o "$dest" || { warn "Could not download $url"; return 1; }
    got=$(sha256sum "$dest" | cut -d' ' -f1)
    if [ "$got" != "$want" ]; then
        rm -f "$dest"
        warn "Checksum mismatch for $url"
        warn "  expected $want"
        warn "  got      $got"
        return 1
    fi
}

# ---------- repos ----------
log "Preparing repositories"
sudo dnf install -y dnf-plugins-core

# Fedora doesn't ship Hyprland or uwsm; sdegler/hyprland tracks current releases
# (the old solopasha COPR stopped at 0.49, before Lua configs existed).
sudo dnf copr disable -y solopasha/hyprland >/dev/null 2>&1 || true
# COPR packages are GPG-signed and dnf verifies them, but `copr enable` trusts whatever
# key the server offers the first time. Check it against the fingerprint recorded here
# before anything from this repo can be installed.
HYPRLAND_COPR_FPR=64BBBF013D1CA5E4BE5B0552C043104207862204
log "Enabling COPR sdegler/hyprland"
sudo dnf copr enable -y sdegler/hyprland
copr_key=$(mktemp)
if curl -fsSL "https://download.copr.fedorainfracloud.org/results/sdegler/hyprland/pubkey.gpg" -o "$copr_key" \
    && [ "$(gpg --show-keys --with-colons "$copr_key" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')" = "$HYPRLAND_COPR_FPR" ]; then
    sudo rpm --import "$copr_key"
    log "Hyprland COPR signing key verified"
else
    rm -f "$copr_key"
    sudo dnf copr disable -y sdegler/hyprland >/dev/null 2>&1 || true
    die "The Hyprland COPR signing key did not match the expected fingerprint. Stopping."
fi
rm -f "$copr_key"
available quickshell || die "quickshell not found in enabled repos (it ships in Fedora 42+)."

# ---------- packages ----------
REQUIRED=(
    hyprland hyprland-guiutils hyprlock hypridle uwsm quickshell kitty git
    # Shell and editor
    zsh zsh-autosuggestions zsh-syntax-highlighting fastfetch
    neovim ripgrep fd-find
    polkit sddm qt6-qtsvg gnupg2 curl tar xz unzip firewalld
    # Fonts, icons and app theming (JetBrainsMono Nerd Font is downloaded below)
    liberation-sans-fonts liberation-serif-fonts adwaita-icon-theme
    papirus-icon-theme breeze-icon-theme
    adw-gtk3-theme qt6ct
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-user-dirs xdg-utils
    # Network. nmtui is the fallback behind the Network window's "Advanced"
    NetworkManager NetworkManager-tui NetworkManager-wifi
    # Sound: PipeWire + WirePlumber, wiremix (sound TUI), pulseaudio compatibility
    pipewire wireplumber pipewire-pulseaudio wiremix
    # Bluetooth. bluez also provides bluetoothctl, the fallback behind "Advanced"
    bluez
    # Battery and power modes
    upower
    # Read the machine's security state for the Security window
    fwupd mokutil policycoreutils
    # Files, clipboard history and screenshots (SUPER+E, SUPER+SHIFT+V, SUPER+SHIFT+S)
    # GNOME's apps, without the GNOME session: none of these pull gnome-shell, mutter,
    # gnome-session or gdm. Nautilus does bring `localsearch`, a background indexer that
    # reads your home directory — see the readme if you'd rather it didn't.
    nautilus gvfs gnome-calculator gnome-disk-utility gnome-software
    cliphist wl-clipboard grim slurp
)
# Nice to have; a missing one only produces a warning
OPTIONAL=(
    hyprsunset brightnessctl
    pamixer playerctl
    google-noto-emoji-fonts
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

# impala and bluetui used to be downloaded here. The Network and Bluetooth windows now
# cover what they were for, and nmtui and bluetoothctl — both already installed — are the
# fallback behind each window's "Advanced". Remove the old binaries if an earlier install
# left them behind.
sudo rm -f /usr/local/bin/impala /usr/local/bin/bluetui

# Hyprland reads hyprland.lua only from 0.55 on; older versions ignore it entirely
# (no autostart, no keybinds) and generate a default hyprland.conf instead.
hypr_ver=$(Hyprland --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [ -n "$hypr_ver" ] && [ "$(printf '%s\n' 0.55.0 "$hypr_ver" | sort -V | head -1)" != 0.55.0 ]; then
    die "Hyprland $hypr_ver is too old for hyprland.lua (need 0.55+). Run: sudo dnf upgrade --refresh hyprland"
fi

# ---------- fonts ----------
# JetBrainsMono Nerd Font for monospace and the shell UI, Liberation for sans-serif
# and serif. The Nerd Font isn't packaged for Fedora; install the official
# release system-wide so the login screen (which runs as the sddm user) can use it too.
NERD_FONT_VERSION=v3.5.1
NERD_FONT_SHA=04d5e8f903693f9dd13e16f867e994834e681eb3c72c0d337a770dcda09010cf
NERD_FONT_DIR=/usr/local/share/fonts/JetBrainsMonoNerdFont
if ! ls "$NERD_FONT_DIR"/*.ttf >/dev/null 2>&1; then
    log "Installing JetBrainsMono Nerd Font"
    tmp=$(mktemp -d)
    if fetch_verified \
        "https://github.com/ryanoasis/nerd-fonts/releases/download/$NERD_FONT_VERSION/JetBrainsMono.tar.xz" \
        "$tmp/font.tar.xz" "$NERD_FONT_SHA" \
        && tar -xJf "$tmp/font.tar.xz" -C "$tmp"; then
        sudo install -d "$NERD_FONT_DIR"
        sudo install -m644 "$tmp"/*.ttf "$NERD_FONT_DIR/"
    else
        warn "Could not install JetBrainsMono Nerd Font"
    fi
    rm -rf "$tmp"
fi
sudo install -m644 "$REPO/system/fontconfig/50-hypora.conf" /etc/fonts/conf.d/50-hypora.conf

# Gruvbox Plus icons (GPL-3.0). Not packaged for Fedora, so take the release zip.
GRUVBOX_ICONS=/usr/share/icons/Gruvbox-Plus-Dark
if [ -f "$GRUVBOX_ICONS/index.theme" ]; then
    log "Gruvbox Plus icons already installed"
else
    log "Installing Gruvbox Plus icons"
    tmp=$(mktemp -d)
    if fetch_verified \
        "https://github.com/SylEleuth/gruvbox-plus-icon-pack/releases/download/v6.6.0/gruvbox-plus-icon-pack-6.6.0.zip" \
        "$tmp/icons.zip" b10a8d6378d7b88ca6d21b90797a4aa7bbdbb1907ea74101a4b9db439d2773a2 \
        && unzip -q "$tmp/icons.zip" -d "$tmp"; then
        sudo cp -r "$tmp/Gruvbox-Plus-Dark" "$tmp/Gruvbox-Plus-Light" /usr/share/icons/
        sudo gtk-update-icon-cache -qf "$GRUVBOX_ICONS" 2>/dev/null || true
    else
        warn "Could not install the Gruvbox Plus icons; Papirus stays the fallback"
    fi
    rm -rf "$tmp"
fi
sudo fc-cache -f >/dev/null 2>&1 || true

# ---------- AI tools (optional) ----------
# Claude Code is not installed unless you say so. Set INSTALL_CLAUDE=yes or =no to answer
# ahead of time; without an answer on a non-interactive run it is skipped.
CLAUDE_KEY_FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE

want_claude() {
    case "${INSTALL_CLAUDE:-}" in
        yes|y|1) return 0 ;;
        no|n|0)  return 1 ;;
    esac
    if [ ! -t 0 ]; then
        log "Skipping Claude Code (no terminal to ask; set INSTALL_CLAUDE=yes to install it)"
        return 1
    fi
    printf '\n%s\n%s\n' \
        "Claude Code is an AI coding assistant from Anthropic. It needs a paid Claude plan." \
        "It installs from Anthropic's signed dnf repository and can be removed later with:" >&2
    printf '  sudo dnf remove claude-code && sudo rm /etc/yum.repos.d/claude-code.repo\n' >&2
    read -r -p "Install Claude Code? [y/N] " answer
    case "$answer" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

if want_claude; then
    log "Installing Claude Code"
    # Check the signing key against the fingerprint Anthropic publishes before rpm trusts it
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
else
    log "Skipping Claude Code"
fi

# ---------- Flatpak ----------
# Flathub as a system remote, then the apps. Each install is skipped if it's already
# there, so re-running costs nothing. Set SKIP_FLATPAKS=1 to install none of them.
log "Setting up Flatpak"
sudo dnf install -y flatpak
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
    || warn "Could not add the Flathub remote"

# Sandboxed by default. Firefox is here rather than as an RPM because a browser handles
# the most hostile input on the machine and Mozilla publishes a verified build; the rest of
# the package list stays native, either because no maintained flatpak exists or because
# sandboxing something that needs host access just means handing it the host anyway.
FLATPAKS=(
    io.github.flattool.Warehouse     # manage installed flatpaks and their leftover data
    com.github.tchx84.Flatseal       # review and change each flatpak's permissions
    org.mozilla.firefox              # publisher-verified by Mozilla
    com.bitwarden.desktop
    org.localsend.localsend_app
    com.valvesoftware.Steam
    net.lutris.Lutris
    com.spotify.Client               # sandboxed, rather than an unmaintained terminal client
)
if [ "${SKIP_FLATPAKS:-0}" = "1" ]; then
    log "Skipping Flatpak apps (SKIP_FLATPAKS=1)"
else
    log "Installing Flatpak apps (this pulls a few GB the first time)"
    for app in "${FLATPAKS[@]}"; do
        if flatpak info "$app" >/dev/null 2>&1; then
            log "  $app is already installed"
        else
            sudo flatpak install -y --noninteractive flathub "$app" \
                || warn "Could not install $app"
        fi
    done
fi

# ---------- shell and editor ----------
# Oh My Zsh: installed unattended, keeping Hypora's .zshrc (installed further down) and
# leaving the login shell alone until we set it ourselves below.
if [ -d "$HOME/.oh-my-zsh" ]; then
    log "Oh My Zsh already installed"
else
    # Clone the repository rather than piping its installer into a shell. With
    # RUNZSH=no CHSH=no KEEP_ZSHRC=yes that script only clones anyway — Hypora writes its
    # own .zshrc and sets the login shell itself — so running it bought nothing and meant
    # executing a file fetched from a moving branch.
    log "Installing Oh My Zsh"
    git clone -q --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" \
        || warn "Could not clone Oh My Zsh"
fi

# LazyVim starter, only when ~/.config/nvim is empty; an existing config is left alone.
if [ -e "$CONF/nvim/init.lua" ] || [ -e "$CONF/nvim/init.vim" ]; then
    log "Keeping your existing Neovim config"
elif git clone -q --depth 1 https://github.com/LazyVim/starter "$CONF/nvim" 2>/dev/null; then
    rm -rf "$CONF/nvim/.git"
    log "Installed the LazyVim starter"
else
    warn "Could not clone the LazyVim starter"
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

# NetworkManager keeps its own default Wi-Fi backend. An earlier version switched it to
# iwd purely so impala would work; with impala gone there is no reason to touch it, so put
# a machine that took that switch back on the stock configuration.
IWD_CONF=/etc/NetworkManager/conf.d/hypora-iwd.conf
if [ -e "$IWD_CONF" ]; then
    log "Restoring NetworkManager's default Wi-Fi backend"
    sudo rm -f "$IWD_CONF"
    sudo systemctl disable iwd 2>/dev/null || true
    sudo systemctl enable wpa_supplicant 2>/dev/null || true
fi
# Encrypted DNS through systemd-resolved. Plain DNS tells whoever runs the network every
# domain you visit; these queries go to Quad9 over TLS instead. DNSOverTLS=yes is strict:
# if the encrypted resolver can't be reached, lookups fail rather than quietly falling back
# to plaintext. That is the point, but it also means captive portals (hotel and airport
# Wi-Fi) can't be reached until you relax it — see the readme.
log "Setting up encrypted DNS"
sudo install -d /etc/systemd/resolved.conf.d /etc/NetworkManager/conf.d
sudo install -m644 "$REPO/system/systemd/resolved.conf.d/hypora-dns.conf" /etc/systemd/resolved.conf.d/hypora-dns.conf
sudo install -m644 "$REPO/system/NetworkManager/conf.d/hypora-dns.conf" /etc/NetworkManager/conf.d/hypora-dns.conf
sudo systemctl enable --now systemd-resolved || warn "Could not enable systemd-resolved"
# resolv.conf has to point at the stub, or applications bypass resolved entirely
if [ ! -L /etc/resolv.conf ]; then
    sudo ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf \
        || warn "Could not point /etc/resolv.conf at systemd-resolved"
fi
# Restarting NetworkManager blips the connection, which is why this runs after the package
# installs and before the local config steps
sudo systemctl try-restart systemd-resolved NetworkManager 2>/dev/null || true

# Firewall. Fedora's FedoraWorkstation zone leaves ports 1025-65535 open on TCP and UDP;
# `public` allows only ssh, mDNS and DHCPv6, which is the right baseline for a desktop that
# serves nothing. LocalSend is the one thing here that listens, so it gets its port back.
log "Enabling the firewall"
sudo systemctl enable --now firewalld || warn "Could not enable firewalld"
if systemctl is-active --quiet firewalld; then
    sudo firewall-cmd --quiet --set-default-zone=public || warn "Could not set the default firewall zone"
    sudo firewall-cmd --quiet --permanent --add-port=53317/tcp || true   # LocalSend
    sudo firewall-cmd --quiet --permanent --add-port=53317/udp || true
    sudo firewall-cmd --quiet --reload || true
fi

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
# SDDM on a minimal Hyprland session with a small QML theme.
# The theme's colors are generated from the active Hypora theme.
log "Installing SDDM login screen"
SDDM_THEME=/usr/share/sddm/themes/hypora
sudo install -d "$SDDM_THEME" /etc/sddm.conf.d
sudo install -m644 "$REPO"/system/sddm/hypora/{Main.qml,metadata.desktop} "$SDDM_THEME/"
sudo install -m644 "$REPO/system/sddm/hyprland.lua" "$SDDM_THEME/hyprland.lua"
# Its colors (theme.conf) are written by hypora-theme. The file stays root-owned: the
# greeter reads it as the sddm user before anyone logs in, and a file you could write would
# put an unprivileged process on the other side of that boundary. install.sh runs with sudo
# already, so the login screen is brought in step here; `hypora-theme <name>` from a
# terminal updates it later, asking for sudo when it needs to.
sudo install -m644 -o root -g root "$REPO/system/sddm/hypora/theme.conf" "$SDDM_THEME/theme.conf"
# Hand back a copy an earlier version of this installer made user-writable
sudo chown root:root "$SDDM_THEME/theme.conf"
sudo install -m644 "$REPO/system/sddm/10-hypora.conf" /etc/sddm.conf.d/10-hypora.conf

for dm in gdm lightdm greetd; do
    if systemctl is-enabled -q "$dm" 2>/dev/null; then
        sudo systemctl disable "$dm"
        warn "Disabled $dm (Hypora uses SDDM)"
    fi
done
sudo systemctl enable sddm

# ---------- terminal and session environment ----------
log "Installing kitty, uwsm, zsh, fastfetch and Neovim settings"
put "$REPO/config/kitty/kitty.conf" "$CONF/kitty/kitty.conf"
put "$REPO/config/uwsm/env" "$CONF/uwsm/env"
put "$REPO/config/hypr/hypridle.conf" "$CONF/hypr/hypridle.conf"
put "$REPO/config/zsh/zshrc" "$HOME/.zshrc"
put "$REPO/config/fastfetch/config.jsonc" "$CONF/fastfetch/config.jsonc"
put "$REPO/config/fastfetch/hypora.txt" "$CONF/fastfetch/hypora.txt"
# Only this one file under ~/.config/nvim is ours; the rest is yours to change
[ -d "$CONF/nvim" ] && put "$REPO/config/nvim/lua/plugins/hypora.lua" "$CONF/nvim/lua/plugins/hypora.lua"

# zsh as the login shell
if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v zsh)" ]; then
    sudo chsh -s "$(command -v zsh)" "$USER" \
        && log "Login shell set to zsh (starts at your next login)" \
        || warn "Could not set zsh as your login shell; run: chsh -s $(command -v zsh)"
fi

# ---------- app entries ----------
# e.g. "Display Settings", so it shows up in the launcher and app menu
log "Installing app entries"
for f in "$REPO"/applications/*.desktop; do
    [ -f "$f" ] && put "$f" "$HOME/.local/share/applications/$(basename "$f")"
done

# ---------- bin ----------
# hypora-security is the one script that gets run as root (via pkexec, from the Security
# window). It must live somewhere only root can write: a copy under ~/.local/bin would let
# anything that can write your home directory earn root the next time you touch a toggle.
log "Installing hypora-security to /usr/local/bin (root-owned)"
sudo install -m755 -o root -g root "$REPO/bin/hypora-security" /usr/local/bin/hypora-security
# Drop the user-writable copy an earlier version of this installer left behind
rm -f "$HOME/.local/bin/hypora-security"

shopt -s nullglob
bin_files=("$REPO"/bin/*)
if [ ${#bin_files[@]} -gt 0 ]; then
    log "Installing bin scripts to ~/.local/bin"
    for f in "${bin_files[@]}"; do
        [ "$(basename "$f")" = hypora-security ] && continue   # root-owned, installed above
        put "$f" "$HOME/.local/bin/$(basename "$f")" 755
    done
fi

# ---------- wallpapers ----------
# Each theme's images come from themes/<Name>/backgrounds/ in the repo. Anything you drop
# into ~/.config/hypora/themes/<Name>/backgrounds/ yourself is left alone.
log "Installing wallpapers"
for f in "$REPO"/themes/*/backgrounds/*; do
    [ -f "$f" ] || continue
    theme=$(basename "$(dirname "$(dirname "$f")")")
    put "$f" "$CONF/hypora/themes/$theme/backgrounds/$(basename "$f")"
done

# ---------- apply the theme ----------
# Renders the palette into Quickshell, kitty, Hyprland, hyprlock, GTK and Qt
log "Applying theme: $THEME"
"$HOME/.local/bin/hypora-theme" "$THEME"

# The login screen's colours live in a root-owned file, so put them in place here where we
# already hold privileges rather than relying on hypora-theme finding a terminal to ask.
RENDERED_SDDM="$CONF/hypora/current/sddm-theme.conf"
if [ -f "$RENDERED_SDDM" ] && [ -d "$SDDM_THEME" ]; then
    sudo install -m644 -o root -g root "$RENDERED_SDDM" "$SDDM_THEME/theme.conf"
fi

# ---------- bookkeeping ----------
prune
mkdir -p "$(dirname "$MANIFEST")"
mv "$NEW_MANIFEST" "$MANIFEST"

# ---------- done ----------
log "Done."
cat <<EOF

Next steps:
  1. Reboot. The Hypora login screen (SDDM) starts the
     uwsm-managed Hyprland session. Log out and back in for the libvirt and wireshark
     group memberships, and your new zsh login shell, to take effect.
  2. Neovim opens with LazyVim; the first start downloads its plugins.
     If it doesn't come up: Ctrl+Alt+F2, log in, and check 'journalctl -b -u sddm'.
  3. If the bar doesn't appear, run 'qs' in a terminal to see QML errors.
     If keybinds don't work, run 'hyprctl configerrors'.
  4. Test notifications:  notify-send "Test" "Hello"
     Test polkit:         pkexec true

Your configs are copies, so this folder can be moved or deleted. To update Hypora later,
git pull (or clone it again) and re-run ./install.sh. Files you had edited were saved as
<name>.bak.<timestamp>.
EOF
