# Hypora

An [Omarchy](https://omarchy.org)-inspired Hyprland desktop for **Fedora**, installed with a single post-install script on top of a stock Fedora install (no custom ISO). The shell is built on [Quickshell](https://quickshell.org): a custom bar, control center, notification daemon and polkit prompt, all themeable from one palette file.

> **Status: early / work in progress.** The desktop shell, installer and SDDM login screen are ready for testing on a fresh install. See [Status](#status).

## Goals

- Omarchy's "install and it just looks good" experience, on Fedora instead of Arch
- A small, readable codebase: plain shell scripts and QML, no framework on top
- One place to change colors; the Quickshell shell reads everything from the active theme
- Deliberately minimal, with no bundled AI tooling

## What you get

**Desktop**
- A minimal SDDM login screen (the same approach Omarchy uses) that follows the active theme
- Hyprland, started through `uwsm`
- Quickshell as the shell layer (replaces Waybar, Mako and a standalone polkit agent)

**Quickshell components** (`config/quickshell/`)

| Component | What it does |
|---|---|
| Bar (`Bar.qml`) | Top bar on every monitor: control center button, workspaces 1-9, clock, status area |
| Control center (`ControlCenter.qml`) | Dropdown from the button left of workspace 1: volume slider and mute, network status, Lock / Logout / Reboot / Off (the last three ask for a second click to confirm) |
| Workspaces | Click to switch; highlights the focused workspace and dims empty ones |
| Volume (`Volume.qml`) | PipeWire volume in the bar. Scroll to change, left click to mute, right click opens the mixer |
| Network (`Network.qml`) | Wi-Fi / Ethernet status via NetworkManager (`nmcli`). Click opens `nmtui` |
| Tray (`Tray.qml`) | System tray: left click activates, middle click secondary action, right click menu |
| Battery (`Battery.qml`) | Shown on laptops only, turns red when low |
| Notifications (`Notifications.qml`) | Quickshell *is* the notification daemon: popups top-right, auto-expire, critical ones persist, action buttons supported |
| Launcher (`Launcher.qml`) | App launcher on **SUPER + R**: type to filter installed apps, Up/Down or Tab to select, Enter to launch, Esc to close |
| Polkit (`PolkitDialog.qml`) | Full-screen authentication prompt (works with `pkexec` and other polkit requests) |

**Theming**
- `themes/<Name>/Theme.qml` holds the palette, font and a few app defaults (terminal, mixer)
- Included themes: **Nord**, **TokyoNight**

## Requirements

- A fresh **Fedora** install (a minimal / Everything netinstall is a good base)
- An internet connection and a user with `sudo`
- **Hyprland 0.55 or newer**: the config is written in Lua (`hyprland.lua`), which replaces the deprecated `hyprland.conf` format
- A Quickshell build with the PipeWire, system tray, notifications, UPower and polkit modules. The installer enables COPRs if the packages aren't in the main repos; check that they are current for your Fedora version

## Install

```bash
git clone https://github.com/misfitxtm/Hypora.git ~/.local/share/hypora
cd ~/.local/share/hypora
./install.sh
```

Pick a different theme with the `THEME` variable (it must exist under `themes/`):

```bash
THEME=Nord ./install.sh
```

The installer is safe to re-run. It:

1. Checks you're on Fedora and not running as root
2. Enables the `sdegler/hyprland` COPR (Fedora doesn't package Hyprland or uwsm) and checks Hyprland is 0.55+
3. Installs required packages (warns and continues if an optional one is unavailable)
4. Enables `NetworkManager` and `upower`, and sets the default boot target to graphical
5. Points `~/.config/hypora/themes/current` at the chosen theme
6. **Symlinks** `config/hypr/hyprland.lua` and each file in `config/quickshell/` into `~/.config/`, and links `Theme.qml` from the current theme
7. Installs the SDDM login theme (colors generated from the chosen theme), disables GDM/LightDM/greetd and enables SDDM
8. Links any scripts in `bin/` into `~/.local/bin/`

Anything it replaces is saved as `<name>.bak.<timestamp>`.

Because configs are symlinks into the repo, **keep the repo where you cloned it**. Editing `~/.config/quickshell/*.qml` edits the repo directly, and Quickshell live-reloads on save.

### Starting the desktop

Reboot. SDDM shows the Hypora login screen and starts the **Hyprland (uwsm-managed)** session. Click your name (or press Up/Down) to switch users.

Without the login screen, start it from a text console (TTY) with `uwsm start hyprland-uwsm.desktop` (or `start-hyprland`). Quickshell starts from the `hyprland.start` hook in `hyprland.lua` either way.

## Keybindings

| Keys | Action |
|---|---|
| SUPER + Enter | Terminal |
| SUPER + R | App launcher |
| SUPER + C | Close window |
| SUPER + V | Toggle floating |
| SUPER + L | Lock (hyprlock) |
| SUPER + M | Log out |
| SUPER + arrows | Move focus |
| SUPER + 1-0 / SUPER + SHIFT + 1-0 | Switch to / move window to workspace |
| SUPER + drag (left / right mouse) | Move / resize window |

## Usage and testing

```bash
qs                          # run Quickshell manually to see QML errors in the terminal
notify-send "Test" "Hello"  # test notifications
pkexec true                 # test the polkit prompt
qs ipc call launcher toggle # open the launcher without the keybind
```

Don't run another notification daemon (Mako, dunst, swaync) or polkit agent alongside Quickshell. They will conflict with it.

## Repository layout

```
.
├── install.sh              # main installer
├── config/                 # symlinked into ~/.config
│   ├── hypr/hyprland.lua
│   └── quickshell/         # shell.qml, Bar, ControlCenter, Tray, Volume, Network,
│                           # Battery, Notifications, PolkitDialog, Launcher, Slider, PowerButton
├── themes/
│   ├── Nord/Theme.qml      # palette, font, app defaults
│   └── TokyoNight/Theme.qml
├── system/
│   └── sddm/               # login screen, installed by install.sh
│       ├── 10-hypora.conf  # -> /etc/sddm.conf.d/ (Wayland greeter on Hyprland, hypora theme)
│       ├── hyprland.lua    # minimal Hyprland session that hosts the greeter
│       └── hypora/         # SDDM theme -> /usr/share/sddm/themes/hypora/
└── LICENSE
```

Not created yet: `bin/` (helper scripts; `install.sh` links anything placed there into `~/.local/bin/`), `packages/` and `install/` (see [Status](#status)).

## Customizing

- **Colors and font:** edit `themes/Nord/Theme.qml`, or copy the folder to `themes/<NewName>/` and install with `THEME=<NewName>`
- **Terminal and mixer launched by widgets:** `terminal` and `mixer` in `Theme.qml`
- **Autostart, keybinds, monitors:** `config/hypr/hyprland.lua`
- **Bar contents:** `Bar.qml` (the right-hand `Row` holds tray, network, volume and battery)

## Status

Working:
- Installer for packages, services, theme and config links
- Quickshell bar, control center, tray, volume, network, battery, notifications and polkit prompt
- Hyprland Lua config with keybinds, Nord-style borders and Quickshell autostart
- SDDM login screen (needs testing on real hardware)

In progress / planned:
- Runtime theme switching (`theme-set`) that reloads apps and syncs the login screen
- Package lists in `packages/*.txt` and a modular `install/` directory
- Brightness control in the control center

## Known limitations

- Developed and tested in a VM so far; real hardware (GPU, laptop battery and backlight) is less tested
- Hyprland window borders are hardcoded to Nord colors in `hyprland.lua` and don't follow the selected theme yet
- The Hyprland Lua config format is new; if something misbehaves after a Hyprland update, check `hyprctl configerrors` and the Hyprland wiki
- Hyprland comes from the third-party `sdegler/hyprland` COPR, so builds may lag behind or break after Fedora updates
- Don't add a `qmldir` to `config/quickshell/`: it hides every component not listed in it (`Bar is not a type`). Quickshell finds `Theme.qml` on its own via `pragma Singleton`
- Fedora versions tested: _fill in_

## License

See [LICENSE](LICENSE).
