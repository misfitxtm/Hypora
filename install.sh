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
# Warnings are shown as they happen and kept, so the summary at the end can repeat them.
# A 400-line install scrolls past; the one line that mattered shouldn't only appear there.
WARNINGS=()
warn() { WARNINGS+=("$*"); printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
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

# pin_clone <url> <commit> <dest>: check out exactly one reviewed commit, nothing else.
#
# The same argument as fetch_verified, for git. `git clone --depth 1 <url>` takes whatever
# the default branch points at today, and both repositories below are *executed* code — Oh
# My Zsh runs on every interactive shell, the LazyVim starter runs inside Neovim. An upstream
# compromise would therefore run as you, on your next shell. Everything else this installer
# fetches is pinned to a hash or a GPG fingerprint; these were the exception.
#
# Fetching a bare commit needs the server to allow it, which GitHub does. The rev-parse at
# the end is the actual guarantee: without it this would just be a slower unpinned clone.
pin_clone() {
    local url=$1 commit=$2 dest=$3
    rm -rf "$dest"
    git init -q "$dest" 2>/dev/null || { warn "Could not create $dest"; return 1; }
    git -C "$dest" remote add origin "$url" || return 1
    if ! git -C "$dest" fetch -q --depth 1 origin "$commit" 2>/dev/null; then
        rm -rf "$dest"
        warn "Could not fetch $commit from $url"
        return 1
    fi
    git -C "$dest" checkout -q FETCH_HEAD || { rm -rf "$dest"; return 1; }
    if [ "$(git -C "$dest" rev-parse HEAD)" != "$commit" ]; then
        rm -rf "$dest"
        warn "$url did not check out $commit"
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
    # Secret Service provider. GNOME's session starts one and Hyprland doesn't, so without
    # this an app looking for somewhere to keep a token finds no provider — and some then
    # fall back to writing it to disk unencrypted. Started from hyprland.lua.
    gnome-keyring
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
    # Qt can only decode jpeg, png, gif and svg out of the box. Hypora's own wallpapers are
    # all jpeg, but the wallpaper and theme pickers accept webp too, and without this a webp
    # you drop in yourself is listed and then renders as nothing.
    qt6-qtimageformats
    # Boot screen, including the LUKS passphrase prompt. Fedora ships these already; they
    # are listed so a minimal install still gets a themed boot rather than a bare console.
    plymouth plymouth-plugin-two-step plymouth-scripts
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
    #
    # Pinned, like every other artifact here. Bumping it is a deliberate edit: read what
    # changed, then update the commit. config/zsh/zshrc turns Oh My Zsh's own auto-update
    # off, because a framework that silently pulls master would make this pin decorative.
    log "Installing Oh My Zsh"
    pin_clone https://github.com/ohmyzsh/ohmyzsh.git \
        60c9a7a839b790cd905d0fd4419435124fd1bdc0 \
        "$HOME/.oh-my-zsh" || warn "Could not install Oh My Zsh"
fi

# LazyVim starter, only when ~/.config/nvim is empty; an existing config is left alone.
if [ -e "$CONF/nvim/init.lua" ] || [ -e "$CONF/nvim/init.vim" ]; then
    log "Keeping your existing Neovim config"
elif pin_clone https://github.com/LazyVim/starter \
        803bc181d7c0d6d5eeba9274d9be49b287294d99 "$CONF/nvim"; then
    rm -rf "$CONF/nvim/.git"
    log "Installed the LazyVim starter"
else
    warn "Could not install the LazyVim starter"
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
# DNS through systemd-resolved, encrypted opportunistically, and MAC addresses that don't
# follow you between networks. Both files carry the full reasoning; the short version is
# that DNS follows the network so a resolver you run yourself stays in charge, and Wi-Fi
# and ethernet present a per-network address instead of the card's permanent serial number.
log "Setting up DNS and MAC address privacy"
sudo install -d /etc/systemd/resolved.conf.d /etc/NetworkManager/conf.d
sudo install -m644 "$REPO/system/systemd/resolved.conf.d/hypora-dns.conf" /etc/systemd/resolved.conf.d/hypora-dns.conf
sudo install -m644 "$REPO/system/NetworkManager/conf.d/hypora-dns.conf" /etc/NetworkManager/conf.d/hypora-dns.conf
sudo install -m644 "$REPO/system/NetworkManager/conf.d/hypora-mac.conf" /etc/NetworkManager/conf.d/hypora-mac.conf
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
#
# SSH is then closed as well, which Fedora leaves open. A desktop nobody logs into remotely
# has no reason to answer on 22, and sshd is the one service reachable from the network by
# default. Set KEEP_SSH=yes to leave it alone.
#
# Never when the installer is itself running over SSH: closing the port you arrived on, on a
# machine you are not sitting at, is how an install ends in a drive to the office.
KEEP_SSH=${KEEP_SSH:-}
if [ -z "$KEEP_SSH" ] && [ -n "${SSH_CONNECTION:-}${SSH_TTY:-}${SSH_CLIENT:-}" ]; then
    KEEP_SSH=yes
    warn "Running over SSH, so SSH is being left enabled and open"
fi

log "Enabling the firewall"
sudo systemctl enable --now firewalld || warn "Could not enable firewalld"
if systemctl is-active --quiet firewalld; then
    sudo firewall-cmd --quiet --set-default-zone=public || warn "Could not set the default firewall zone"
    if [ "$KEEP_SSH" != yes ]; then
        sudo firewall-cmd --quiet --permanent --remove-service=ssh 2>/dev/null || true
    fi
    sudo firewall-cmd --quiet --permanent --add-port=53317/tcp || true   # LocalSend
    sudo firewall-cmd --quiet --permanent --add-port=53317/udp || true
    sudo firewall-cmd --quiet --reload || true
fi

# Stop the daemon too, not just block the port: a listener nothing can reach is still a
# listener, and it comes back the moment someone widens a zone. Left installed, so turning
# it back on is `sudo systemctl enable --now sshd`.
if [ "$KEEP_SSH" != yes ]; then
    if systemctl is-enabled --quiet sshd 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
        log "Disabling the SSH server (KEEP_SSH=yes to keep it)"
        sudo systemctl disable --now sshd 2>/dev/null || warn "Could not disable sshd"
    fi
fi

# Automatic security updates, in two halves because nothing covers both.
# dnf5-automatic takes the system packages, limited to Fedora security advisories so the
# Hyprland COPR is never upgraded behind your back (third-party repos ship no advisory
# metadata, so they can't match). A timer of our own takes the flatpaks, which dnf cannot
# see at all and which include the browser.
# Both timers are enabled without --now on purpose: they are Persistent, so starting them
# here would fire a transaction immediately and fight the installer for the dnf lock. They
# take effect at the reboot the install ends with.
log "Enabling automatic security updates"
sudo dnf install -y dnf5-plugin-automatic \
    || sudo dnf install -y dnf-automatic \
    || warn "Could not install dnf-automatic"
if command -v dnf-automatic >/dev/null 2>&1; then
    # Both dnf5's plugin and dnf4's dnf-automatic read this path and share these keys
    sudo install -d /etc/dnf
    sudo install -m644 "$REPO/system/dnf/automatic.conf" /etc/dnf/automatic.conf
    sudo systemctl enable dnf5-automatic.timer 2>/dev/null \
        || sudo systemctl enable dnf-automatic.timer 2>/dev/null \
        || warn "Could not enable the automatic update timer"
else
    warn "dnf-automatic is not available; system updates stay manual"
fi
sudo install -m644 "$REPO/system/systemd/system/hypora-flatpak-update.service" \
    /etc/systemd/system/hypora-flatpak-update.service
sudo install -m644 "$REPO/system/systemd/system/hypora-flatpak-update.timer" \
    /etc/systemd/system/hypora-flatpak-update.timer
sudo systemctl daemon-reload
sudo systemctl enable hypora-flatpak-update.timer \
    || warn "Could not enable the flatpak update timer"

# Hardware that didn't come up. A laptop with no Wi-Fi or Bluetooth after a fresh install is
# usually one of three things — firmware package absent, driver never bound, or the radio
# soft-blocked — and they look identical from the desktop. hypora-hardware separates them and
# fixes the ones that can be fixed from Fedora's own repositories. It never adds a third-party
# repo; where a chip needs one (Broadcom's wl, typically) it says so and leaves it to you.
# Run from the repo, not from ~/.local/bin. Two reasons, both of which bit:
#   * ~/.local/bin is writable by you, and this runs under sudo — anything that could write
#     your home directory would have earned root the next time you ran the installer. The
#     repo is the tree you are already executing, so it grants nothing new.
#   * ~/.local/bin/hypora-hardware doesn't exist yet at this point in the script (bin/ is
#     installed further down), so on a *fresh* install the guard was false and this never
#     ran at all — on exactly the case it was written for, a new install with no Wi-Fi.
if [ -x "$REPO/bin/hypora-hardware" ]; then
    log "Checking hardware, firmware and drivers"
    sudo "$REPO/bin/hypora-hardware" fix || warn "Some hardware could not be fixed"
    "$REPO/bin/hypora-hardware" probe || true
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
# Scripts that get run as root must live somewhere only root can write. A copy under
# ~/.local/bin would let anything that can write your home directory earn root the next time
# you ran it — which is the whole attack, and it does not require the attacker to be root
# already. So these go to /usr/local/bin, owned by root, and the user-writable copies are
# removed:
#
#   hypora-security   run by pkexec from the Security window
#   hypora-console    documented as `sudo hypora-console apply`; it writes the kernel
#                     command line, so a tampered copy is a boot-integrity problem
#   hypora-hardware   documented as `sudo hypora-hardware fix`; it installs packages and
#                     loads kernel modules
#
# The test is simply "does anything tell you to run this under sudo", which is why these
# three and not the others — the rest never need more than your own privileges.
ROOT_OWNED=(hypora-security hypora-console hypora-hardware)

for name in "${ROOT_OWNED[@]}"; do
    log "Installing $name to /usr/local/bin (root-owned)"
    sudo install -m755 -o root -g root "$REPO/bin/$name" "/usr/local/bin/$name"
    # Drop any user-writable copy an earlier version of this installer left behind
    rm -f "$HOME/.local/bin/$name"
done

shopt -s nullglob
bin_files=("$REPO"/bin/*)
if [ ${#bin_files[@]} -gt 0 ]; then
    log "Installing bin scripts to ~/.local/bin"
    for f in "${bin_files[@]}"; do
        name=$(basename "$f")
        skip=
        for r in "${ROOT_OWNED[@]}"; do [ "$name" = "$r" ] && skip=1; done
        [ -n "$skip" ] && continue        # root-owned, installed above
        put "$f" "$HOME/.local/bin/$name" 755
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

# Boot screen, including the LUKS passphrase prompt. Plymouth renders that prompt, so
# theming it means shipping a Plymouth theme; the two-step module is the one Fedora's own
# themes use. The theme has to be inside the initramfs to exist that early, which is what
# -R rebuilds — the slowest single step in this script, and the reason hypora-theme doesn't
# do it on every theme switch.
RENDERED_PLY="$CONF/hypora/current/plymouth.plymouth"
if command -v plymouth-set-default-theme >/dev/null 2>&1 && [ -f "$RENDERED_PLY" ]; then
    log "Installing the boot screen theme"
    sudo install -d -m755 /usr/share/plymouth/themes/hypora
    sudo install -m644 -o root -g root "$RENDERED_PLY" \
        /usr/share/plymouth/themes/hypora/hypora.plymouth
    if [ -d "$CONF/hypora/current/plymouth" ]; then
        sudo install -m644 -o root -g root "$CONF"/hypora/current/plymouth/*.png \
            /usr/share/plymouth/themes/hypora/
    fi
    # Plymouth's own tools grep this file unanchored and expand the result unquoted, so a
    # second line matching one of their keys — a comment mentioning it, say — makes the value
    # two lines. The test downstream then fails with "too many arguments", which is not fatal
    # in itself, but the module afterwards gets installed under a mangled path and never
    # reaches the initramfs, so the boot screen silently falls back to text. Catch it here,
    # where the message can say what actually went wrong.
    ply_dupes=0
    for key in ModuleName ImageDir; do
        n=$(grep -cE "${key} *= *" /usr/share/plymouth/themes/hypora/hypora.plymouth 2>/dev/null || true)
        n=${n:-0}
        if [ "$n" -ne 1 ]; then
            warn "hypora.plymouth has $n lines matching '$key'; Plymouth needs exactly one"
            ply_dupes=1
        fi
    done

    # A theme missing its images leaves you with no visible passphrase prompt, which on an
    # encrypted disk means no way in short of Esc for the text fallback. Only switch to it
    # once the field and its bullets are actually on disk.
    if [ "$ply_dupes" -eq 0 ] \
       && [ -f /usr/share/plymouth/themes/hypora/entry.png ] \
       && [ -f /usr/share/plymouth/themes/hypora/bullet.png ]; then
        sudo plymouth-set-default-theme hypora -R \
            || warn "Could not set the boot theme; the previous one is still in place"
    else
        warn "Boot screen images are missing; leaving the existing boot theme alone"
    fi
else
    warn "Plymouth is not installed; the boot screen stays as it is"
fi

# ---------- bookkeeping ----------
prune
mkdir -p "$(dirname "$MANIFEST")"
mv "$NEW_MANIFEST" "$MANIFEST"

# ---------- optional third-party repositories ----------
# RPM Fusion carries what Fedora won't ship: patent-encumbered codecs, NVIDIA's own driver,
# Broadcom's wl. Off unless you ask for it, because it is a different trust decision from the
# rest of Hypora — the release RPMs are fetched over HTTPS from rpmfusion.org and cannot be
# pinned to a fingerprint the way the Hyprland COPR and Anthropic's repository are, since both
# the package and its key change with every Fedora release. Once installed, packages from it
# are GPG-checked normally.
#
# Set ENABLE_RPMFUSION=yes or =no to answer ahead of time.
want_rpmfusion() {
    case "${ENABLE_RPMFUSION:-}" in
        yes|y|1) return 0 ;;
        no|n|0)  return 1 ;;
    esac
    if rpm -q rpmfusion-free-release >/dev/null 2>&1; then
        log "RPM Fusion is already enabled"
        return 1
    fi
    if [ ! -t 0 ]; then
        log "Skipping RPM Fusion (no terminal to ask; set ENABLE_RPMFUSION=yes to enable it)"
        return 1
    fi
    printf '\n%s\n%s\n%s\n' \
        "RPM Fusion (free and nonfree) carries packages Fedora cannot: media codecs," \
        "NVIDIA's own graphics driver, and firmware for some Broadcom and Realtek chips." \
        "It is a third-party repository, so this is your trust decision, not Hypora's." >&2
    printf '  Remove later with: sudo dnf remove rpmfusion-free-release rpmfusion-nonfree-release\n' >&2
    read -r -p "Enable RPM Fusion? [y/N] " answer
    case "$answer" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

if want_rpmfusion; then
    log "Enabling RPM Fusion"
    rel=$(rpm -E %fedora)
    sudo dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$rel.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$rel.noarch.rpm" \
        || warn "Could not enable RPM Fusion"
else
    log "Skipping RPM Fusion"
fi

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

# ---------- done ----------
# The hexagon mark from config/quickshell/Logo.qml, in its own two colours. Printed with
# truecolor escapes where the terminal supports them and plain otherwise, so this still
# reads on a TTY after a failed graphical boot — which is exactly when someone is looking.
banner() {
    # The same mark fastfetch prints, so there is one ASCII Hypora rather than two. That file
    # uses $1 and $2 as colour slots; substitute the logo's own two colours into them.
    local a b r logo="$REPO/config/fastfetch/hypora.txt"
    if [ "${COLORTERM:-}" = "truecolor" ] || [ "${COLORTERM:-}" = "24bit" ]; then
        a=$'\033[38;2;122;162;247m'; b=$'\033[38;2;195;122;247m'
    else
        a=$'\033[36m'; b=$'\033[35m'
    fi
    r=$'\033[0m'
    printf '\n'
    if [ -r "$logo" ]; then
        sed -e "s/\$1/$a/g" -e "s/\$2/$b/g" -e "s/\$/$r/" "$logo"
    else
        printf '   %sH Y P O R A%s\n' "$a" "$r"
    fi
    printf '\n'
}

banner

if [ ${#WARNINGS[@]} -eq 0 ]; then
    printf '\033[1;32m Hypora was installed successfully.\033[0m\n\n'
else
    printf '\033[1;32m Hypora was installed\033[0m, with \033[1;33m%d warning(s)\033[0m:\n\n' "${#WARNINGS[@]}"
    for w in "${WARNINGS[@]}"; do printf '   \033[1;33m!!\033[0m %s\n' "$w"; done
    printf '\n'
fi

cat <<'EOF'
 Reboot to finish. The Hypora login screen starts the Hyprland session.

   sudo reboot

 Group memberships and your new zsh shell also need that reboot to take effect.
 If the desktop does not come up, switch to a console with Ctrl+Alt+F2 and run:

   journalctl -b -u sddm      why the login screen failed
   qs                         QML errors from the shell
   hyprctl configerrors       problems in hyprland.lua
   hypora-hardware probe      hardware with no driver, firmware or radio

EOF
