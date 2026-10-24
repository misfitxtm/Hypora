#!/usr/bin/env bash
# Hypora installer: run as your normal user on fresh Fedora; safe to re-run, and config is copied so the clone can go.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$HOME/.config"
# Keep the theme chosen last time (hypora-theme) unless THEME is set
THEME="${THEME:-$(cat "$CONF/hypora/current/name" 2>/dev/null || echo Nord)}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
# Warnings print as they happen and are saved, so the summary at the end can repeat them
WARNINGS=()
warn() { WARNINGS+=("$*"); printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- sanity checks ----------
[ "$(id -u)" -ne 0 ] || die "Run as your normal user, not root (sudo is used where needed)."
. /etc/os-release
[ "${ID:-}" = "fedora" ] || die "This script targets Fedora (found: ${ID:-unknown})."
[ -f "$REPO/themes/$THEME/colors.toml" ] || die "Theme '$THEME' not found in $REPO/themes/"
[ -d "$REPO/config/quickshell" ] || die "Missing $REPO/config/quickshell"

# Helpers: every copied file is recorded with its checksum so a re-run can tell your edits from replaceable files.
MANIFEST="$CONF/hypora/installed.sha256"
NEW_MANIFEST=$(mktemp)
trap 'rm -f "$NEW_MANIFEST"' EXIT

# With `set -e` a failure ends the script silently, so print what happened and that the install is partial.
on_err() {
    local code=$? line=$1
    printf '\033[1;31mxx\033[0m %s\n' \
        "Install failed at line $line (exit $code). This leaves a PARTIAL install:" >&2
    printf '   %s\n' \
        "config files may be in place while the theme, login screen and power setup are not." \
        "Fix the error above and re-run ./install.sh — it is safe to re-run and will finish" \
        "the steps it missed. Nothing is removed on a failed run." >&2
}
trap 'on_err $LINENO' ERR

sha() { sha256sum "$1" | cut -c1-64; }
# installed_sha PATH: the checksum recorded for PATH by the last install
installed_sha() { [ -f "$MANIFEST" ] && awk -v p="$1" 'substr($0, 67) == p { print substr($0, 1, 64) }' "$MANIFEST"; }

# put SRC DEST [MODE]: copy a file into place and record it in the manifest
put() {
    local src=$1 dest=$2 mode=${3:-644} new
    # Guard against a directory (from a glob) giving sha256sum's unhelpful error.
    [ -f "$src" ] || die "put: $src is not a regular file (installer bug)"
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

# Remove files an earlier run installed that Hypora no longer ships (unless you edited them)
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

# available PKG: true if dnf can find the package
available() { [ -n "$(dnf repoquery --quiet "$1" 2>/dev/null)" ]; }

# fetch_verified URL DEST SHA256: refuse a download whose hash differs, since HTTPS does not prove it is the reviewed file.
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

# key_ok FILE FINGERPRINT: `rpm --import` trusts every key in a file, so check every primary key's fingerprint.
key_ok() {
    local fprs
    fprs=$(gpg --show-keys --with-colons "$1" 2>/dev/null \
        | awk -F: '$1 == "pub" { p = 1; next } p && $1 == "fpr" { print $10; p = 0 }')
    [ -n "$fprs" ] && [ "$fprs" = "$2" ]
}

# pin_clone URL COMMIT DEST: check out one reviewed commit; the final rev-parse is what makes it a real pin.
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

# Baseline: encryption and btrfs cannot be added later, so only report what is missing.

# is_encrypted MOUNTPOINT: true if it is mounted from a dm-crypt (LUKS) volume
is_encrypted() {
    local src type
    src=$(findmnt -fno SOURCE "$1" 2>/dev/null) || return 1
    [ -n "$src" ] || return 1
    src=${src%%[*}   # btrfs reports the source as /dev/x[/subvol]
    type=$(lsblk -no TYPE "$src" 2>/dev/null | head -1)
    [ "$type" = crypt ]
}

baseline_note() {
    local missing=0
    # -f (first only): a path can have several mount entries, which would break the tests
    if [ "$(findmnt -fno FSTYPE / 2>/dev/null)" != btrfs ]; then
        warn "/ is not btrfs, so there will be no snapshots (cannot be converted later)"
        missing=1
    fi
    # Judge encryption by where your files are: an encrypted /home protects them even if / is not.
    if [ "$(findmnt -fno TARGET /home 2>/dev/null)" = /home ]; then
        if ! is_encrypted /home; then
            warn "/home is not encrypted, so your files can be read by anyone holding the drive"
            missing=1
        fi
    elif ! is_encrypted /; then
        # no separate /home, so / holds everything
        warn "The disk is not encrypted, so your files can be read by anyone holding the drive"
        missing=1
    fi
    if ! is_encrypted /; then
        log "  note: / is not encrypted. /etc (where NetworkManager keeps Wi-Fi keys) and"
        log "  /var/log stay readable, and the system can be modified by someone with the"
        log "  drive — weaker than full-disk encryption, but not nothing."
    fi
    if rpm -q gnome-shell >/dev/null 2>&1; then
        warn "gnome-shell is installed; Hypora will use its own session but GNOME stays on disk"
        missing=1
    fi
    [ "$missing" -eq 0 ] && log "Baseline looks right: btrfs, encrypted, no competing desktop"
    return 0
}
baseline_note

# Decide laptop or desktop once (`hypora-power is-laptop`, override with IS_LAPTOP), since a battery alone proves nothing.
if [ -n "${IS_LAPTOP:-}" ]; then
    machine_kind="forced by IS_LAPTOP=$IS_LAPTOP"
elif machine_kind=$("$REPO/bin/hypora-power" is-laptop 2>/dev/null); then
    IS_LAPTOP=yes
else
    IS_LAPTOP=no
fi
if [ "$IS_LAPTOP" = yes ]; then
    log "Laptop: $machine_kind — battery, backlight and charger handling will be set up"
else
    log "Desktop: $machine_kind — skipping battery, backlight and charger handling"
fi

# Stop the background dnf services first: they hold dnf's lock and every dnf command would wait forever.
for svc in dnf5daemon-server packagekit; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        log "Stopping $svc so it releases the dnf lock (D-Bus restarts it on demand)"
        sudo timeout 60 systemctl stop "$svc" \
            || warn "Could not stop $svc; dnf steps may stall waiting for its lock"
    fi
done

log "Preparing repositories"
sudo dnf install -y dnf-plugins-core

# Fedora ships no Hyprland or uwsm; the sdegler/hyprland COPR does and tracks current releases.
sudo dnf copr disable -y solopasha/hyprland >/dev/null 2>&1 || true
# `copr enable` trusts the first key offered, so check it against a recorded fingerprint before installing.
HYPRLAND_COPR_FPR=64BBBF013D1CA5E4BE5B0552C043104207862204
log "Enabling COPR sdegler/hyprland"
sudo dnf copr enable -y sdegler/hyprland
copr_key=$(mktemp)
if curl -fsSL "https://download.copr.fedorainfracloud.org/results/sdegler/hyprland/pubkey.gpg" -o "$copr_key" \
    && key_ok "$copr_key" "$HYPRLAND_COPR_FPR"; then
    sudo rpm --import "$copr_key"
    # Point the repo at the verified key, or dnf would refetch one from the network and accept any key later.
    sudo install -m644 "$copr_key" /etc/pki/rpm-gpg/RPM-GPG-KEY-hypora-hyprland
    copr_pinned=0
    for repo in /etc/yum.repos.d/_copr*sdegler*hyprland*.repo; do
        [ -f "$repo" ] || continue
        sudo sed -i 's|^gpgkey=.*|gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-hypora-hyprland|' "$repo" \
            && copr_pinned=1
    done
    [ "$copr_pinned" -eq 1 ] || warn "Could not pin the Hyprland COPR key; dnf may fetch it again"
    log "Hyprland COPR signing key verified and pinned"
else
    rm -f "$copr_key"
    sudo dnf copr disable -y sdegler/hyprland >/dev/null 2>&1 || true
    die "The Hyprland COPR signing key did not match the expected fingerprint. Stopping."
fi
rm -f "$copr_key"
available quickshell || die "quickshell not found in enabled repos (it ships in Fedora 42+)."

# Extras (virtualization, network tools) are asked about, not default; INSTALL_EXTRAS=yes|no answers ahead.
want_extras() {
    case "${INSTALL_EXTRAS:-}" in
        yes|y|1) return 0 ;;
        no|n|0)  return 1 ;;
    esac
    rpm -q libvirt-daemon >/dev/null 2>&1 && return 0
    if [ ! -t 0 ]; then
        log "Skipping virtualization and network tools (no terminal to ask; set INSTALL_EXTRAS=yes)"
        return 1
    fi
    printf '\n%s\n%s\n' \
        "Optional: virtualization (libvirt, QEMU, virt-manager) and network tools (nmap," \
        "aircrack-ng, wireshark). Adds you to the libvirt and wireshark groups." >&2
    read -r -p "Install them? [y/N] " answer
    case "$answer" in [Yy]*) return 0 ;; *) return 1 ;; esac
}
if want_extras; then EXTRAS=yes; else EXTRAS=no; fi

# Bundled apps past the core desktop are asked about; INSTALL_APPS answers ahead, and no terminal means yes.
want_apps() {
    case "${INSTALL_APPS:-}" in
        yes|y|1) return 0 ;;
        no|n|0)  return 1 ;;
    esac
    [ -t 0 ] || return 0
    printf '\n%s\n%s\n' \
        "Optional: extra apps (Bitwarden, LocalSend, RustDesk, Lutris, Spotify, Flatseal," \
        "Warehouse). The core desktop, including a browser, is installed either way." >&2
    read -r -p "Install them? [Y/n] " answer
    case "$answer" in [Nn]*) return 1 ;; *) return 0 ;; esac
}
if want_apps; then APPS=yes; else APPS=no; fi

# ---------- packages ----------
REQUIRED=(
    hyprland hyprland-guiutils hyprlock hypridle hyprsunset uwsm quickshell kitty git
    # Shell and editor
    zsh zsh-autosuggestions zsh-syntax-highlighting fastfetch
    neovim ripgrep fd-find
    eza   # ls replacement used by the shell aliases
    polkit sddm qt6-qtsvg gnupg2 curl tar xz unzip firewalld
    # Secret Service (keyring): without it apps store tokens unencrypted; pam and gcr handle login unlock and prompts.
    gnome-keyring gnome-keyring-pam gcr
    # Fonts, icons and app theming (the Nerd Font is downloaded below)
    liberation-sans-fonts liberation-serif-fonts adwaita-icon-theme
    papirus-icon-theme breeze-icon-theme
    adw-gtk3-theme qt6ct qt5ct
    qt6-qtimageformats   # lets Qt show webp wallpapers
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-user-dirs xdg-utils
    xdg-terminal-exec   # starts Terminal=true apps with kitty (GIO does not know kitty)
    # Network (nmtui is the fallback behind the Network window's "Advanced")
    NetworkManager NetworkManager-tui NetworkManager-wifi
    # Sound: PipeWire, WirePlumber, wiremix (sound TUI), pulseaudio compatibility
    pipewire wireplumber pipewire-pulseaudio wiremix
    bluez   # also provides bluetoothctl, the fallback behind "Advanced"
    upower  # battery status
    # Smart cards: pcscd, the CCID reader driver, and OpenSC for PIV/CAC/PKCS#11 tokens
    pcsc-lite pcsc-lite-ccid opensc
    nss-tools   # certutil/modutil, used by hypora-smartcard to set up the browsers
    yubikey-manager fido2-tools   # ykman for YubiKeys, fido2-token for any FIDO2 key
    # Read the machine's security state for the Security window
    fwupd mokutil policycoreutils
    # Baseline desktop apps, listed so they are user-installed and `dnf autoremove` leaves them alone.
    nautilus gvfs gnome-calculator gnome-disk-utility gnome-software
    gnome-calendar baobab simple-scan
    papers            # PDF and document viewer
    loupe             # image viewer
    gnome-text-editor
    mpv               # video and audio player
    cliphist wl-clipboard grim slurp
)
# Nice to have; a missing one only gives a warning
OPTIONAL=(
    iw   # Wi-Fi power save
    pamixer playerctl
    google-noto-emoji-fonts
    # Boot screen, including the disk passphrase prompt (usually already installed)
    plymouth plymouth-plugin-two-step plymouth-scripts
)
# Only installed if you opt in (see want_extras)
EXTRAS_PKGS=(nmap aircrack-ng wireshark wireshark-cli)

log "Installing required packages"
sudo dnf install -y "${REQUIRED[@]}"

# Mark these user-installed so autoremove cannot take gnome-keyring-pam and gcr and break keyring unlock.
PROTECT_USER=(
    gsettings-desktop-schemas xorg-x11-server-Xwayland
    gnome-keyring gnome-keyring-pam gcr
    nautilus gvfs gnome-calculator gnome-disk-utility gnome-software
    gnome-software gnome-calendar baobab simple-scan papers evince
    loupe gnome-text-editor
    pcsc-lite pcsc-lite-ccid opensc
)
# Check with rpm first (fast) so a missing package cannot fail the whole dnf call.
protect_now=()
for p in "${PROTECT_USER[@]}"; do
    rpm -q "$p" >/dev/null 2>&1 && protect_now+=("$p")
done
if [ ${#protect_now[@]} -gt 0 ]; then
    log "Protecting ${#protect_now[@]} required packages from dnf autoremove"
    # One dnf call with a timeout (it waits forever on a held lock); -C skips metadata, with a second try without it.
    if ! sudo timeout 45 dnf -C -y mark user "${protect_now[@]}" >/dev/null 2>&1 \
       && ! sudo timeout 90 dnf -y mark user "${protect_now[@]}" >/dev/null 2>&1; then
        warn "Could not mark packages user-installed (dnf was busy or locked), so a later"
        warn "  'dnf autoremove' may remove them. Run this when nothing else is using dnf:"
        warn "    sudo dnf mark user ${protect_now[*]}"
    fi
fi

if [ "$EXTRAS" = yes ]; then
    log "Installing virtualization (@virtualization group)"
    # Without virt-viewer: its remote-viewer duplicates RustDesk and virt-manager has its own console.
    sudo dnf group install -y virtualization --exclude=virt-viewer \
        || warn "Could not install the virtualization group"
    sudo dnf install -y --skip-unavailable "${EXTRAS_PKGS[@]}" \
        || warn "Some network tools could not be installed"
fi
# Remove virt-viewer if an earlier install added it (nothing depends on it)
if rpm -q virt-viewer >/dev/null 2>&1; then
    log "Removing virt-viewer (remote-viewer); RustDesk replaces it"
    sudo dnf remove -y virt-viewer || warn "Could not remove virt-viewer"
fi

# An earlier version installed RustDesk's unsigned RPM. The Flathub build replaces it.
if rpm -q rustdesk >/dev/null 2>&1; then
    log "Removing the RustDesk RPM (the verified Flathub build replaces it)"
    sudo dnf remove -y rustdesk || warn "Could not remove the RustDesk RPM"
fi

# GNOME Help documents a shell that is not running; hypora-replace-de removes it only while a desktop is detected.
if rpm -q yelp >/dev/null 2>&1; then
    log "Removing GNOME Help (yelp)"
    sudo dnf remove -y yelp || warn "Could not remove yelp"
fi


log "Installing optional packages"
# One transaction, and --skip-unavailable skips names this Fedora release lacks.
sudo dnf install -y --skip-unavailable "${OPTIONAL[@]}" \
    || warn "Some optional packages could not be installed"
# `install` leaves an already-installed (possibly old) Hyprland as it is
sudo dnf upgrade -y hyprland uwsm || true

# Laptop-only packages: brightnessctl needs a backlight, and upower stays required for wireless peripherals' batteries.
if [ "$IS_LAPTOP" = yes ] && available brightnessctl; then
    sudo dnf install -y brightnessctl || warn "Skipped brightnessctl (brightness keys will not work)"
fi

# Fedora defaults to tuned-ppd (same D-Bus API); keep power-profiles-daemon if installed since the two conflict.
if ! rpm -q power-profiles-daemon >/dev/null 2>&1; then
    sudo dnf install -y tuned-ppd || warn "Could not install tuned-ppd (power modes unavailable)"
fi

# Remove old impala and bluetui binaries; the Network and Bluetooth windows replace them.
sudo rm -f /usr/local/bin/impala /usr/local/bin/bluetui

# Hyprland reads hyprland.lua only from 0.55; `|| true` because grep exits 1 on no match and pipefail would end the script.
hypr_ver=$(Hyprland --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
if [ -n "$hypr_ver" ] && [ "$(printf '%s\n' 0.55.0 "$hypr_ver" | sort -V | head -1)" != 0.55.0 ]; then
    die "Hyprland $hypr_ver is too old for hyprland.lua (need 0.55+). Run: sudo dnf upgrade --refresh hyprland"
fi

# Snapshots use snapper, not Timeshift, which needs an `@` subvolume Fedora lacks; unattended updates get one via a drop-in.
has_btrfs() {
    findmnt -nt btrfs >/dev/null 2>&1 && return 0
    lsblk -no FSTYPE 2>/dev/null | grep -qx btrfs
}

# kv_set FILE KEY VALUE: set KEY="VALUE" in a shell-style config, adding the line if missing.
kv_set() {
    local f=$1 key=$2 val=$3
    [ -f "$f" ] || return 0
    if sudo grep -q "^${key}=" "$f"; then
        sudo sed -i "s|^${key}=.*|${key}=\"${val}\"|" "$f"
    else
        printf '%s="%s"\n' "$key" "$val" | sudo tee -a "$f" >/dev/null
    fi
}

snapper_set() { kv_set "/etc/snapper/configs/$1" "$2" "$3"; }

# snapper_setup NAME PATH: create a config, then lower the retention (default is too much for a laptop disk).
snapper_setup() {
    local name=$1 path=$2
    if [ -f "/etc/snapper/configs/$name" ]; then
        log "  snapper config '$name' already exists, leaving it alone"
    elif sudo snapper -c "$name" create-config "$path"; then
        log "  snapper config '$name' created for $path"
    else
        warn "Could not create a snapper config for $path"
        return 1
    fi
    snapper_set "$name" TIMELINE_CREATE yes
    snapper_set "$name" TIMELINE_LIMIT_HOURLY 5
    snapper_set "$name" TIMELINE_LIMIT_DAILY 7
    snapper_set "$name" TIMELINE_LIMIT_WEEKLY 4
    snapper_set "$name" TIMELINE_LIMIT_MONTHLY 2
    snapper_set "$name" TIMELINE_LIMIT_YEARLY 0
    snapper_set "$name" NUMBER_LIMIT 10
    snapper_set "$name" NUMBER_LIMIT_IMPORTANT 5
}

if ! has_btrfs; then
    log "No btrfs filesystem, so snapshots were not set up"
elif ! available snapper; then
    warn "No snapper package for this Fedora release, so snapshots were not set up"
else
    log "Installing snapper (btrfs filesystem found)"
    if ! sudo dnf install -y snapper; then
        warn "Could not install snapper"
    else
        snapper_any=0
        # / first, since an update is what can break it
        if [ "$(findmnt -fno FSTYPE / 2>/dev/null)" = btrfs ]; then
            snapper_setup root / && snapper_any=1
        else
            log "  / is not btrfs, so there is no config for it"
        fi
        # /home separately (usually its own subvolume): it holds your own files
        if [ "$(findmnt -fno FSTYPE /home 2>/dev/null)" = btrfs ] \
           && [ "$(findmnt -fno TARGET /home 2>/dev/null)" = /home ]; then
            snapper_setup home /home && snapper_any=1
        fi

        if [ "$snapper_any" -eq 1 ]; then
            sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer \
                2>/dev/null || warn "Could not enable the snapper timers"
            log "  timeline and cleanup timers enabled"
        else
            warn "snapper is installed but no config could be created, so nothing is snapshotted"
        fi

        # snapper has no GUI of its own; btrfs-assistant is one for browsing snapshots
        if available btrfs-assistant; then
            sudo dnf install -y btrfs-assistant \
                || warn "Could not install btrfs-assistant (snapshots stay command-line only)"
        else
            warn "No btrfs-assistant package; snapshots are command-line only"
        fi
    fi
fi

# btrfs housekeeping: scrub finds bit rot and balance frees mostly-empty chunks; trim and defrag are left off.
if has_btrfs && available btrfsmaintenance; then
    log "Setting up btrfs scrub and balance"
    if sudo dnf install -y btrfsmaintenance; then
        for cfg in /etc/sysconfig/btrfsmaintenance /etc/default/btrfsmaintenance; do
            [ -f "$cfg" ] || continue
            kv_set "$cfg" BTRFS_SCRUB_PERIOD monthly
            kv_set "$cfg" BTRFS_BALANCE_PERIOD monthly
            kv_set "$cfg" BTRFS_TRIM_PERIOD none
            kv_set "$cfg" BTRFS_DEFRAG_PERIOD none
        done
        # The package's refresh unit reads that config and enables the matching timers
        if systemctl cat btrfsmaintenance-refresh.service >/dev/null 2>&1; then
            # `start`, not `enable`: this unit has no [Install] section
            sudo systemctl start btrfsmaintenance-refresh.service \
                || warn "Could not apply the btrfsmaintenance schedule"
            # The .path unit re-runs the refresh when the config file changes
            sudo systemctl enable --now btrfsmaintenance-refresh.path 2>/dev/null \
                || warn "btrfsmaintenance timers won't refresh if you edit its config later"
        else
            for t in btrfs-scrub btrfs-balance; do
                systemctl cat "$t.timer" >/dev/null 2>&1 \
                    && sudo systemctl enable --now "$t.timer" 2>/dev/null \
                    || true
            done
        fi
    else
        warn "Could not install btrfsmaintenance (no scheduled scrub or balance)"
    fi
fi

# JetBrainsMono Nerd Font is not packaged for Fedora; install it system-wide so the sddm login screen can use it.
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

# Gruvbox Plus icons (GPL-3.0) are not packaged for Fedora, so use the release zip
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


# Flatpak: Flathub is added as a system remote, installed apps are skipped, SKIP_FLATPAKS=1 installs none.
log "Setting up Flatpak"
sudo dnf install -y flatpak
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
    || warn "Could not add the Flathub remote"

# Apps handling untrusted input (the browser) are sandboxed flatpaks; the rest are native.
FLATPAKS=(
    org.mozilla.firefox              # publisher-verified by Mozilla
)
# Bundled apps, installed only when want_apps said yes
APP_FLATPAKS=(
    io.github.flattool.Warehouse     # manage installed flatpaks and their leftover data
    com.github.tchx84.Flatseal       # review and change each flatpak's permissions
    com.bitwarden.desktop
    com.yubico.yubioath              # Yubico Authenticator: one-time codes from a YubiKey
    org.localsend.localsend_app
    # Remote desktop from Flathub: publisher-verified, unlike the project's unsigned RPM.
    com.rustdesk.RustDesk
    # Steam is native (installed below) because the flatpak sandbox gets in the way of controllers and game libraries.
    net.lutris.Lutris
    com.spotify.Client               # sandboxed, rather than an unmaintained terminal client
)
if [ "${SKIP_FLATPAKS:-0}" = "1" ]; then
    log "Skipping Flatpak apps (SKIP_FLATPAKS=1)"
else
    log "Installing Flatpak apps (this pulls a few GB the first time)"
    [ "$APPS" = yes ] && FLATPAKS+=("${APP_FLATPAKS[@]}")
    for app in "${FLATPAKS[@]}"; do
        if flatpak info "$app" >/dev/null 2>&1; then
            log "  $app is already installed"
        else
            sudo flatpak install -y --noninteractive flathub "$app" \
                || warn "Could not install $app"
        fi
    done
fi

# Oh My Zsh: clone a pinned commit instead of running its installer; zshrc turns off auto-update so the pin holds.
if [ -d "$HOME/.oh-my-zsh" ]; then
    log "Oh My Zsh already installed"
else
    log "Installing Oh My Zsh"
    pin_clone https://github.com/ohmyzsh/ohmyzsh.git \
        60c9a7a839b790cd905d0fd4419435124fd1bdc0 \
        "$HOME/.oh-my-zsh" || warn "Could not install Oh My Zsh"
fi

# LazyVim starter, only if you have no Neovim config yet
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
sudo systemctl enable --now pcscd.socket || warn "Could not enable pcscd (smart card readers will not work)"
sudo systemctl enable --now bluetooth 2>/dev/null || warn "No bluetooth service (the Bluetooth tile will show Unavailable)"
if rpm -q tuned-ppd >/dev/null 2>&1; then
    sudo systemctl enable --now tuned tuned-ppd || warn "Could not enable tuned-ppd"
else
    sudo systemctl enable --now power-profiles-daemon || warn "Could not enable power-profiles-daemon"
fi

if [ "$EXTRAS" = yes ] && rpm -q libvirt-daemon >/dev/null 2>&1; then
    sudo systemctl enable --now libvirtd || warn "Could not enable libvirtd"
    sudo usermod -aG libvirt "$USER" || true
fi
# Capturing packets as a normal user needs the wireshark group
if [ "$EXTRAS" = yes ] && getent group wireshark >/dev/null; then
    sudo usermod -aG wireshark "$USER" || true
fi

# Put machines that an earlier version switched to iwd back on the default Wi-Fi backend.
IWD_CONF=/etc/NetworkManager/conf.d/hypora-iwd.conf
if [ -e "$IWD_CONF" ]; then
    log "Restoring NetworkManager's default Wi-Fi backend"
    sudo rm -f "$IWD_CONF"
    sudo systemctl disable iwd 2>/dev/null || true
    sudo systemctl enable wpa_supplicant 2>/dev/null || true
fi
# DNS through systemd-resolved and per-network MAC addresses (see the config files).
log "Setting up DNS and MAC address privacy"
sudo install -d /etc/systemd/resolved.conf.d /etc/NetworkManager/conf.d
sudo install -m644 "$REPO/system/systemd/resolved.conf.d/hypora-dns.conf" /etc/systemd/resolved.conf.d/hypora-dns.conf
sudo install -m644 "$REPO/system/NetworkManager/conf.d/hypora-dns.conf" /etc/NetworkManager/conf.d/hypora-dns.conf
sudo install -m644 "$REPO/system/NetworkManager/conf.d/hypora-mac.conf" /etc/NetworkManager/conf.d/hypora-mac.conf
sudo systemctl enable --now systemd-resolved || warn "Could not enable systemd-resolved"
# /etc/resolv.conf must point at resolved's stub, or apps skip resolved
if [ "$(readlink -f /etc/resolv.conf)" != /run/systemd/resolve/stub-resolv.conf ]; then
    sudo ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf \
        || warn "Could not point /etc/resolv.conf at systemd-resolved"
fi
# Restarting NetworkManager briefly drops the connection, so do it after the downloads
sudo systemctl try-restart systemd-resolved NetworkManager 2>/dev/null || true

# Firewall: close Fedora's wide default zone; LocalSend opens in `home` only, SSH closes unless KEEP_SSH=yes.
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
    # Close LocalSend's port in `public` if an earlier version opened it
    if sudo firewall-cmd --permanent --query-port=53317/tcp >/dev/null 2>&1; then
        log "Closing LocalSend's port 53317 in the public zone (see the LocalSend note in the readme)"
        sudo firewall-cmd --quiet --permanent --remove-port=53317/tcp || true
        sudo firewall-cmd --quiet --permanent --remove-port=53317/udp || true
    fi
    if [ "${LOCALSEND_LAN:-yes}" != no ]; then
        sudo firewall-cmd --quiet --permanent --zone=home --add-port=53317/tcp || true   # LocalSend
        sudo firewall-cmd --quiet --permanent --zone=home --add-port=53317/udp || true
        log "LocalSend's port is open in the home zone only. Put a trusted network in that zone with:"
        log "  nmcli connection modify <name> connection.zone home"
    fi
    sudo firewall-cmd --quiet --reload || true
fi

# Also stop sshd so a blocked port is not reopened by mistake; it stays installed (`systemctl enable --now sshd`).
if [ "$KEEP_SSH" != yes ]; then
    if systemctl is-enabled --quiet sshd 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
        log "Disabling the SSH server (KEEP_SSH=yes to keep it)"
        sudo systemctl disable --now sshd 2>/dev/null || warn "Could not disable sshd"
    fi
fi

# Automatic security updates: dnf5-automatic for advisories, our timer for flatpaks; enabled without --now (dnf lock).
log "Enabling automatic security updates"
sudo dnf install -y dnf5-plugin-automatic \
    || sudo dnf install -y dnf-automatic \
    || warn "Could not install dnf-automatic"
if command -v dnf-automatic >/dev/null 2>&1; then
    # dnf5's plugin and dnf4's dnf-automatic both read this file
    sudo install -d /etc/dnf
    sudo install -m644 "$REPO/system/dnf/automatic.conf" /etc/dnf/automatic.conf
    sudo systemctl enable dnf5-automatic.timer 2>/dev/null \
        || sudo systemctl enable dnf-automatic.timer 2>/dev/null \
        || warn "Could not enable the automatic update timer"

    # Snapshot before each unattended update via a drop-in; the `-` means a failed snapshot never blocks the update.
    if [ -f /etc/snapper/configs/root ]; then
        for unit in dnf5-automatic dnf-automatic; do
            if systemctl cat "$unit.service" >/dev/null 2>&1; then
                sudo install -d "/etc/systemd/system/$unit.service.d"
                sudo tee "/etc/systemd/system/$unit.service.d/10-hypora-snapshot.conf" \
                    >/dev/null <<'DROPIN'
# Added by Hypora: snapshot / before an unattended update; the `-` keeps a failed snapshot from cancelling it.
[Service]
ExecStartPre=-/usr/bin/snapper -c root create --type single \
    --cleanup-algorithm number --description "before automatic update"
DROPIN
                sudo systemctl daemon-reload
                log "  snapshotting / before each unattended update ($unit)"
                break
            fi
        done
    fi
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

# Fix hardware that did not come up; install the root-owned copy first, since the checkout is user-writable.
if [ -x "$REPO/bin/hypora-hardware" ]; then
    log "Checking hardware, firmware and drivers"
    sudo install -m755 -o root -g root "$REPO/bin/hypora-hardware" /usr/local/bin/hypora-hardware
    sudo /usr/local/bin/hypora-hardware fix || warn "Some hardware could not be fixed"
    "$REPO/bin/hypora-hardware" probe || true
fi

sudo systemctl set-default graphical.target

# Themes: install palettes and templates; bin/hypora-theme renders them near the end.
log "Installing themes"
for f in "$REPO"/themes/*/colors.toml; do
    put "$f" "$CONF/hypora/themes/$(basename "$(dirname "$f")")/colors.toml"
done
for f in "$REPO"/themes/templates/*.tpl; do
    put "$f" "$CONF/hypora/templates/$(basename "$f")"
done

# Older installs had a 'current' symlink here; the rendered theme is now in hypora/current/
if [ -L "$CONF/hypora/themes/current" ]; then rm "$CONF/hypora/themes/current"; fi

# Hyprland 0.55+ uses a Lua config (hyprland.lua).
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

# Quickshell: copy each file into ~/.config/quickshell (hypora-theme links in Theme.qml).
log "Installing Quickshell config"
mkdir -p "$CONF/quickshell"
# Older installs symlinked into the clone; delete links that no longer resolve
find "$CONF/quickshell" -maxdepth 1 -type l ! -exec test -e {} \; -delete
for f in "$REPO"/config/quickshell/*; do
    [ -f "$f" ] && put "$f" "$CONF/quickshell/$(basename "$f")"
done

# Login screen (SDDM): a minimal Hyprland session with a small QML theme coloured from the active Hypora theme.
log "Installing SDDM login screen"
SDDM_THEME=/usr/share/sddm/themes/hypora
sudo install -d "$SDDM_THEME" /etc/sddm.conf.d
sudo install -m644 "$REPO"/system/sddm/hypora/{Main.qml,metadata.desktop} "$SDDM_THEME/"
sudo install -m644 "$REPO/system/sddm/hyprland.lua" "$SDDM_THEME/hyprland.lua"
# theme.conf stays root-owned because the greeter reads it before login; hypora-theme uses sudo to update it.
sudo install -m644 -o root -g root "$REPO/system/sddm/hypora/theme.conf" "$SDDM_THEME/theme.conf"
# Fix the owner if an earlier version of this installer made it user-writable
sudo chown root:root "$SDDM_THEME/theme.conf"
sudo install -m644 "$REPO/system/sddm/10-hypora.conf" /etc/sddm.conf.d/10-hypora.conf

for dm in gdm lightdm greetd; do
    if systemctl is-enabled -q "$dm" 2>/dev/null; then
        sudo systemctl disable "$dm"
        warn "Disabled $dm (Hypora uses SDDM)"
    fi
done
sudo systemctl enable sddm

# Keyring unlock and fingerprint login both go through authselect, which edits PAM and survives updates.
enable_authselect_feature() {
    local feature=$1 what=$2
    if ! command -v authselect >/dev/null 2>&1; then
        warn "authselect is not installed, so $what was not enabled"
        return 1
    fi
    if ! authselect current >/dev/null 2>&1; then
        warn "No authselect profile is selected, so $what was not enabled"
        return 1
    fi
    if authselect current 2>/dev/null | grep -q -- "$feature"; then
        log "  $what already enabled"
        return 0
    fi
    if sudo authselect enable-feature "$feature" >/dev/null 2>&1; then
        log "  enabled $feature"
        return 0
    fi
    warn "Could not enable $feature, so $what was not set up"
    return 1
}

if [ "${KEYRING_AUTOUNLOCK:-yes}" = no ]; then
    log "Skipping keyring auto-unlock (KEYRING_AUTOUNLOCK=no)"
else
    log "Enabling keyring auto-unlock"
    enable_authselect_feature with-pam-gnome-keyring "keyring auto-unlock" || true
    # The `password` line must come before pam_unix's (`sufficient` stops PAM); resolve the system-auth symlink first.
    PAM_PW=$(readlink -f /etc/pam.d/system-auth)
    if [ -f "$PAM_PW" ] && ! awk '
            /^-?password[[:space:]].*pam_gnome_keyring\.so/ { k = NR }
            /^password[[:space:]]+sufficient[[:space:]]+pam_unix\.so/ && !u { u = NR }
            END { exit !(k && u && k < u) }' "$PAM_PW"; then
        if grep -Eq '^password[[:space:]]+sufficient[[:space:]]+pam_unix\.so' "$PAM_PW"; then
            sudo cp -aL "$PAM_PW" "/etc/pam.d/system-auth.hypora-$(date +%Y%m%d-%H%M%S)"
            sudo sed -i '/^-password[[:space:]].*pam_gnome_keyring\.so/d' "$PAM_PW"
            sudo sed -i '/^password[[:space:]]\+sufficient[[:space:]]\+pam_unix\.so/i -password   optional   pam_gnome_keyring.so use_authtok' "$PAM_PW"
            log "  placed the keyring re-key line in $PAM_PW"
        else
            warn "No pam_unix password line in $PAM_PW, so the keyring re-key line was not added"
        fi
    fi
fi

# Fingerprint login: check the hardware first, install fprintd only if it passes, then change PAM.
if ! "$REPO/bin/hypora-hardware" fingerprint --hardware >/dev/null 2>&1; then
    # No or unsupported reader, so skip fprintd; `|| true` because the command fails by design under pipefail.
    fp_why=$("$REPO/bin/hypora-hardware" fingerprint --hardware 2>&1 | tail -1 || true)
    case "$fp_why" in
        *unsupported*) log "Skipping fingerprint setup: $fp_why" ;;
    esac
else
    log "Fingerprint reader detected; installing fprintd to see whether it is supported"
    if sudo dnf install -y fprintd fprintd-pam; then
        if "$REPO/bin/hypora-hardware" fingerprint >/dev/null 2>&1; then
            enable_authselect_feature with-fingerprint "fingerprint login" \
                && log "  enrol a finger with: fprintd-enroll" \
                || warn "Could not enable fingerprint login"
        else
            warn "Your fingerprint reader has no libfprint driver, so enrolment cannot"
            warn "  work and fingerprint login was left off. Details:"
            warn "  $("$REPO/bin/hypora-hardware" fingerprint 2>&1 | tail -1 || true)"
        fi
    else
        warn "Could not install fprintd"
    fi
fi

# ---------- terminal and session environment ----------
log "Installing kitty, uwsm, zsh, fastfetch and Neovim settings"
put "$REPO/config/kitty/kitty.conf" "$CONF/kitty/kitty.conf"
put "$REPO/config/uwsm/env" "$CONF/uwsm/env"
put "$REPO/config/xdg-terminals.list" "$CONF/xdg-terminals.list"
put "$REPO/config/hypr/hypridle.conf" "$CONF/hypr/hypridle.conf"
put "$REPO/config/zsh/zshrc" "$HOME/.zshrc"
put "$REPO/config/fastfetch/config.jsonc" "$CONF/fastfetch/config.jsonc"
put "$REPO/config/fastfetch/hypora.txt" "$CONF/fastfetch/hypora.txt"
# Only this one file under ~/.config/nvim is ours; the rest is yours
[ -d "$CONF/nvim" ] && put "$REPO/config/nvim/lua/plugins/hypora.lua" "$CONF/nvim/lua/plugins/hypora.lua"

# zsh as the login shell
if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v zsh)" ]; then
    sudo chsh -s "$(command -v zsh)" "$USER" \
        && log "Login shell set to zsh (starts at your next login)" \
        || warn "Could not set zsh as your login shell; run: chsh -s $(command -v zsh)"
fi

# App entries so Hypora's windows (e.g. Display Settings) show up in the launcher.
log "Installing app entries"
for f in "$REPO"/applications/*.desktop; do
    [ -f "$f" ] && put "$f" "$HOME/.local/share/applications/$(basename "$f")"
done

# Root-run scripts go to root-owned /usr/local/bin, or anything that can write ~/.local/bin could get root.
ROOT_OWNED=(hypora-security hypora-console hypora-hardware hypora-grub hypora-power
            hypora-replace-de hypora-greeter)

for name in "${ROOT_OWNED[@]}"; do
    log "Installing $name to /usr/local/bin (root-owned)"
    sudo install -m755 -o root -g root "$REPO/bin/$name" "/usr/local/bin/$name"
    # Remove a user-writable copy left by an earlier version
    rm -f "$HOME/.local/bin/$name"
done

# Copy the main display into the theme dir for the greeter (it cannot read monitors.lua); run after the bin loop.
primary=""
if [ -f "$CONF/hypr/monitors.lua" ]; then
    primary=$(sed -nE 's/^HYPORA_PRIMARY[[:space:]]*=[[:space:]]*"([A-Za-z][A-Za-z0-9-]*)".*/\1/p' \
        "$CONF/hypr/monitors.lua" | head -1 || true)
fi
if [ -n "$primary" ] && [ -d /usr/share/sddm/themes/hypora ]; then
    log "Sending the login screen to $primary"
    sudo /usr/local/bin/hypora-greeter set "$primary" \
        || warn "Could not set the login screen's display; run: sudo hypora-greeter set $primary"
fi

shopt -s nullglob
bin_files=("$REPO"/bin/*)
if [ ${#bin_files[@]} -gt 0 ]; then
    log "Installing bin scripts to ~/.local/bin"
    for f in "${bin_files[@]}"; do
        # Files only: bin/* can also match a directory such as __pycache__
        [ -f "$f" ] || continue
        name=$(basename "$f")
        skip=
        for r in "${ROOT_OWNED[@]}"; do [ "$name" = "$r" ] && skip=1; done
        [ -n "$skip" ] && continue        # root-owned, installed above
        put "$f" "$HOME/.local/bin/$name" 755
    done
fi

# Smart cards and YubiKeys for the Flatpak browsers, which cannot see the host's OpenSC; runs after the Flatpak step.
"$REPO/bin/hypora-smartcard" setup || warn "Smart card setup failed; run: hypora-smartcard setup"

# Laptop power: nothing switches profiles on unplug under Hyprland, so hypora-power does it via udev.
if [ "$IS_LAPTOP" = yes ]; then
    log "Setting up laptop power management"
    sudo /usr/local/bin/hypora-power install \
        || warn "Could not set up automatic power switching"
fi

# Wallpapers come from themes/<Name>/backgrounds/; images you added yourself are left alone.
log "Installing wallpapers"
for f in "$REPO"/themes/*/backgrounds/*; do
    [ -f "$f" ] || continue
    theme=$(basename "$(dirname "$(dirname "$f")")")
    put "$f" "$CONF/hypora/themes/$theme/backgrounds/$(basename "$f")"
done

# Apply the theme: render the palette into Quickshell, kitty, Hyprland, hyprlock, GTK and Qt.
log "Applying theme: $THEME"
"$HOME/.local/bin/hypora-theme" "$THEME"

# Copy the root-owned login colours here where sudo is available, rather than hoping hypora-theme finds a terminal.
RENDERED_SDDM="$CONF/hypora/current/sddm-theme.conf"
if [ -f "$RENDERED_SDDM" ] && [ -d "$SDDM_THEME" ]; then
    sudo install -m644 -o root -g root "$RENDERED_SDDM" "$SDDM_THEME/theme.conf"
fi

# Boot screen with the passphrase prompt: the theme must be in the initramfs (`-R`), the slowest step.
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
    # Plymouth's unanchored grep breaks if ModuleName or ImageDir appears twice, so require exactly one of each.
    ply_dupes=0
    for key in ModuleName ImageDir; do
        n=$(grep -cE "${key} *= *" /usr/share/plymouth/themes/hypora/hypora.plymouth 2>/dev/null || true)
        n=${n:-0}
        if [ "$n" -ne 1 ]; then
            warn "hypora.plymouth has $n lines matching '$key'; Plymouth needs exactly one"
            ply_dupes=1
        fi
    done

    # Switch only when the passphrase field and bullet images exist, or an encrypted disk gets no visible prompt.
    if [ "$ply_dupes" -eq 0 ] \
       && [ -f /usr/share/plymouth/themes/hypora/entry.png ] \
       && [ -f /usr/share/plymouth/themes/hypora/bullet.png ]; then
        sudo plymouth-set-default-theme hypora -R \
            || warn "Could not set the boot theme; the previous one is still in place"
    else
        warn "Boot screen images are missing; leaving the existing boot theme alone"
    fi

    # Keep the splash up until the login screen draws over it, or the GRUB menu shows between the two.
    sudo install -d /etc/systemd/system/plymouth-quit.service.d
    sudo install -m644 \
        "$REPO/system/systemd/plymouth-quit.service.d/10-hypora-retain-splash.conf" \
        /etc/systemd/system/plymouth-quit.service.d/10-hypora-retain-splash.conf
    sudo systemctl daemon-reload
else
    warn "Plymouth is not installed; the boot screen stays as it is"
fi

# Boot menu: hypora-grub themes GRUB from the palette; skipped silently without GRUB (e.g. systemd-boot).
if [ -d /boot/grub2 ] || [ -d /boot/grub ]; then
    if command -v grub2-mkconfig >/dev/null 2>&1; then
        log "Theming the boot menu"
        sudo /usr/local/bin/hypora-grub apply \
            || warn "Could not theme the boot menu; GRUB is unchanged"
    else
        warn "grub2-mkconfig is missing, so the boot menu was left alone"
    fi
else
    log "No GRUB found, so the boot menu was left alone"
fi

# ---------- bookkeeping ----------
prune
mkdir -p "$(dirname "$MANIFEST")"
mv "$NEW_MANIFEST" "$MANIFEST"

# Another desktop is offered last; hypora-replace-de refuses while you run it, so rerun after rebooting into Hypora.
if "$REPO/bin/hypora-replace-de" list >/dev/null 2>&1; then
    printf '\n'
    "$REPO/bin/hypora-replace-de" list >&2
    printf '\n%s\n%s\n%s\n' \
        "Hypora can remove that desktop: its session, the packages it left lying around," \
        "and the orphaned libraries behind them. The applications and settings schemas" \
        "Hypora itself uses are kept — it is built on some of them and would break." >&2
    if [ -t 0 ] && [ "${REPLACE_DE:-}" != no ]; then
        read -r -p "Remove it now? [y/N] " answer
        case "$answer" in
            [Yy]*) sudo /usr/local/bin/hypora-replace-de remove \
                       || warn "Could not remove the other desktop" ;;
            *) log "Left it alone — run: sudo hypora-replace-de remove" ;;
        esac
    else
        log "Leaving it alone; run: sudo hypora-replace-de remove"
    fi
fi

# Optional repos: RPM Fusion (codecs, NVIDIA) is a separate trust decision, off unless ENABLE_RPMFUSION=yes.
want_rpmfusion() {
    case "${ENABLE_RPMFUSION:-}" in
        yes|y|1) return 0 ;;
        no|n|0)  return 1 ;;
    esac
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

if rpm -q rpmfusion-free-release >/dev/null 2>&1; then
    log "RPM Fusion already enabled"
elif want_rpmfusion; then
    log "Enabling RPM Fusion"
    rel=$(rpm -E %fedora)
    sudo dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$rel.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$rel.noarch.rpm" \
        || warn "Could not enable RPM Fusion"
else
    log "Skipping RPM Fusion"
fi

# Steam is native, not the flatpak, because the sandbox hurts controllers and libraries; it needs rpmfusion-nonfree.
if rpm -q steam >/dev/null 2>&1; then
    log "Steam already installed natively"
elif rpm -q rpmfusion-nonfree-release >/dev/null 2>&1 && available steam; then
    log "Installing Steam (native)"
    sudo dnf install -y steam || warn "Could not install Steam"
else
    warn "Steam not installed: it needs RPM Fusion nonfree, which is not enabled"
    warn "  Enable it and run: sudo dnf install steam"
    warn "  Or use the flatpak instead: flatpak install flathub com.valvesoftware.Steam"
fi

# Remove the old Steam flatpak once native Steam is there, never with --delete-data (the library can be hundreds of GB).
if flatpak info com.valvesoftware.Steam >/dev/null 2>&1; then
    if rpm -q steam >/dev/null 2>&1; then
        log "Removing the Steam flatpak (native Steam is installed)"
        sudo flatpak uninstall -y com.valvesoftware.Steam \
            || warn "Could not remove the Steam flatpak; you now have two Steams installed"
        warn "The flatpak's games are still at ~/.var/app/com.valvesoftware.Steam/.local/share/Steam"
        warn "  Add that as a library folder in native Steam (Settings > Storage) to reuse them,"
        warn "  or delete it once you are sure: rm -rf ~/.var/app/com.valvesoftware.Steam"
    else
        warn "Keeping the Steam flatpak: native Steam is not installed, so removing it"
        warn "  would leave you with no Steam at all"
    fi
fi

# AI tools (optional): Claude Code installs only on yes; INSTALL_CLAUDE answers ahead, and non-interactive runs skip it.
CLAUDE_KEY_FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE

# Claude Code can arrive via Anthropic's script or npm, so check all three locations before asking.
claude_installed() {
    rpm -q claude-code >/dev/null 2>&1 && return 0
    command -v claude >/dev/null 2>&1 && return 0
    [ -x "$HOME/.local/bin/claude" ]
}

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

if claude_installed; then
    log "Claude Code already installed"
elif want_claude; then
    log "Installing Claude Code"
    # Check the signing key against Anthropic's published fingerprint before rpm trusts it
    key=$(mktemp)
    if curl -fsSL https://downloads.claude.ai/keys/claude-code.asc -o "$key" \
        && key_ok "$key" "$CLAUDE_KEY_FPR"; then
        sudo rpm --import "$key"
        # The repo file points at this verified copy, not at a key URL (see the COPR above)
        sudo install -m644 "$key" /etc/pki/rpm-gpg/RPM-GPG-KEY-claude-code
        sudo install -m644 "$REPO/system/yum.repos.d/claude-code.repo" /etc/yum.repos.d/claude-code.repo
        sudo dnf install -y claude-code || warn "Could not install claude-code"
    else
        warn "Claude Code signing key missing or fingerprint mismatch; skipped Claude Code"
    fi
    rm -f "$key"
else
    log "Skipping Claude Code"
fi

# Done: print the logo in its two colours (truecolor if supported) from the same file as fastfetch.
banner() {
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

# Record the installed commit so you can tell whether the machine runs the code you just changed.
STAMP="$CONF/hypora/installed.version"
mkdir -p "$(dirname "$STAMP")"
{
    if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
        printf 'commit=%s\n' "$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
        # a dirty tree means the installed files match no commit
        [ -n "$(git -C "$REPO" status --porcelain 2>/dev/null)" ] \
            && printf 'tree=dirty\n' || printf 'tree=clean\n'
    else
        printf 'commit=not-a-git-checkout\ntree=unknown\n'
    fi
    printf 'source=%s\ndate=%s\n' "$REPO" "$(date -Is)"
} > "$STAMP"

banner

if [ ${#WARNINGS[@]} -eq 0 ]; then
    printf '\033[1;32m Hypora was installed successfully.\033[0m\n\n'
else
    printf '\033[1;32m Hypora was installed\033[0m, with \033[1;33m%d warning(s)\033[0m:\n\n' "${#WARNINGS[@]}"
    for w in "${WARNINGS[@]}"; do printf '   \033[1;33m!!\033[0m %s\n' "$w"; done
    printf '\n'
fi

printf ' Installed from %s (%s, %s).\n' \
    "$REPO" "$(sed -n 's/^commit=//p' "$STAMP")" "$(sed -n 's/^tree=//p' "$STAMP")"
printf ' Check later with: cat %s\n\n' "$STAMP"

cat <<'EOF'
 Reboot to finish. The Hypora login screen starts the Hyprland session.

   sudo reboot

 Group memberships and your new zsh shell also need that reboot to take effect.
 If the desktop does not come up, switch to a console with Ctrl+Alt+F2 and run:

   journalctl -b -u sddm      why the login screen failed
   qs                         QML errors from the shell
   hyprctl configerrors       problems in hyprland.lua
   hypora-hardware probe      hardware with no driver, firmware or radio
   hypora-smartcard status    smart card / YubiKey readers and browser setup

 Hyprland's own log is NOT in journalctl (it sets debug.enable_stdout_logs = 0):

   cat /run/user/$UID/hypr/*/hyprland.log

EOF
