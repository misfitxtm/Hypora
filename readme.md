# Hypora

A **privacy-focused Hyprland desktop for Fedora**, installed with a single post-install script on top of a stock Fedora install (no custom ISO). The shell is built on [Quickshell](https://quickshell.org): a custom bar, control center, notification daemon and polkit prompt, all themeable from one palette file.

The aim is an "install it and it just looks good" experience that doesn't take control away from you: a small, readable codebase of plain shell scripts and QML with no framework on top, one place to change colours, and AI tooling that is offered but never assumed.

## Alpha

> **Hypora is alpha software.** The majority of it works — the installer, the shell, the login screen, theming, and the Security, Display, Network, Bluetooth and Sound windows have all been exercised on real hardware. But **some sections are incomplete and there are known bugs**, and you should expect to hit them.
>
> Known-incomplete and under investigation:
>
> - **Boot** — the GRUB framebuffer leftover (a black box after menu selection, and the menu reappearing after the splash) is still being chased; `fbcon=nodefer` is the current fix and is not yet confirmed on hardware
> - **Battery** — on at least one ThinkPad the embedded controller's gauge reports 100% while discharging. This is a firmware reading, not Hypora's arithmetic, but the bar shows what it is given
> - **Boot time** is longer than it should be and hasn't been profiled yet
> - **Not yet run end to end:** `hypora-power install` and fingerprint enrolment. `hypora-replace-de` has now been run on real hardware, which is how its missing cleanup phase and a silent keyring-auto-unlock breakage were found — both fixed
> - **Packaging** — `packages/*.txt` and a modular `install/` directory are planned, not written
> - **Theming** — TokyoNight's `dim` colour sits at 2.76 contrast, just under the 3.0 floor the other themes meet
>
> Most development happened in a VM. It has since been installed and booted on bare metal, but hardware-specific pieces (GPU, battery, backlight) have had far less exercise than the rest. Please [file what you find](#reporting-bugs).

## What privacy means here

Specific things, not a slogan:

- **Nothing phones home.** No telemetry, no analytics, no update pings of our own.
- **The weather widget never geolocates you.** You pick a city by name; only that name is sent, and until you pick one no weather request is made at all.
- **AI tooling is opt-in.** The installer asks before installing Claude Code, and the default answer is no. Decline, and the menu has no Claude entry at all — nothing advertises it back at you.
- **Your security state is visible and adjustable** — Secure Boot, firmware checks, SELinux, camera, microphone, location and file history all in one window, with each switch saying plainly what it does and does not cover.
- **Flatpak apps come with the tools to audit them:** Flatseal for permissions, Warehouse for what's installed and what data it left behind. Firefox and Spotify run sandboxed rather than as system packages.
- **Everything downloaded is verified.** Each file fetched outside dnf is pinned to a release and checked against a recorded SHA-256; the Hyprland COPR's signing key is checked against a pinned fingerprint before anything installs from it; Claude Code's repository key likewise. HTTPS proves which host answered, not what it sent.
- **The firewall is on, and closed by default.** Fedora's workstation zone leaves ports 1025-65535 open on TCP and UDP; Hypora uses `public`, which allows only ssh, mDNS and DHCPv6, and opens LocalSend's port because that's the one thing here that listens.
- **DNS is encrypted where it can be, and stays yours.** systemd-resolved with DNS-over-TLS in opportunistic mode, following the network rather than overriding it — which is what keeps a resolver you run yourself in charge. [Quad9](https://quad9.net) is the fallback. See [DNS](docs/network.md#dns).
- **Your MAC address doesn't follow you between networks.** Scanning is randomized, and each network sees a per-network address rather than the card's permanent serial. See [MAC addresses](docs/network.md#mac-addresses).
- **Security updates install themselves, and the third-party repo doesn't.** Fedora security advisories and flatpak updates apply daily; the Hyprland COPR is deliberately excluded, so the compositor never changes under you. See [Automatic updates](docs/security.md#automatic-updates).
- **The screen locks on its own.** Ten minutes to lock, fifteen to blank, and it locks before suspending.
- **Full-disk encryption is checked, not assumed.** The Security window reports whether this system is on an encrypted volume, and warns about swap reaching the disk in the clear. Encryption itself has to be chosen when Fedora is installed — see [Requirements](#requirements).
- **Secrets stay out of argv and privileged paths stay out of `$HOME`.** Wi-Fi passwords go to `nmcli` on stdin, never as an argument any process could read from `/proc`; every helper that runs as root lives in a root-owned directory, never in `~/.local/bin` — a script you can write that something runs with `sudo` is a way to become root, not a convenience.

## Screenshots

All shown in **Nord**; every theme drives the same widgets from its own palette.

**The menu** (`AppMenuPanel.qml`), from the Hypora logo at the top left. Sections on the left, a section opened on the right — Settings lists Hypora's own windows, not the system's control panels.

<p>
<img src="docs/images/menu-sections.png" alt="The Hypora menu, showing its six sections" width="330">
<img src="docs/images/menu-settings.png" alt="The menu's Settings section" width="330">
</p>

**The theme picker** (`ThemePicker.qml`), **SUPER + ALT + T**. The centred card is the one Enter applies; neighbours sit back and dim. Previews are generated from each theme's `colors.toml`, not screenshots.

<img src="docs/images/theme-picker.png" alt="The Hypora theme picker, sliding between themes" width="800">

**The Security window** (`SecuritySettings.qml`), Menu > Security — shown with the deeper checks already run, so the firmware attributes and the firewall's zone are filled in.

<img src="docs/images/security.png" alt="The Hypora Security window" width="620">

**Included wallpapers**, with each theme's background, surface and accent swatches at the right.

![The wallpapers shipped with each theme](docs/images/wallpapers.png)

> Shots of the bar and the login screen are still to be added.

## Requirements

Hypora is built and tested against one baseline, and everything below works on it:

> **Fedora Everything netinstall**, with **"Encrypt my data" ticked** and **btrfs** as the filesystem.

None of the three is enforced — the installer runs on a stock Workstation install on ext4 without encryption and most of it works fine. But each one you skip takes a feature with it, and two cannot be added later without reinstalling:

| Choice | What you get | If you skip it |
|---|---|---|
| **Everything netinstall** | a base with no second desktop competing for the session | you are carrying two desktops. Hypora disables GDM and uses its own session, and `hypora-replace-de` can remove the other one's session, its leftover packages and their orphaned libraries — see [Replacing another desktop](docs/desktop.md#replacing-another-desktop) |
| **Encrypt my data** (LUKS) | full-disk encryption, and a themed passphrase prompt at boot | the disk is readable by anyone holding it. **Cannot be added later** — LUKS is set up as the partitions are created |
| **btrfs** | snapshots via snapper (with the btrfs-assistant GUI), one before every unattended update, plus scheduled scrub and balance | no snapshots and no scrub, so bit rot goes unnoticed. **Cannot be converted later** in any way worth attempting on a system you care about |

The installer checks these at the start, tells you which you are missing, and carries on.

Also needed:

- A fresh **Fedora** install (tested on Fedora 44), an internet connection, and a user with `sudo`
- **Hyprland 0.55 or newer** — the config is Lua (`hyprland.lua`), which replaces the deprecated `hyprland.conf` format
- A Quickshell build with the PipeWire, system tray, notifications, UPower and polkit modules. The installer enables COPRs if the packages aren't in the main repos
- **The SSH server is switched off** and port 22 closed, because it is the one service on a stock Fedora desktop reachable from the network. Pass `KEEP_SSH=yes` to keep it; the installer keeps it automatically if you are installing *over* SSH. Re-enable with `sudo systemctl enable --now sshd`

## Install

Two ways to get the files. Either works; the difference is only which revision you end up on.

**Download a release** — a fixed set of files that was tested as a unit. On alpha this is the one to pick if you want to be able to say *which* Hypora you are reporting a bug against. Grab the source tarball from the [releases page](https://github.com/misfitxtm/Hypora/releases), or:

```bash
mkdir -p ~/.local/share/hypora
curl -fsSL https://github.com/misfitxtm/Hypora/archive/refs/tags/v0.1.0-alpha.tar.gz \
  | tar xz --strip-components=1 -C ~/.local/share/hypora
cd ~/.local/share/hypora
./install.sh
```

**Clone the repository** — tracks `main`, so you get fixes as they land, which during alpha is most days. Also what you want if you intend to read or change the code, since you keep the history:

```bash
git clone https://github.com/misfitxtm/Hypora.git ~/.local/share/hypora
cd ~/.local/share/hypora
./install.sh
```

Pick a theme with the `THEME` variable (it must exist under `themes/`). Re-runs keep the theme you last chose with `hypora-theme`:

```bash
THEME=TokyoNight ./install.sh
```

The installer is safe to re-run. It:

1. Checks you're on Fedora and not running as root, and whether this is a laptop or a desktop — the battery and backlight pieces only install on a laptop
2. Enables the `sdegler/hyprland` COPR (Fedora doesn't package Hyprland or uwsm) and checks Hyprland is 0.55+
3. Installs required packages, warning and continuing if an optional one is unavailable: PipeWire with wiremix, BlueZ, tuned-ppd, zsh, Neovim, fastfetch, `@virtualization` (libvirt, QEMU/KVM, virt-manager), and network and security tools (nmap, aircrack-ng, wireshark/tshark)
4. Installs Oh My Zsh and the LazyVim starter, both pinned to a commit, and makes zsh your login shell (an existing `~/.config/nvim` is left alone)
5. Installs JetBrainsMono Nerd Font and the system font defaults
6. Enables NetworkManager, upower, bluetooth and power profiles; points DNS at systemd-resolved with DNS-over-TLS; randomizes MAC addresses; enables `firewalld` in the closed `public` zone; turns on automatic security updates for packages and flatpaks; sets up keyring auto-unlock; and sets the default boot target to graphical
7. Installs the theme palettes and templates into `~/.config/hypora/` and applies the chosen theme
8. **Copies** `config/hypr/hyprland.lua`, `config/quickshell/`, the GTK settings and the themes into `~/.config/`, and `applications/*.desktop` into `~/.local/share/applications/`
9. Installs the SDDM login theme, disables GDM/LightDM/greetd, enables SDDM, and installs the Plymouth boot theme — the slowest step, because it rebuilds the initramfs
10. Copies `bin/` into `~/.local/bin/`, except the root-owned helpers, which go to `/usr/local/bin`
11. Checks hardware, firmware and drivers (see [Hardware](docs/hardware.md))
12. On btrfs, sets up snapper, btrfs-assistant and btrfsmaintenance (see [Snapshots](docs/storage.md#snapshots))
13. Offers to remove another desktop if one is installed — session, leftovers and orphans, keeping what Hypora is built on — then **offers RPM Fusion**, then **offers Claude Code**. All three default to no, and all three are at the end of the run so a declined answer costs nothing

Anything it replaces that you had changed is saved as `<name>.bak.<timestamp>`.

Configs are **copies**, so the directory you installed from can be moved or deleted afterwards. To update, `git pull` (or download a newer release over the same directory) and re-run `./install.sh`: it records a checksum of every file it installs, so files you haven't touched are updated quietly, files you edited are saved as `<name>.bak.<timestamp>` before being replaced, and files Hypora no longer ships are removed (unless you edited them). Quickshell live-reloads when you edit `~/.config/quickshell/*.qml`.

### Starting the desktop

Reboot. SDDM shows the Hypora login screen and starts the **Hyprland (uwsm-managed)** session. On machines with more than one user, the name appears above the box.

Without the login screen, start it from a text console with `uwsm start hyprland-uwsm.desktop` (or `start-hyprland`). Quickshell starts from the `hyprland.start` hook in `hyprland.lua` either way.

## What you get

**Desktop**

- A minimal SDDM login screen: the time, the date and a password field, in the active theme's colours
- Hyprland, started through `uwsm`
- Quickshell as the shell layer — it replaces Waybar, Mako *and* a standalone polkit agent

**Quickshell components** (`config/quickshell/`)

| Component | What it does |
|---|---|
| Bar (`Bar.qml`) | Top bar on every monitor: menu button, that monitor's own workspaces, clock, tray and status icons. See [Workspaces and monitors](docs/desktop.md#workspaces-and-monitors) |
| Menu (`AppMenu.qml`, `AppMenuPanel.qml`) | From the Hypora logo at the top left. Six sections: **Apps**, **Style**, **Settings** (Hypora's own windows, not the system's control panels), **Security**, **Tools** — including **Set up fingerprint**, shown only where there is both a reader and `fprintd` to drive it — and **Help**, with Keybindings and **Report a bug**. Enter or Right opens a section, Esc or Left goes back, typing searches apps. Power actions live in the control center |
| Security & Privacy (`SecuritySettings.qml`) | Two sections. **Security**: Secure Boot, disk encryption and unencrypted swap (with **Add swapfile** — see [Swap](docs/storage.md#swap)), firmware checks (see [Firmware updates](docs/security.md#firmware-updates)), encrypted DNS, MAC randomization, the firewall's zone, automatic updates and SELinux. **Privacy**: location (masks GeoClue), camera (unloads `uvcvideo`), microphone (mutes it in PipeWire) and GTK file history, with a Clear button. Grouped by subject rather than by component — a camera is about you, a firewall is about the machine. **Opening it never asks for a password**; the two readings that need root sit behind one **Run the deeper checks** prompt rather than one per service. There is no periodic refresh, because re-reading on a timer turned one prompt into one every fifteen seconds; instead a change moves its own switch straight away and the window re-reads when the change finishes |
| Volume and brightness slider (`Osd.qml`) | Appears along the bottom of the focused monitor on a volume or brightness key, and leaves after a second and a half. Volume is a watched PipeWire property, so it also appears when the bar or control center changes it; brightness is pushed from the keybind instead, because the kernel exposes it as a sysfs file and sysfs raises no reliable change event. **Brightness is only wired up where there is a backlight** — a desktop has an empty `/sys/class/backlight`, and a slider that cannot move is worse than none. It takes no keyboard focus and clicks pass through it |
| Keyboard shortcuts (`KeybindHelp.qml`) | Menu > Help > Keybindings: every shortcut, grouped; click one and press the new combination to rebind it. **Your shortcuts are paused while it waits**, via the `keyboard-shortcuts-inhibit` protocol — Hyprland handles binds before any client sees the key, so otherwise SUPER + Q to rebind "Close window" would just close the window. Because the inhibition belongs to the window, nothing can leave you with a desktop that has no working keys, and the prompt turns amber if the compositor didn't agree. A chord already in use is **accepted**, not refused, with a banner naming the clash — refusing it made swapping two shortcuts impossible. Changes go to `~/.config/hypr/keybinds.lua`; delete it or use **Reset all** for stock |
| Theme picker (`ThemePicker.qml`) | **SUPER + ALT + T**: a full-screen carousel, each card a live preview — the theme's own wallpaper under a miniature desktop drawn in its colours, plus its palette. Arrows or scroll to slide, Enter to apply, Esc to close, type to filter |
| Wallpaper (`Wallpaper.qml`) | Cross-fades the wallpaper on every monitor. Each theme ships several; cycle with menu > Style > **Next wallpaper** (or `qs ipc call wallpaper next`). Your choice is remembered |
| Weather (`Weather.qml`) | Current conditions and a three-day forecast, right of the clock. You pick the city by name — no IP geolocation, and nothing requested until you choose. Data from [Open-Meteo](https://open-meteo.com), which needs no account or API key; `bin/hypora-weather` does the lookups and can be run on its own |
| Sound (`AudioSettings.qml`) | Output and input devices with their own volume and mute, a picker when there's more than one, and a row per playing application. Talks to PipeWire through Quickshell — no pavucontrol. `wiremix` is behind "Advanced" for routing and profiles |
| Control center (`ControlCenter.qml`, `ControlPanel.qml`) | Click the status icons at the top right: Lock / Log out / Restart / Power off (the last three ask for a second click), volume and brightness, power mode (Saver / Balanced / Performance — see [Power](docs/power.md)), and Wi-Fi, Bluetooth, Do Not Disturb and Night Light tiles |
| Network (`NetworkSettings.qml`, `Network.qml`) | Wi-Fi on/off, nearby networks with signal strength, connect (asking for a password when it's a new secured network), disconnect and forget. No terminal needed. The bar icon updates live via `nmcli monitor` |
| Bluetooth (`BluetoothSettings.qml`) | Power and scanning, pair, connect, disconnect and forget, with device battery where reported |
| Display (`DisplaySettings.qml`) | Resolution, refresh rate, scale, rotation and on/off per monitor. **Arrangement is set by dragging** a screen on the map — edges snap together, overlaps are refused, and the layout is anchored at 0,0. **Main display** is a toggle: that screen starts focused and Hypora's menu and clipboard open there, instead of on whichever output Quickshell enumerated first. Changes apply live, then a prompt appears **on every monitor** asking whether to keep them, reverting after 15 seconds — on every screen because a bad mode can hide the window holding the undo. Enter keeps, Esc reverts; kept settings go to `~/.config/hypr/monitors.lua` |
| Battery (`Battery.qml`, `BatteryWatch.qml`) | Charge in the bar on laptops, red when low. Notifies at 20% and 10% and suspends at 5%, because a laptop that runs flat mid-write is how filesystems get damaged. Each threshold fires once per discharge; plugging in resets them |
| Clipboard (`Clipboard.qml`) | History left of the clock, also on **SUPER + SHIFT + V**: click a recent copy to put it back, or Clear to wipe it. Recorded by `wl-paste --watch cliphist store`, since Quickshell doesn't speak `wlr-data-control` |
| Clock and calendar (`Clock.qml`, `CalendarPanel.qml`) | Click the clock: time, date and a month calendar. Arrows or scrolling change the month; click the month name to jump back to today |
| System usage (`SystemUsage.qml`, `SysInfo.qml`) | Live RAM, CPU, CPU temperature and, where reported, GPU usage and temperature, warming to the accent colour and then red as they climb. Click to choose which appear; numbers come from `bin/hypora-sysinfo` |
| Notifications (`Notifications.qml`) | Quickshell *is* the notification daemon: popups top-right, auto-expire, critical ones persist, action buttons supported |
| Launcher (`Launcher.qml`) | **SUPER + R**: type to filter, Tab or arrows to select, Enter to launch, Esc to close. Everyday apps only — control panels (anything in the freedesktop `Settings` category) live under the menu's Settings section |
| Tray, Volume, Icons, Polkit | System tray with left / middle / right click actions (`Tray.qml`), scrollable volume icon (`Volume.qml`), inline-SVG line icons and logo drawn in the theme's colours so no icon font is needed (`Icon.qml`, `Logo.qml`), and a full-screen polkit prompt that works with `pkexec` and anything else (`PolkitDialog.qml`) |

The shell is never run as root, and shouldn't be. Quickshell is a single process — the Security window is not separable from the bar, launcher and notification daemon — and it loads its QML from `~/.config/quickshell/`, which you can write. Privileged code must not sit on a path its own user can edit, which is why `hypora-security`, `hypora-console`, `hypora-hardware`, `hypora-grub`, `hypora-power` and `hypora-replace-de` are root-owned in `/usr/local/bin` and reached through pkexec. `hypora-security deep` deliberately re-reads none of your per-user settings, so running it as root can't substitute root's configuration for yours, and it reads firewalld's zone from `/etc/firewalld` directly rather than over D-Bus so that half can't raise a second prompt. Run `hypora-security status` to see exactly what it reads.

**Terminal tools** — `nmtui` (Network > Advanced), `bluetoothctl` (Bluetooth > Advanced) and `wiremix` (Sound > Advanced). All three ship with Fedora, so nothing extra is downloaded for them.

**Fonts and icons** — **JetBrainsMono Nerd Font** for monospace and the shell UI, **Liberation Sans / Serif** for the rest, set system-wide in `/etc/fonts/conf.d/50-hypora.conf`; **Papirus-Dark** icons, with GTK and gsettings set to match.

**Shell, editor and fetch**

- **zsh** with **Oh My Zsh**, tab completion (menu select, case-insensitive), autosuggestions and syntax highlighting. Set as your login shell; put your own additions in `~/.zshrc.local`, which Hypora never overwrites
- **eza** replaces `ls` (`ls`, `ll`, `la`, and `lt` for a two-level tree), with **file-type icons** from the bundled Nerd Font and **coloured from the active theme** rather than from eza's own palette: `hypora-theme` renders `EZA_COLORS` from the same `colors.toml` as everything else, so a listing matches the desktop and changes with it. Permission bits, sizes, owners and dates are each coloured by meaning. `\ls` still gets you coreutils, and if `eza` is missing the plain `ls` aliases stay
- **Neovim** with the **LazyVim** starter, its colorscheme following the active theme (`~/.config/nvim/lua/plugins/hypora.lua` is the only file Hypora owns there)
- **fastfetch** with a Hypora logo and a short readout: OS (as *Hypora Linux*, with the running kernel), host, CPU, GPU, RAM, WM, terminal, the active theme and the palette. Set `HYPORA_NO_FETCH=1` to stop it greeting new shells

**Desktop applications** — a handful of GNOME's apps without the GNOME session; none of them pull `gnome-shell`, `mutter`, `gnome-session` or `gdm`: Files (`nautilus`, with `gvfs` for trash, mounts and network shares), Calculator (`gnome-calculator`), Disks (`gnome-disk-utility`), Software (`gnome-software`, which manages flatpaks — use `dnf` for system packages), Calendar (`gnome-calendar`), Disk Usage Analyzer (`baobab`), Document Viewer (`papers`, or `evince` before Fedora's rename) and Document Scanner (`simple-scan`).

These are kept deliberately and **marked user-installed**, which is what stops `dnf autoremove` and [`hypora-replace-de`](docs/desktop.md#replacing-another-desktop) treating them as GNOME leftovers. GNOME Help (`yelp`) is removed instead: it documents a shell that isn't running.

One thing to know: **Nautilus hard-requires `localsearch`**, a background indexer that reads your home directory to make search work. It stays on the machine and talks to nothing over the network, but it is a daemon that reads your files. To see what it installed and mask it: `systemctl --user list-units '*localsearch*'`.

**Virtualization and network tools** — `@virtualization` (libvirt, QEMU/KVM, virt-manager) with `libvirtd` enabled and your user in the `libvirt` group, plus `nmap`, `aircrack-ng` and `wireshark`/`tshark` with your user in the `wireshark` group so captures work without root. Both group changes need a logout to take effect. `virt-viewer` is deliberately excluded from the group — its `remote-viewer` duplicated RustDesk below, and virt-manager has its own console for local VMs.

**Remote desktop** — **RustDesk**, as a Flathub flatpak that is publisher-verified via `rustdesk.com`. Chosen over the project's own RPM, which ships unsigned: a pinned hash there would prove the bytes hadn't changed since someone looked at them, but nothing about who built them. Being sandboxed, it reaches the screen and input through the desktop portals rather than the raw session.

**Why most packages stay native.** Flatpak sandboxing earns its keep for software that handles hostile input, which is why Firefox and Spotify are flatpaks. **Steam is native**, not a flatpak: the sandbox fights controller access and reaching game libraries stored outside it. That has a cost worth stating — native Steam comes from `rpmfusion-nonfree-steam`, so declining RPM Fusion means no Steam, where the flatpak would have worked. It does nothing for the rest: the compositor, shell, terminal and portals *are* the session and cannot sandbox themselves; `kitty` and `fastfetch` have no maintained Flathub build at all; the file manager and Disks need the host filesystem and `udisks` to be any use; and `nmap`, `aircrack-ng`, `wireshark` and `virt-manager` need raw sockets, capture privileges or host libvirt, so a sandboxed build would have to be handed the host anyway — paying the integration cost for none of the benefit.

**Optional, offered at the end of the install, both defaulting to no**

- **RPM Fusion** carries what Fedora won't ship — media codecs, NVIDIA's own driver, firmware for some Broadcom and Realtek chips. Answer ahead with `ENABLE_RPMFUSION=yes ./install.sh`. It is a different trust decision from the rest of Hypora: the release RPMs come over HTTPS from rpmfusion.org and can't be pinned to a fingerprint the way the Hyprland COPR and Anthropic's repository are, because both the package and its key change with every Fedora release. Packages from it are GPG-checked normally once it's enabled. Remove with `sudo dnf remove rpmfusion-free-release rpmfusion-nonfree-release`
- **Claude Code** comes from Anthropic's signed dnf repository (stable channel; `sudo dnf upgrade claude-code` to update) and needs a paid Claude plan. Answer ahead with `INSTALL_CLAUDE=yes ./install.sh`; a non-interactive run skips it, and a re-run detects an existing install rather than asking again. Run `claude` to log in; remove with `sudo dnf remove claude-code && sudo rm /etc/yum.repos.d/claude-code.repo`. The menu's **Tools > Claude Code** entry appears only when `claude` is on your `PATH`
- Nothing else AI-related is installed, and nothing is installed without asking

**Themes** — **Nord** (default), **Tokyo Night**, **Catppuccin Mocha**, **Gruvbox**, **Kanagawa**, **Osaka Jade**, **Hackerman** and **Cyberpunk**. A theme is one palette, `themes/<Name>/colors.toml`, applied everywhere: the Quickshell shell, kitty, Hyprland borders, hyprlock, GTK 3/4 (adw-gtk3 + libadwaita colours), Qt (qt6ct), the SDDM login screen, the Plymouth splash and the GRUB menu. Each theme's wallpapers live in `themes/<Name>/backgrounds/` and are copied to `~/.config/hypora/themes/<Name>/backgrounds/`; drop your own images in either place to add them to the rotation. Switch any time with the picker (**SUPER + ALT + T**) or `hypora-theme Gruvbox` (`hypora-theme` alone lists them). The shell, borders and terminals change immediately; other open apps pick it up when restarted.

## Keybindings

| Keys | Action |
|---|---|
| SUPER + Enter | Terminal |
| SUPER + B | Browser (Firefox, sandboxed as a flatpak) |
| SUPER + E | Files (Nautilus) |
| SUPER + R | App launcher |
| SUPER + A | Hypora menu |
| SUPER + ALT + T | Theme picker |
| SUPER + SHIFT + V | Clipboard history |
| SUPER + SHIFT + S | Screenshot a region |
| SUPER + L | Lock (also locks on its own after 10 minutes) |
| SUPER + M | Log out |
| SUPER + Q | Close window |
| SUPER + V | Toggle floating |
| SUPER + F | Fullscreen |
| SUPER + J | Toggle split |
| SUPER + P | Pseudo-tile |
| SUPER + S / SUPER + ALT + S | Show scratchpad / move window to it |
| SUPER + arrows | Move focus |
| SUPER + SHIFT + arrows | Send the focused window to the next monitor over, side to side or stacked above and below. Does nothing, quietly, when there is no screen that way — Hyprland would otherwise raise an error notification, which on a single-monitor machine is every press |
| SUPER + 1-0 / SUPER + SHIFT + 1-0 | Switch to / move window to workspace, on the monitor you're using |
| SUPER + scroll | Cycle this monitor's workspaces |
| SUPER + drag (left / right mouse) | Move / resize window |
| Volume / brightness / media keys | As labelled on the keyboard |

The programs behind these are set at the top of `config/hypr/hyprland.lua` (`terminal`, `browser`, `fileManager`). Every shortcut above can be rebound from **menu > Help > Keybindings**.

These follow Hyprland's own defaults wherever Hypora doesn't need the key. One deliberate difference: Hyprland puts *move window to scratchpad* on SUPER + SHIFT + S, which Hypora gives to the screenshot, so that moves to **SUPER + ALT + S**.

## Documentation

The reasoning behind each subsystem — what it does, why it is done that way, and what the trade-offs are — lives in `docs/`:

| Document | Covers |
|---|---|
| [Boot](docs/boot.md) | The GRUB menu, the Plymouth splash and the themed text console |
| [Storage](docs/storage.md) | btrfs snapshots with snapper, and why Hypora would rather you had no swap partition |
| [Network](docs/network.md) | Encrypted DNS, and per-network MAC randomization |
| [Power](docs/power.md) | Measuring what a laptop draws, and the profiles that reduce it |
| [Security](docs/security.md) | Keyring auto-unlock, firmware updates from LVFS, and automatic updates |
| [Hardware](docs/hardware.md) | Finding hardware that came up without a driver, firmware or radio |
| [Desktop](docs/desktop.md) | Workspaces and monitors, customizing, and replacing another desktop |

## Usage and testing

```bash
qs                          # run Quickshell manually to see QML errors in the terminal
notify-send "Test" "Hello"  # test notifications
pkexec true                 # test the polkit prompt
qs ipc call launcher toggle # open the launcher without the keybind
qs ipc call menu toggle     # open the app menu
qs ipc call display open    # open Display Settings
```

Don't run another notification daemon (Mako, dunst, swaync) or polkit agent alongside Quickshell. They will conflict with it.

## Repository layout

```
.
├── install.sh              # main installer
├── config/                 # copied into ~/.config
│   ├── hypr/               # hyprland.lua, hypridle.conf
│   ├── quickshell/         # the shell: bar, menu, control center, settings windows,
│   │                       # notifications, launcher, polkit prompt, theme picker, OSD
│   ├── kitty/              # terminal (colours come from the theme)
│   ├── zsh/zshrc           # -> ~/.zshrc
│   ├── fastfetch/          # config.jsonc and the hypora.txt ASCII logo
│   ├── nvim/               # the one LazyVim plugin file Hypora owns
│   └── uwsm/env            # session environment (Qt apps use qt6ct)
├── bin/
│   ├── hypora-theme        # applies a theme everywhere
│   ├── hypora-sysinfo      # RAM/CPU/GPU stats as JSON for the bar widget
│   ├── hypora-screenshot   # region / window / screen, saved and copied
│   ├── hypora-weather      # place search and forecast via Open-Meteo
│   ├── hypora-plymouth     # draws the boot screen's images in the current palette
│   ├── hypora-firmware     # checks LVFS and installs firmware updates
│   └── # root-owned, installed to /usr/local/bin:
│       ├── hypora-security # security status as JSON, and the root actions behind it
│       ├── hypora-console  # the theme's colours on the text console (kernel args)
│       ├── hypora-grub     # themes the GRUB boot menu from the active palette
│       ├── hypora-hardware # finds hardware with no driver, firmware or radio
│       ├── hypora-power    # measures battery draw and follows the charger
│       └── hypora-replace-de  # removes another desktop, keeping what Hypora needs
├── docs/                   # the subsystem documentation linked above, and images/
├── tools/gen-ascii-logo.py # regenerates the fastfetch ASCII logo from the mark
├── applications/           # .desktop entries -> ~/.local/share/applications
├── themes/
│   ├── <Name>/colors.toml  # palette (UI, terminal ANSI colours, GTK/icon theme)
│   ├── <Name>/backgrounds/ # that theme's wallpapers
│   └── templates/          # one per app; {{ key }} is filled from colors.toml
├── system/
│   ├── fontconfig/         # system font defaults -> /etc/fonts/conf.d/
│   ├── yum.repos.d/        # Claude Code repository -> /etc/yum.repos.d/
│   ├── systemd/            # DNS config, flatpak update timer, the plymouth drop-in
│   │                       # and the power units -> /etc/systemd/
│   ├── NetworkManager/     # systemd-resolved and MAC randomization -> conf.d/
│   ├── dnf/automatic.conf  # automatic security updates
│   └── sddm/               # login screen theme and session, installed by install.sh
└── LICENSE
```

## Known limitations

See [Alpha](#alpha) above for what is incomplete or actively broken. Beyond that:

- The Hyprland Lua config format is new; if something misbehaves after a Hyprland update, check `hyprctl configerrors` and the Hyprland wiki
- Hyprland comes from the third-party `sdegler/hyprland` COPR, so builds may lag behind or break after Fedora updates
- In a VM with no Wi-Fi or Bluetooth adapter, the Network and Bluetooth windows say so plainly rather than looking broken
- NetworkManager keeps Fedora's own Wi-Fi backend. An earlier version switched it to iwd so `impala` would work; both are gone, and re-running the installer puts a machine that took that switch back on the stock configuration
- Don't add a `qmldir` to `config/quickshell/`: it hides every component not listed in it (`Bar is not a type`). Quickshell finds `Theme.qml` on its own via `pragma Singleton`
- `~/.config/quickshell/Theme.qml`, `~/.config/kitty/current-theme.conf`, `~/.config/hypr/theme.lua`, `hyprlock.conf`, the GTK `gtk.css`/`settings.ini` and `qt6ct.conf` are links to files `hypora-theme` generates; edit the palette or templates instead, or your changes are lost on the next theme switch
- DNS-over-TLS is opportunistic, not strict, so a network blocking port 853 silently gets plaintext queries. Strict mode is a two-line change but breaks captive portals — see [DNS](docs/network.md#dns)
- MAC randomization changes each card's address once, which breaks existing DHCP reservations until they're updated — see [MAC addresses](docs/network.md#mac-addresses)
- Automatic updates only install packages Fedora tagged as security advisories, which misses fixes shipped as bugfix updates. Run `sudo dnf upgrade` periodically anyway
- Fedora versions tested: Fedora 44

## Reporting bugs

**Please file bugs and feature requests as [GitHub issues](https://github.com/misfitxtm/Hypora/issues).** That's the only place they're tracked, and the menu's **Help > Report a bug** opens the form directly.

What makes a report useful here:

- Which Fedora version, and whether it's bare metal or a VM
- The output of `hyprctl configerrors` if it's a compositor or keybind problem
- The output of `qs` run from a terminal if it's a shell problem — QML errors print there and nowhere else
- `hypora-security status` for anything in the Security window
- `journalctl -b -u <unit>` for a service that didn't start

## License

See [LICENSE](LICENSE).

## A note on AI assistance

The code here was written and reviewed by me, with help from [Claude Code](https://claude.com/claude-code). I decide what gets built and why, read every change before it lands, and test it on real hardware.

Either way, read the code rather than trust it. This is a desktop that configures your firewall, your DNS, your firmware updates and a helper that runs as root; the installer is plain shell and the shell layer is plain QML, both commented to explain *why* rather than *what*, specifically so that reading them is practical.
