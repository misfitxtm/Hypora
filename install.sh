#!/usr/bin/env bash
# Hypora installer. Run it as your normal user on a fresh Fedora install.
# It installs packages, the Hyprland (Lua) config, the Quickshell config, the theme and
# the SDDM login screen.
#
# It is safe to re-run. Config files are copied into place, so the clone can be moved or
# deleted afterwards. To update, pull the repo and run this again.
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

# ---------- helpers ----------
# Every copied file is recorded with its checksum. On a re-run this shows which files you
# edited (they are backed up first) and which can be replaced quietly.
MANIFEST="$CONF/hypora/installed.sha256"
NEW_MANIFEST=$(mktemp)
trap 'rm -f "$NEW_MANIFEST"' EXIT

# With `set -e`, a failing command ends the script silently. Print what happened and
# what to do, because the install is then only partly done.
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
    # A directory here (for example from a glob) would otherwise end the script with an
    # unhelpful message from sha256sum
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

# fetch_verified URL DEST SHA256: download a file and refuse it if the hash differs.
# HTTPS shows who answered, not that the file is the one we reviewed, so every download
# is pinned to a version and a hash. To upgrade, change both here.
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

# key_ok FILE FINGERPRINT: true if FILE holds exactly one key and it is the pinned one.
# `rpm --import` trusts every key in a file, so a server could add its own key after the
# real one. This checks the fingerprint of every primary key, not just the first.
key_ok() {
    local fprs
    fprs=$(gpg --show-keys --with-colons "$1" 2>/dev/null \
        | awk -F: '$1 == "pub" { p = 1; next } p && $1 == "fpr" { print $10; p = 0 }')
    [ -n "$fprs" ] && [ "$fprs" = "$2" ]
}

# pin_clone URL COMMIT DEST: check out one exact, reviewed commit.
# Oh My Zsh and the LazyVim starter run as you, so they are pinned like every other
# download. The final rev-parse is the real check: without it this would be an ordinary
# unpinned clone.
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

# ---------- baseline ----------
# Hypora is tested on a Fedora Everything netinstall with disk encryption and btrfs. None of
# it is required, so this only reports what is missing. Encryption and btrfs cannot be
# added later without reinstalling, so it is better to say so now.

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
    # Encryption is judged by where your files are: an encrypted /home protects them
    # even if / is not encrypted.
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

# ---------- machine type ----------
# Decide laptop or desktop once, so every laptop-only step agrees. `hypora-power is-laptop`
# reads the chassis type; "has a battery" is not enough, since a desktop with a UPS or a
# wireless mouse has one too. Set IS_LAPTOP=yes or no to override a wrong firmware answer.
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

# Stop the background dnf services first. They hold dnf's lock, and every dnf command
# below would then wait forever (once for over an hour). They are not enabled units,
# so D-Bus starts them again when needed. `timeout`: stopping one can take 5 minutes.
for svc in dnf5daemon-server packagekit; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        log "Stopping $svc so it releases the dnf lock (D-Bus restarts it on demand)"
        sudo timeout 60 systemctl stop "$svc" \
            || warn "Could not stop $svc; dnf steps may stall waiting for its lock"
    fi
done

log "Preparing repositories"
sudo dnf install -y dnf-plugins-core

# Fedora does not ship Hyprland or uwsm. The sdegler/hyprland COPR does, and tracks
# current releases (the older solopasha COPR stopped before Lua configs existed).
sudo dnf copr disable -y solopasha/hyprland >/dev/null 2>&1 || true
# `copr enable` trusts whatever key the server offers the first time, so check it against
# a fingerprint recorded here before anything is installed from the repo.
HYPRLAND_COPR_FPR=64BBBF013D1CA5E4BE5B0552C043104207862204
log "Enabling COPR sdegler/hyprland"
sudo dnf copr enable -y sdegler/hyprland
copr_key=$(mktemp)
if curl -fsSL "https://download.copr.fedorainfracloud.org/results/sdegler/hyprland/pubkey.gpg" -o "$copr_key" \
    && key_ok "$copr_key" "$HYPRLAND_COPR_FPR"; then
    sudo rpm --import "$copr_key"
    # Point the repo at this verified copy. Otherwise dnf would fetch the key from the
    # network again, and a later `dnf upgrade -y` would accept whatever key it was offered.
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

# ---------- optional extras ----------
# Virtualization and network-analysis tools are asked about, not installed by default
# (libvirt group membership is close to root). Set INSTALL_EXTRAS=yes or no to answer ahead
# of time. A machine that already has libvirt keeps it.
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

# ---------- packages ----------
REQUIRED=(
    hyprland hyprland-guiutils hyprlock hypridle uwsm quickshell kitty git
    # Shell and editor
    zsh zsh-autosuggestions zsh-syntax-highlighting fastfetch
    neovim ripgrep fd-find
    eza   # ls replacement used by the shell aliases
    polkit sddm qt6-qtsvg gnupg2 curl tar xz unzip firewalld
    # Secret Service (keyring). GNOME starts one and Hyprland does not; without it some
    # apps store tokens unencrypted on disk. hyprland.lua starts it. gnome-keyring-pam
    # provides pam_gnome_keyring.so (needed for keyring unlock at login), and gcr is the
    # password prompter.
    gnome-keyring gnome-keyring-pam gcr
    # Fonts, icons and app theming (the Nerd Font is downloaded below)
    liberation-sans-fonts liberation-serif-fonts adwaita-icon-theme
    papirus-icon-theme breeze-icon-theme
    adw-gtk3-theme qt6ct
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-user-dirs xdg-utils
    xdg-terminal-exec   # starts Terminal=true apps with kitty (GIO does not know kitty)
    # Network (nmtui is the fallback behind the Network window's "Advanced")
    NetworkManager NetworkManager-tui NetworkManager-wifi
    # Sound: PipeWire, WirePlumber, wiremix (sound TUI), pulseaudio compatibility
    pipewire wireplumber pipewire-pulseaudio wiremix
    bluez   # also provides bluetoothctl, the fallback behind "Advanced"
    upower  # battery status
    # Read the machine's security state for the Security window
    fwupd mokutil policycoreutils
    # Files, clipboard history and screenshots. These are GNOME apps without the GNOME
    # session. Nautilus brings `localsearch`, an indexer that reads your home directory.
    nautilus gvfs gnome-calculator gnome-disk-utility gnome-software
    # Also GNOME apps, kept because nothing else here replaces them. Listing them marks
    # them user-installed, so `dnf autoremove` leaves them alone.
    gnome-calendar baobab simple-scan
    cliphist wl-clipboard grim slurp
)
# Nice to have; a missing one only gives a warning
OPTIONAL=(
    hyprsunset
    iw   # Wi-Fi power save
    pamixer playerctl
    google-noto-emoji-fonts
    qt6-qtimageformats   # lets Qt show webp wallpapers
    # Boot screen, including the disk passphrase prompt (usually already installed)
    plymouth plymouth-plugin-two-step plymouth-scripts
)
# Only installed if you opt in (see want_extras)
EXTRAS_PKGS=(nmap aircrack-ng wireshark wireshark-cli)

log "Installing required packages"
sudo dnf install -y "${REQUIRED[@]}"

# Mark these packages user-installed so `dnf autoremove` cannot remove them. After the
# desktop that pulled them in is gone, autoremove would take gnome-keyring-pam and gcr
# and silently break keyring unlock. `dnf install` does not reliably change the reason.
PROTECT_USER=(
    gsettings-desktop-schemas xorg-x11-server-Xwayland
    gnome-keyring gnome-keyring-pam gcr
    nautilus gvfs gnome-calculator gnome-disk-utility gnome-software
    gnome-calendar baobab simple-scan papers evince
)
# Check with rpm first (fast), so a package that is not installed cannot make the whole
# dnf call fail
protect_now=()
for p in "${PROTECT_USER[@]}"; do
    rpm -q "$p" >/dev/null 2>&1 && protect_now+=("$p")
done
if [ ${#protect_now[@]} -gt 0 ]; then
    log "Protecting ${#protect_now[@]} required packages from dnf autoremove"
    # One dnf call (each start takes ~7 seconds), with a timeout, because dnf waits
    # forever if another process holds its lock. -C skips metadata, which is not needed
    # to change a package's reason; the second try runs without it.
    if ! sudo timeout 45 dnf -C -y mark user "${protect_now[@]}" >/dev/null 2>&1 \
       && ! sudo timeout 90 dnf -y mark user "${protect_now[@]}" >/dev/null 2>&1; then
        warn "Could not mark packages user-installed (dnf was busy or locked), so a later"
        warn "  'dnf autoremove' may remove them. Run this when nothing else is using dnf:"
        warn "    sudo dnf mark user ${protect_now[*]}"
    fi
fi

if [ "$EXTRAS" = yes ]; then
    log "Installing virtualization (@virtualization group)"
    # Without virt-viewer: its remote-viewer duplicates RustDesk, and virt-manager has its
    # own console for local VMs
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

# GNOME Help documents a shell that is not running. hypora-replace-de removes it too, but
# only while a desktop is still detected.
if rpm -q yelp >/dev/null 2>&1; then
    log "Removing GNOME Help (yelp)"
    sudo dnf remove -y yelp || warn "Could not remove yelp"
fi

# Document viewer. Fedora renamed Evince to Papers, so install whichever exists.
for viewer in papers evince; do
    if available "$viewer"; then
        sudo dnf install -y "$viewer" || warn "Could not install $viewer (document viewer)"
        break
    fi
done

log "Installing optional packages"
# One transaction (each dnf start costs seconds). --skip-unavailable skips names this
# Fedora release does not have instead of failing.
sudo dnf install -y --skip-unavailable "${OPTIONAL[@]}" \
    || warn "Some optional packages could not be installed"
# `install` leaves an already-installed (possibly old) Hyprland as it is
sudo dnf upgrade -y hyprland uwsm || true

# ---------- laptop-only packages ----------
# brightnessctl needs a backlight. upower stays in REQUIRED because it also reports the
# batteries of wireless mice and keyboards.
if [ "$IS_LAPTOP" = yes ] && available brightnessctl; then
    sudo dnf install -y brightnessctl || warn "Skipped brightnessctl (brightness keys will not work)"
fi

# Power modes: Fedora's default is tuned-ppd (same D-Bus API as power-profiles-daemon).
# Keep power-profiles-daemon if it is already installed; the two conflict.
if ! rpm -q power-profiles-daemon >/dev/null 2>&1; then
    sudo dnf install -y tuned-ppd || warn "Could not install tuned-ppd (power modes unavailable)"
fi

# Older installs downloaded impala and bluetui. The Network and Bluetooth windows replace
# them, so remove the old binaries.
sudo rm -f /usr/local/bin/impala /usr/local/bin/bluetui

# Hyprland only reads hyprland.lua from version 0.55; older versions ignore it.
# `|| true`: grep exits 1 when nothing matches, and with pipefail that would end the
# script. An empty answer is expected if Hyprland is missing.
hypr_ver=$(Hyprland --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
if [ -n "$hypr_ver" ] && [ "$(printf '%s\n' 0.55.0 "$hypr_ver" | sort -V | head -1)" != 0.55.0 ]; then
    die "Hyprland $hypr_ver is too old for hyprland.lua (need 0.55+). Run: sudo dnf upgrade --refresh hyprland"
fi

# ---------- snapshots (btrfs only) ----------
# Uses snapper, not Timeshift: Timeshift's btrfs mode needs a subvolume named `@`, which
# Fedora does not create. dnf5 has no snapper plugin, so snapshots before a manual
# `dnf upgrade` are yours to take; unattended updates get one from a drop-in further down.
has_btrfs() {
    findmnt -nt btrfs >/dev/null 2>&1 && return 0
    lsblk -no FSTYPE 2>/dev/null | grep -qx btrfs
}

# kv_set FILE KEY VALUE: set KEY="VALUE" in a shell-style config file, adding the line
# if it is missing
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

# snapper_setup NAME PATH: create a snapper config, then lower the default retention
# (10 hourly, monthly and yearly snapshots is too much for a laptop disk)
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

# ---------- btrfs housekeeping ----------
# Fedora runs neither of these, and btrfs needs them:
#   scrub    reads every block and checks its checksum, which finds bit rot
#   balance  frees chunks that are allocated but mostly empty ("no space left" errors)
# Left off: trim (fstrim.timer already does it) and defrag (it unshares snapshot data and
# can use much more disk).
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

# ---------- fonts ----------
# JetBrainsMono Nerd Font is not packaged for Fedora. It is installed system-wide so the
# login screen (which runs as the sddm user) can use it too.
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


# ---------- Flatpak ----------
# Flathub is added as a system remote. Apps already installed are skipped.
# Set SKIP_FLATPAKS=1 to install none.
log "Setting up Flatpak"
sudo dnf install -y flatpak
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
    || warn "Could not add the Flathub remote"

# Apps that handle untrusted input (the browser) are flatpaks, because they are sandboxed.
# Everything else is a native package, since sandboxing an app that needs host access just
# hands it the host.
FLATPAKS=(
    io.github.flattool.Warehouse     # manage installed flatpaks and their leftover data
    com.github.tchx84.Flatseal       # review and change each flatpak's permissions
    org.mozilla.firefox              # publisher-verified by Mozilla
    com.bitwarden.desktop
    org.localsend.localsend_app
    # Remote desktop. The Flathub build is publisher-verified; the project's own RPM is
    # unsigned, so a pinned hash would not show who built it.
    com.rustdesk.RustDesk
    # Steam is native (installed further down): the flatpak sandbox gets in the way of
    # controllers and existing game libraries.
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
# Oh My Zsh. Its installer script is not run: it would only clone the repo, and Hypora
# writes its own .zshrc and sets the login shell itself. The clone is pinned to a commit
# (update it on purpose after reading the changes). config/zsh/zshrc turns off Oh My
# Zsh's auto-update, which would defeat the pin.
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

# An earlier version switched NetworkManager to iwd for impala, which is gone. Put such a
# machine back on the default Wi-Fi backend.
IWD_CONF=/etc/NetworkManager/conf.d/hypora-iwd.conf
if [ -e "$IWD_CONF" ]; then
    log "Restoring NetworkManager's default Wi-Fi backend"
    sudo rm -f "$IWD_CONF"
    sudo systemctl disable iwd 2>/dev/null || true
    sudo systemctl enable wpa_supplicant 2>/dev/null || true
fi
# DNS through systemd-resolved, and MAC addresses that change per network (the config
# files explain the details)
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

# Firewall. Fedora's FedoraWorkstation zone opens ports 1025-65535; the `public` zone only
# allows ssh, mDNS and DHCPv6. LocalSend is the one app here that listens, so its port is
# opened in the `home` zone only, which holds no network until you assign one. It is never
# opened in `public`. Set LOCALSEND_LAN=no to skip it. SSH is closed too (set
# KEEP_SSH=yes to keep it), but never when this installer itself runs over SSH, which
# would lock you out.
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

# Also stop the SSH daemon (a port that is blocked can be opened again later by mistake).
# It stays installed: `sudo systemctl enable --now sshd` turns it back on.
if [ "$KEEP_SSH" != yes ]; then
    if systemctl is-enabled --quiet sshd 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
        log "Disabling the SSH server (KEEP_SSH=yes to keep it)"
        sudo systemctl disable --now sshd 2>/dev/null || warn "Could not disable sshd"
    fi
fi

# Automatic security updates, in two parts. dnf5-automatic installs Fedora security
# advisories only, so the Hyprland COPR is never updated behind your back. A timer of our
# own updates flatpaks, which dnf cannot see (including the browser). The timers are
# enabled without --now: they would start an update at once and fight the installer for the
# dnf lock. They start after the reboot at the end.
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

    # Take a snapshot before each unattended update, if / has a snapper config. A drop-in
    # on the update service is the only place to hook this (dnf5 has no snapper plugin).
    # The `-` before the command means a failed snapshot never blocks the update.
    if [ -f /etc/snapper/configs/root ]; then
        for unit in dnf5-automatic dnf-automatic; do
            if systemctl cat "$unit.service" >/dev/null 2>&1; then
                sudo install -d "/etc/systemd/system/$unit.service.d"
                sudo tee "/etc/systemd/system/$unit.service.d/10-hypora-snapshot.conf" \
                    >/dev/null <<'DROPIN'
# Added by Hypora: snapshot / before an unattended update, so a bad update can be undone.
# The `-` means a failed snapshot does not cancel the update.
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

# Hardware that did not come up (for example no Wi-Fi after install): hypora-hardware
# finds out whether firmware is missing, a driver is unbound or a radio is blocked, and
# fixes what Fedora's own repos can. It runs from $REPO on purpose: ~/.local/bin is
# writable by you (so not safe to run with sudo) and does not exist yet on a fresh install.
if [ -x "$REPO/bin/hypora-hardware" ]; then
    log "Checking hardware, firmware and drivers"
    sudo "$REPO/bin/hypora-hardware" fix || warn "Some hardware could not be fixed"
    "$REPO/bin/hypora-hardware" probe || true
fi

sudo systemctl set-default graphical.target

# ---------- themes ----------
# Install palettes and templates. bin/hypora-theme renders them (run near the end).
log "Installing themes"
for f in "$REPO"/themes/*/colors.toml; do
    put "$f" "$CONF/hypora/themes/$(basename "$(dirname "$f")")/colors.toml"
done
for f in "$REPO"/themes/templates/*.tpl; do
    put "$f" "$CONF/hypora/templates/$(basename "$f")"
done

# Older installs had a 'current' symlink here; the rendered theme is now in hypora/current/
if [ -L "$CONF/hypora/themes/current" ]; then rm "$CONF/hypora/themes/current"; fi

# ---------- Hyprland ----------
# Hyprland 0.55+ uses a Lua config (hyprland.lua)
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
# Copy each file into ~/.config/quickshell. (hypora-theme links in Theme.qml.)
log "Installing Quickshell config"
mkdir -p "$CONF/quickshell"
# Older installs symlinked into the clone; delete links that no longer resolve
find "$CONF/quickshell" -maxdepth 1 -type l ! -exec test -e {} \; -delete
for f in "$REPO"/config/quickshell/*; do
    [ -f "$f" ] && put "$f" "$CONF/quickshell/$(basename "$f")"
done

# ---------- login screen (SDDM) ----------
# SDDM runs a minimal Hyprland session with a small QML theme. The theme colours come from
# the active Hypora theme.
log "Installing SDDM login screen"
SDDM_THEME=/usr/share/sddm/themes/hypora
sudo install -d "$SDDM_THEME" /etc/sddm.conf.d
sudo install -m644 "$REPO"/system/sddm/hypora/{Main.qml,metadata.desktop} "$SDDM_THEME/"
sudo install -m644 "$REPO/system/sddm/hyprland.lua" "$SDDM_THEME/hyprland.lua"
# theme.conf (the colours) stays owned by root: the greeter reads it before login, so
# a file you can write would let an unprivileged process change what the greeter reads.
# hypora-theme asks for sudo to update it later.
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

# Keyring unlock at login, and fingerprint login. Both use authselect, Fedora's tool for
# changing PAM. It has features for both, writes them into system-auth and password-auth
# (which sddm uses), and keeps them across updates. Its keyring feature has no `password`
# line, so one is added below.
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
    # The `password` line re-keys the keyring when you change your password. It must come
    # BEFORE the pam_unix password line: that line is `sufficient`, so after a successful
    # change PAM stops there and a later line never runs. system-auth is a symlink into
    # /etc/authselect, so resolve it first (`cp -a` would back up only the symlink).
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

# Fingerprint login. A reader being present does not mean libfprint supports it (it has
# no driver for the Synaptics readers in many ThinkPads). So check the hardware first
# (without fprintd), install fprintd only if that passes, then ask fprintd whether it can
# really drive the reader. Only then is PAM changed.
if ! "$REPO/bin/hypora-hardware" fingerprint --hardware >/dev/null 2>&1; then
    # No reader, or an unsupported one. fprintd is not installed: it could never work.
    # `|| true`: the command fails by design and pipefail would end the script.
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

# ---------- app entries ----------
# These make Hypora's windows (for example "Display Settings") show up in the launcher
log "Installing app entries"
for f in "$REPO"/applications/*.desktop; do
    [ -f "$f" ] && put "$f" "$HOME/.local/share/applications/$(basename "$f")"
done

# ---------- bin ----------
# Scripts that run as root go to /usr/local/bin, which only root can write. If they lived
# in ~/.local/bin, anything that can write your home directory could get root the next
# time you ran them. The user-writable copies are removed. A script is on this list if
# anything tells you to run it with sudo or pkexec:
#   hypora-security    run by pkexec from the Security window
#   hypora-console     writes the kernel command line
#   hypora-hardware    installs packages and loads kernel modules
#   hypora-grub        writes /etc/default/grub and regenerates grub.cfg
#   hypora-power       writes a udev rule that runs as root
#   hypora-replace-de  removes packages
#   hypora-greeter     writes a Lua file the login screen loads before anyone logs in
ROOT_OWNED=(hypora-security hypora-console hypora-hardware hypora-grub hypora-power
            hypora-replace-de hypora-greeter)

for name in "${ROOT_OWNED[@]}"; do
    log "Installing $name to /usr/local/bin (root-owned)"
    sudo install -m755 -o root -g root "$REPO/bin/$name" "/usr/local/bin/$name"
    # Remove a user-writable copy left by an earlier version
    rm -f "$HOME/.local/bin/$name"
done

# Tell the login screen which monitor is your main one. Display Settings saves it in
# ~/.config/hypr/monitors.lua, which the greeter (running as the sddm user) cannot read,
# so it is copied into the theme directory. This must run after the loop above, because
# it needs /usr/local/bin/hypora-greeter. It checks the file exists first: a fresh install
# has no monitors.lua, and the failing sed would end the script.
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

# ---------- laptop power ----------
# Laptops only. Nothing switches the power profile when the charger is unplugged on a
# Hyprland session (GNOME does it inside its shell), and tuned leaves PCIe ASPM, USB
# autosuspend and PCI power management alone. hypora-power does both, using a udev rule.
if [ "$IS_LAPTOP" = yes ]; then
    log "Setting up laptop power management"
    sudo /usr/local/bin/hypora-power install \
        || warn "Could not set up automatic power switching"
fi

# ---------- wallpapers ----------
# Each theme's images come from themes/<Name>/backgrounds/. Images you add yourself to
# ~/.config/hypora/themes/<Name>/backgrounds/ are left alone.
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

# The login screen colours are in a root-owned file. Copy them here, where sudo is
# available, instead of relying on hypora-theme finding a terminal to ask.
RENDERED_SDDM="$CONF/hypora/current/sddm-theme.conf"
if [ -f "$RENDERED_SDDM" ] && [ -d "$SDDM_THEME" ]; then
    sudo install -m644 -o root -g root "$RENDERED_SDDM" "$SDDM_THEME/theme.conf"
fi

# Boot screen, including the disk passphrase prompt. It needs a Plymouth theme, and the
# theme must be inside the initramfs, which `-R` rebuilds. That is the slowest step here
# and the reason hypora-theme does not do it on every theme change.
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
    # Plymouth's tools read ModuleName and ImageDir with an unanchored grep. If a key
    # appears twice (even in a comment) the value breaks and the boot screen falls back to
    # text without any message. Check that each key appears exactly once.
    ply_dupes=0
    for key in ModuleName ImageDir; do
        n=$(grep -cE "${key} *= *" /usr/share/plymouth/themes/hypora/hypora.plymouth 2>/dev/null || true)
        n=${n:-0}
        if [ "$n" -ne 1 ]; then
            warn "hypora.plymouth has $n lines matching '$key'; Plymouth needs exactly one"
            ply_dupes=1
        fi
    done

    # Switch only when the passphrase field and bullet images exist. Without them there
    # would be no visible passphrase prompt on an encrypted disk.
    if [ "$ply_dupes" -eq 0 ] \
       && [ -f /usr/share/plymouth/themes/hypora/entry.png ] \
       && [ -f /usr/share/plymouth/themes/hypora/bullet.png ]; then
        sudo plymouth-set-default-theme hypora -R \
            || warn "Could not set the boot theme; the previous one is still in place"
    else
        warn "Boot screen images are missing; leaving the existing boot theme alone"
    fi

    # Keep the splash on screen until the login screen draws over it. Otherwise the GRUB
    # menu (still in the framebuffer) shows briefly between the two.
    sudo install -d /etc/systemd/system/plymouth-quit.service.d
    sudo install -m644 \
        "$REPO/system/systemd/plymouth-quit.service.d/10-hypora-retain-splash.conf" \
        /etc/systemd/system/plymouth-quit.service.d/10-hypora-retain-splash.conf
    sudo systemctl daemon-reload
else
    warn "Plymouth is not installed; the boot screen stays as it is"
fi

# Boot menu. Fedora's GRUB menu is plain text. hypora-grub writes a theme from the
# palette and switches GRUB to graphics mode so the theme shows. Skipped without a
# warning if there is no GRUB (for example systemd-boot).
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

# ---------- another desktop ----------
# Offered last, and only if another desktop is installed, so that everything else has
# already succeeded. hypora-replace-de refuses while you are running that desktop (it would
# remove the shell your terminal runs in). Running the installer from a GNOME terminal is
# the normal case, so run it again after rebooting into Hypora.
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

# ---------- optional third-party repositories ----------
# RPM Fusion has what Fedora cannot ship: media codecs, NVIDIA's driver, Broadcom's wl.
# It is off unless you ask, because it is a separate trust decision: its release packages
# come over HTTPS and cannot be pinned to a fingerprint (the key changes every Fedora
# release). Once installed, its packages are GPG-checked as normal.
# Set ENABLE_RPMFUSION=yes or no to answer ahead of time.
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

# ---------- Steam (native, needs RPM Fusion nonfree) ----------
# Native, not the flatpak, because the sandbox gets in the way of controllers and game
# libraries outside it. The cost: `steam` comes from rpmfusion-nonfree, so declining RPM
# Fusion means no Steam at all.
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

# Earlier versions installed the Steam flatpak. Remove it once native Steam is there, but
# never with --delete-data: its library can be hundreds of GB of games.
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

# ---------- AI tools (optional) ----------
# Claude Code is only installed if you say yes. Set INSTALL_CLAUDE=yes or no to answer
# ahead of time. Without an answer, a non-interactive run skips it.
CLAUDE_KEY_FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE

# Claude Code can arrive by other routes (Anthropic's install script uses ~/.local/bin,
# npm uses another path), so check all three before asking.
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

# ---------- done ----------
# Print the Hypora logo in its two colours (truecolor if the terminal supports it). It
# uses the same file as fastfetch, where $1 and $2 are colour slots.
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

# Record which commit was installed, so you can tell whether the machine runs the code
# you just changed.
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

 Hyprland's own log is NOT in journalctl (it sets debug.enable_stdout_logs = 0):

   cat /run/user/$UID/hypr/*/hyprland.log

EOF
