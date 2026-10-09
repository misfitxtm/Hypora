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

# `set -e` turns any unchecked failure into a silent exit, and this script has ~1100 lines of
# them. The symptom is a run that stops mid-way with whatever the failing command printed and
# no indication that anything is wrong — a bare "sha256sum: ...: Is a directory" is not a
# diagnosis, and the install it leaves behind is worse than either outcome: configs copied but
# never themed, because hypora-theme runs near the end. So say so, and say what to do.
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
installed_sha() { [ -f "$MANIFEST" ] && awk -v p="$1" 'substr($0, 67) == p { print substr($0, 1, 64) }' "$MANIFEST"; }

# put <src> <dest> [mode]: copy a file into place
put() {
    local src=$1 dest=$2 mode=${3:-644} new
    # Refuse anything that isn't a regular file, with a message naming it. Without this the
    # caller's glob handing over a directory produced only `sha256sum: ...: Is a directory`
    # and, under `set -e`, killed the installer mid-run — which is how a stray bin/__pycache__
    # left an install with its configs in place but never themed.
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
# ---------- baseline ----------
# Hypora's tested baseline is a Fedora Everything netinstall with encryption and btrfs. None
# of it is required and none of it is enforced — this is a report, not a gate — but two of
# the three cannot be added afterwards without reinstalling, so it is worth saying now rather
# than when someone goes looking for the feature that isn't there.
# Is this mountpoint backed by a dm-crypt layer? Asks lsblk what the mounted source *is*
# rather than walking the tree: a LUKS volume is mounted from /dev/mapper/..., whose type
# lsblk reports as "crypt". The bracket strip is for btrfs, which reports its source as
# /dev/x[/subvol].
is_encrypted() {
    local src type
    src=$(findmnt -fno SOURCE "$1" 2>/dev/null) || return 1
    [ -n "$src" ] || return 1
    src=${src%%[*}
    type=$(lsblk -no TYPE "$src" 2>/dev/null | head -1)
    [ "$type" = crypt ]
}

baseline_note() {
    local missing=0
    # -f is --first-only throughout: a path can have more than one mount entry (bind mounts,
    # overlays, a sandbox), and without it the substitution returns several lines and every
    # comparison below quietly fails.
    if [ "$(findmnt -fno FSTYPE / 2>/dev/null)" != btrfs ]; then
        warn "/ is not btrfs, so there will be no snapshots (cannot be converted later)"
        missing=1
    fi
    # Encryption, judged on where your files actually are. If /home is its own encrypted
    # volume then user data is protected whatever / is doing, and calling such a machine
    # "unencrypted" is just wrong. So /home decides the warning and / gets a note.
    if [ "$(findmnt -fno TARGET /home 2>/dev/null)" = /home ]; then
        if ! is_encrypted /home; then
            warn "/home is not encrypted, so your files can be read by anyone holding the drive"
            missing=1
        fi
    elif ! is_encrypted /; then
        # No separate /home, so / is the volume holding everything
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
# Decided once, here, so that every laptop-specific step below asks the same question and
# gets the same answer. `hypora-power is-laptop` is the authority rather than a test
# written out again: it reads the SMBIOS chassis type, which is a different question from
# "is there a battery" — a desktop with a UPS has one, and so does a paired wireless mouse.
#
# Set IS_LAPTOP=yes or =no to override, for a machine whose firmware reports nonsense.
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

# Release the dnf lock before any of the package work below.
#
# dnf5daemon-server takes the system repository lock, and every dnf command in this script
# then waits for it — not with an error, but indefinitely, which reads as the installer
# hanging on whatever step it happened to reach. On a real install it sat there for over an
# hour on `dnf mark`, with a daemon that had been up since before the run started.
#
# Safe to stop: the unit is Type=dbus with BusName=org.rpm.dnf.v0 and no [Install] section,
# so it is never "enabled" in the first place — it is activated on demand and anything that
# wants it (GNOME Software, most often) brings it straight back afterwards. Stopped, not
# disabled, for exactly that reason.
#
# `timeout` because its TimeoutStopSec is 5min: if it is mid-transaction, waiting that long
# to start is worse than carrying on and letting the per-command timeouts handle it.
for svc in dnf5daemon-server packagekit; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        log "Stopping $svc so it releases the dnf lock (D-Bus restarts it on demand)"
        sudo timeout 60 systemctl stop "$svc" \
            || warn "Could not stop $svc; dnf steps may stall waiting for its lock"
    fi
done

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
    #
    # gnome-keyring-pam is a separate package on Fedora and ships pam_gnome_keyring.so,
    # which is the whole mechanism behind the keyring auto-unlock enabled further down.
    # Listing only gnome-keyring left the module absent while authselect happily wrote the
    # PAM lines referencing it — and because those lines are `optional` and `-` prefixed,
    # PAM skips a missing module without even logging it. Login worked and the keyring
    # silently never unlocked. gcr provides the prompter it talks to.
    gnome-keyring gnome-keyring-pam gcr
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
    # Kept on purpose, and listed here so they are marked user-installed: that is what keeps
    # `dnf autoremove` and hypora-replace-de's sweep from treating them as GNOME leftovers.
    # Calendar, Disk Usage Analyzer and Document Scanner have no Hypora equivalent and
    # nothing else here replaces them.
    gnome-calendar baobab simple-scan
    cliphist wl-clipboard grim slurp
)
# Nice to have; a missing one only produces a warning
OPTIONAL=(
    hyprsunset
    # Wi-Fi power save, which tuned's empty [net] section does not touch
    iw
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

# Mark the load-bearing packages user-installed, so `dnf autoremove` can never take them.
#
# This is not belt-and-braces; it is the fix for something that already happened. On a stock
# Workstation install these arrive with reason `Group` or `Dependency`, which is exactly what
# autoremove collects once the desktop that pulled them in is gone. A plain `dnf autoremove`
# run by hand after removing gnome-shell took gnome-keyring-pam and gcr, silently disabling
# keyring auto-unlock — the PAM lines are `optional` and `-` prefixed, so PAM skips the
# missing module without even logging it.
#
# `dnf install` does not reliably change an existing package's reason, so mark explicitly.
PROTECT_USER=(
    gsettings-desktop-schemas xorg-x11-server-Xwayland
    gnome-keyring gnome-keyring-pam gcr
    nautilus gvfs gnome-calculator gnome-disk-utility gnome-software
    gnome-calendar baobab simple-scan papers evince
)
# Filter with rpm, which is instant, so dnf is only asked about packages that are really
# there. That also means one unavailable name cannot cost the whole batch its protection.
protect_now=()
for p in "${PROTECT_USER[@]}"; do
    rpm -q "$p" >/dev/null 2>&1 && protect_now+=("$p")
done
if [ ${#protect_now[@]} -gt 0 ]; then
    log "Protecting ${#protect_now[@]} required packages from dnf autoremove"
    # One dnf call, not one per package, and bounded. An earlier version ran `dnf mark` in a
    # loop with its output redirected to /dev/null, which made the installer appear to hang
    # here. Two separate costs were behind that, and only the second is a real stall:
    #
    #   * dnf start-up is ~7s even with -C, so fifteen invocations cost ~2 minutes of nothing
    #     visible happening. Hence one call.
    #   * `dnf mark` takes the system repository lock and then waits for it *indefinitely*.
    #     Anything else touching dnf holds that lock — PackageKit or gnome-software doing a
    #     background refresh is the usual culprit, and dnf-automatic is enabled by this very
    #     script. That is the actual hang, and no amount of caching avoids it.
    #
    # So `timeout` is the fix, not an optimisation: this step is hardening, and it must never
    # be the reason an install fails to finish. -C stays because a reason change touches only
    # the local rpmdb and has nothing to resolve; the plain retry covers a missing cache.
    if ! sudo timeout 45 dnf -C -y mark user "${protect_now[@]}" >/dev/null 2>&1 \
       && ! sudo timeout 90 dnf -y mark user "${protect_now[@]}" >/dev/null 2>&1; then
        warn "Could not mark packages user-installed (dnf was busy or locked), so a later"
        warn "  'dnf autoremove' may remove them. Run this when nothing else is using dnf:"
        warn "    sudo dnf mark user ${protect_now[*]}"
    fi
fi

log "Installing virtualization (@virtualization group)"
# Without virt-viewer: the group pulls it in, and its `remote-viewer` is a second, worse
# remote-desktop client sitting next to RustDesk below. virt-manager has its own built-in
# console for local VMs and does not depend on it, so nothing loses a feature.
sudo dnf group install -y virtualization --exclude=virt-viewer \
    || warn "Could not install the virtualization group"
# Drop a copy an earlier run of this installer brought in. It is a leaf package — nothing
# installed requires it — so this removes exactly one thing.
if rpm -q virt-viewer >/dev/null 2>&1; then
    log "Removing virt-viewer (remote-viewer); RustDesk replaces it"
    sudo dnf remove -y virt-viewer || warn "Could not remove virt-viewer"
fi

# A brief earlier version of this installer used RustDesk's own unsigned RPM. The flatpak
# replaced it, so drop the RPM rather than leaving two RustDesks in the launcher.
if rpm -q rustdesk >/dev/null 2>&1; then
    log "Removing the RustDesk RPM (the verified Flathub build replaces it)"
    sudo dnf remove -y rustdesk || warn "Could not remove the RustDesk RPM"
fi

# GNOME Help. Removed here as well as by hypora-replace-de's sweep, because the sweep only
# runs while a desktop is still detected — on a machine where GNOME's session has already
# gone, yelp is left stranded with no way to catch it. Its content package (gnome-user-docs)
# documents a shell that isn't running, so the reader has nothing useful to show.
if rpm -q yelp >/dev/null 2>&1; then
    log "Removing GNOME Help (yelp)"
    sudo dnf remove -y yelp || warn "Could not remove yelp"
fi

# Document viewer. Fedora renamed Evince to Papers, so take whichever this release has
# rather than hardcoding a name that breaks on one side of the rename.
for viewer in papers evince; do
    if available "$viewer"; then
        sudo dnf install -y "$viewer" || warn "Could not install $viewer (document viewer)"
        break
    fi
done

log "Installing optional packages"
for p in "${OPTIONAL[@]}"; do
    sudo dnf install -y "$p" || warn "Skipped optional package: $p"
done
# 'install' leaves an already-installed (possibly old) Hyprland alone
sudo dnf upgrade -y hyprland uwsm || true

# ---------- laptop-only packages ----------
# brightnessctl drives a backlight, so there is nothing for it to do on a machine with no
# panel to dim. upower deliberately stays in REQUIRED rather than moving here: it also
# reports the batteries in wireless mice and keyboards, which desktops very much have.
if [ "$IS_LAPTOP" = yes ] && available brightnessctl; then
    sudo dnf install -y brightnessctl || warn "Skipped brightnessctl (brightness keys will not work)"
fi

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

# ---------- snapshots (btrfs only) ----------
# snapper rather than Timeshift, and only where there is btrfs to snapshot.
#
# Timeshift was the obvious choice and is the wrong one here: its BTRFS mode requires the
# Ubuntu-style subvolume layout, with / on a subvolume literally named `@`. Fedora's
# installer creates `root` and `home`, so on a stock Fedora btrfs install Timeshift silently
# offers only its RSYNC mode — copying files, not snapshotting. snapper does not care what
# the subvolumes are called, which on Fedora is the difference between real snapshots and a
# slow file copy.
#
# What this does not get you, because there is no honest way to: automatic snapshots around
# a manual `dnf upgrade`. python3-dnf-plugin-snapper is a dnf4 plugin and Fedora now runs
# dnf5, which has no snapper plugin at all, so installing it would hook nothing. The
# unattended updates Hypora enables are covered instead by a drop-in further down, and the
# readme says plainly that a manual upgrade is yours to snapshot.
has_btrfs() {
    findmnt -nt btrfs >/dev/null 2>&1 && return 0
    lsblk -no FSTYPE 2>/dev/null | grep -qx btrfs
}

# Set KEY="value" in a shell-style config, whether or not the key is already there.
# Both snapper's configs and btrfsmaintenance's sysconfig are this shape.
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

# create-config, then limits that won't quietly eat the disk. snapper's defaults keep ten
# hourly, ten monthly and ten yearly snapshots per config, which on a laptop is a lot of
# retained extents for very little benefit.
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
        # / first, which is what an update can break
        if [ "$(findmnt -fno FSTYPE / 2>/dev/null)" = btrfs ]; then
            snapper_setup root / && snapper_any=1
        else
            log "  / is not btrfs, so there is no config for it"
        fi
        # /home separately: it is usually its own subvolume, and the snapshots people
        # actually reach for are of their own files
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

        # A GUI for it. snapper is CLI-only, and browsing snapshots to find the one you want
        # is the part that genuinely wants a list you can click. This is the thing Timeshift
        # was better at, and btrfs-assistant closes it.
        if available btrfs-assistant; then
            sudo dnf install -y btrfs-assistant \
                || warn "Could not install btrfs-assistant (snapshots stay command-line only)"
        else
            warn "No btrfs-assistant package; snapshots are command-line only"
        fi
    fi
fi

# ---------- btrfs housekeeping ----------
# Nothing on a stock Fedora runs these, and btrfs wants them:
#   scrub    reads every block and checks it against its checksum. This is how bit rot is
#            found — and finding it matters more with snapshots, because a corrupted extent
#            is shared by every snapshot referencing it.
#   balance  reclaims chunks that are allocated but mostly empty, which is the usual cause
#            of "no space left" on a filesystem that df says is half free.
#
# Two periods are deliberately left off:
#   trim     Fedora already enables fstrim.timer, so this would be the second thing doing it.
#   defrag   defragmenting a filesystem with snapshots *unshares* the extents snapshots have
#            in common, so it can multiply disk usage instead of tidying it. Wrong tool here.
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
        # The package's own refresh unit reads that config and enables exactly the timers it
        # describes. Preferred over enabling timers directly, which would then disagree with
        # the config the next time anything ran the refresh.
        if systemctl cat btrfsmaintenance-refresh.service >/dev/null 2>&1; then
            # `start`, not `enable --now`. The refresh service is a Type=oneshot helper with
            # no [Install] section, so enabling it is a no-op that makes systemd print nine
            # lines explaining that the unit isn't meant to be enabled — noise in an already
            # long log. Starting it is the half that actually applies the schedule.
            sudo systemctl start btrfsmaintenance-refresh.service \
                || warn "Could not apply the btrfsmaintenance schedule"
            # The .path unit beside it is the one with [Install], and enabling it is what
            # keeps the timers in step with /etc/sysconfig/btrfsmaintenance if that file is
            # edited later. Nothing enabled it before, so a later change went unnoticed.
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
    # Remote desktop, replacing virt-viewer's remote-viewer. Publisher-verified on Flathub
    # (via rustdesk.com), which is better provenance than the project's own RPM: that one is
    # unsigned, so a pinned hash would prove only that the bytes hadn't changed since someone
    # looked at them, not who built them.
    com.rustdesk.RustDesk
    # Steam is installed natively instead, further down — the flatpak's sandbox gets in the
    # way in practice (controller access, filesystem paths to existing libraries, launching
    # anything outside it). Native Steam needs RPM Fusion nonfree, so it is installed with
    # that section rather than here.
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

    # Snapshot before an unattended update, when there is a snapper config for /.
    #
    # This is the gap left by there being no dnf5 snapper plugin: nothing hooks a dnf
    # transaction, so an update that installs itself overnight does so with no way back. A
    # drop-in on the service that performs it is the one place to catch that — and it is the
    # case that matters most, because it is the one you were not watching.
    #
    # ExecStartPre is prefixed with `-` so a failing snapshot cannot stop security updates
    # from installing. An update that applied is worth more than a snapshot that didn't.
    if [ -f /etc/snapper/configs/root ]; then
        for unit in dnf5-automatic dnf-automatic; do
            if systemctl cat "$unit.service" >/dev/null 2>&1; then
                sudo install -d "/etc/systemd/system/$unit.service.d"
                sudo tee "/etc/systemd/system/$unit.service.d/10-hypora-snapshot.conf" \
                    >/dev/null <<'DROPIN'
# Added by Hypora: take a btrfs snapshot of / before an unattended update, so an update
# that breaks something can be undone. Harmless if snapper is removed — the `-` prefix
# means a failure here is ignored rather than cancelling the update.
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

# Keyring auto-unlock, and fingerprint login.
#
# Both go through authselect, which is how Fedora expects PAM to be changed. An earlier
# version of this appended three lines to /etc/pam.d/sddm by hand, and that was working
# around a problem Fedora had already solved: authselect ships `with-pam-gnome-keyring`
# and `with-fingerprint` as features, writes them into system-auth and password-auth —
# which sddm's stack includes — and keeps them across package updates. Editing the service
# file directly also risked overriding a vendor file in /usr/lib/pam.d outright, which
# would have replaced the whole auth stack with three lines.
#
# authselect's keyring feature covers the auth and session lines but not the `password`
# one, so a password change would otherwise orphan the keyring behind a passphrase nobody
# knows. That single line is added separately, which is a much smaller edit than the stack.
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
    # The re-key line authselect's feature leaves out
    PAM_PW=/etc/pam.d/system-auth
    if [ -f "$PAM_PW" ] && ! grep -q "pam_gnome_keyring.so use_authtok" "$PAM_PW"; then
        sudo cp -a "$PAM_PW" "$PAM_PW.hypora-$(date +%Y%m%d-%H%M%S)"
        printf '%s\n' '-password   optional   pam_gnome_keyring.so use_authtok' \
            | sudo tee -a "$PAM_PW" >/dev/null
        log "  added the keyring re-key line to $PAM_PW"
    fi
fi

# Fingerprint, only where there is a reader libfprint might drive.
if "$REPO/bin/hypora-hardware" fingerprint >/dev/null 2>&1; then
    log "Setting up the fingerprint reader"
    sudo dnf install -y fprintd fprintd-pam \
        && enable_authselect_feature with-fingerprint "fingerprint login" \
        && log "  enrol a finger with: fprintd-enroll" \
        || warn "Could not set up the fingerprint reader"
fi

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
#   hypora-grub       documented as `sudo hypora-grub apply`; it writes /etc/default/grub
#                     and regenerates grub.cfg, so a tampered copy decides how you boot
#   hypora-power      documented as `sudo hypora-power install`; it writes a udev rule and
#                     sysfs power controls, and udev runs it as root on every AC change
#   hypora-replace-de documented as `sudo hypora-replace-de remove`; it removes packages
#                     and briefly moves a dnf protection file aside to do it
#
# The test is simply "does anything tell you to run this under sudo", which is why these
# six and not the others — the rest never need more than your own privileges.
ROOT_OWNED=(hypora-security hypora-console hypora-hardware hypora-grub hypora-power
            hypora-replace-de)

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
        # Files only. `bin/*` matches directories too, and a __pycache__ left behind by
        # running one of these scripts as a Python module is enough to stop the installer
        # dead here — the same guard the quickshell loop above has always had.
        [ -f "$f" ] || continue
        name=$(basename "$f")
        skip=
        for r in "${ROOT_OWNED[@]}"; do [ "$name" = "$r" ] && skip=1; done
        [ -n "$skip" ] && continue        # root-owned, installed above
        put "$f" "$HOME/.local/bin/$name" 755
    done
fi

# ---------- laptop power ----------
# Only where there is a battery. The saving comes from two places: nothing on a Hyprland
# session switches the power profile when the charger comes out — GNOME does that in its
# shell, so without it a laptop sits in `balanced` on battery indefinitely — and tuned's
# own powersave profile leaves PCIe ASPM, USB autosuspend and PCI runtime power management
# untouched. hypora-power covers both and installs a udev rule so it follows the charger.
# Uses the decision made at the top rather than asking again. hypora-power refuses to
# install on a desktop regardless, so this is belt and braces — but it also keeps the two
# answers from ever disagreeing, which is the point of deciding once.
if [ "$IS_LAPTOP" = yes ]; then
    log "Setting up laptop power management"
    sudo /usr/local/bin/hypora-power install \
        || warn "Could not set up automatic power switching"
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

    # Hold the splash on screen until the login screen paints over it.
    #
    # Plymouth draws into its own buffer, so when it exits the framebuffer underneath is
    # still whatever was there before — on a themed setup, the GRUB menu. That is why the
    # menu reappears for a moment between the splash ending and SDDM arriving. It is not
    # GRUB being redrawn; it is GRUB never having been painted over.
    sudo install -d /etc/systemd/system/plymouth-quit.service.d
    sudo install -m644 \
        "$REPO/system/systemd/plymouth-quit.service.d/10-hypora-retain-splash.conf" \
        /etc/systemd/system/plymouth-quit.service.d/10-hypora-retain-splash.conf
    sudo systemctl daemon-reload
else
    warn "Plymouth is not installed; the boot screen stays as it is"
fi

# Boot menu. The GRUB menu is the one screen before Plymouth, and Fedora leaves it as white
# text on black in 80x25 text mode — GRUB_TERMINAL_OUTPUT="console". hypora-grub writes a
# theme from the active palette and switches GRUB to graphics mode so the theme is actually
# shown; see bin/hypora-grub for why those two have to happen together.
#
# Skipped silently where there is no GRUB: a system booting with systemd-boot or straight
# from UEFI has nothing here to theme, and that is not a problem worth a warning.
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
# Offered last, and only when something else is installed. The order matters more than it
# looks: this is where Hypora stops being an addition and starts being a replacement, and
# it should happen after everything else has succeeded rather than before.
#
# hypora-replace-de refuses outright if you are running the desktop in question, because
# removing a shell out from under a live session takes the terminal the command was typed
# into with it, half way through a dnf transaction. Running the installer from a GNOME
# terminal is the normal case, so expect that refusal and run it again after rebooting
# into Hypora.
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
# Native rather than the flatpak. The sandbox is the problem in practice: controller and
# filesystem access, and reaching game libraries that live outside it, all take fighting.
#
# The cost of the switch is stated plainly because it is real: `steam` lives in
# rpmfusion-nonfree-steam, so declining RPM Fusion above means no Steam at all, where the
# flatpak would have worked. Nothing is installed silently either way.
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

# An earlier Hypora installed the Steam flatpak. Two Steams in the launcher is the confusion
# this change was meant to end, so retire the flatpak — but never with --delete-data: the
# library under ~/.var/app can be hundreds of GB of games, and it is not ours to throw away.
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
# Claude Code is not installed unless you say so. Set INSTALL_CLAUDE=yes or =no to answer
# ahead of time; without an answer on a non-interactive run it is skipped.
CLAUDE_KEY_FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE

# Three ways, because Claude Code can arrive by routes other than this one: Anthropic's
# own install script puts it in ~/.local/bin and npm puts it elsewhere again. Asking a
# second time on a machine that already has it is the whole complaint.
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
