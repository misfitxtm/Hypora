# Hypora

An [Omarchy](https://omarchy.org)-inspired Hyprland desktop for **Fedora**, installed with a single post-install script on top of a stock Fedora install (no custom ISO). The shell is built on [Quickshell](https://quickshell.org): a custom bar, control center, notification daemon and polkit prompt, all themeable from one palette file.

> **Status: early / work in progress.** The desktop shell and installer work for testing on a fresh install. The greetd login screen is written but untested, and is installed separately. See [Status](#status).

## Goals

- Omarchy's "install and it just looks good" experience, on Fedora instead of Arch
- A small, readable codebase: plain shell scripts and QML, no framework on top
- One place to change colors; everything reads from the active theme
- Deliberately minimal, with no bundled AI tooling

## What you get

**Desktop**
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
git clone <repo-url> ~/.local/share/hypora
cd ~/.local/share/hypora
./install.sh
```

Pick a different theme with the `THEME` variable (it must exist under `themes/`):

```bash
THEME=Nord ./install.sh
```

The installer is safe to re-run. It:

1. Checks you're on Fedora and not running as root
2. Enables the Hyprland and Quickshell COPRs only when the packages aren't already available
3. Installs required packages (warns and continues if an optional one is unavailable)
4. Enables `NetworkManager` and `upower`, and sets the default boot target to graphical
5. Points `~/.config/hypora/themes/current` at the chosen theme
6. **Symlinks** `config/hypr/hyprland.lua` and each file in `config/quickshell/` into `~/.config/`, and links `Theme.qml` from the current theme
7. Links any scripts in `bin/` into `~/.local/bin/`

Anything it replaces is saved as `<name>.bak.<timestamp>`.

Because configs are symlinks into the repo, **keep the repo where you cloned it**. Editing `~/.config/quickshell/*.qml` edits the repo directly, and Quickshell live-reloads on save.

### Starting the desktop

There's no login screen installed yet, so from a text console (TTY) run:

```bash
uwsm start hyprland-uwsm.desktop
```

(or plain `Hyprland` if you aren't using uwsm). Quickshell starts from the `hyprland.start` hook in `hyprland.lua`.

## Usage and testing

```bash
qs                          # run Quickshell manually to see QML errors in the terminal
notify-send "Test" "Hello"  # test notifications
pkexec true                 # test the polkit prompt
```

Don't run another notification daemon (Mako, dunst, swaync) or polkit agent alongside Quickshell. They will conflict with it.

## Repository layout

```
.
├── install.sh              # main installer
├── install-greeter.sh      # greeter installer (run separately)
├── config/                 # symlinked into ~/.config
│   ├── hypr/hyprland.lua
│   └── quickshell/         # shell.qml, Bar, ControlCenter, Tray, Volume, Network,
│                           # Battery, Notifications, PolkitDialog, Slider, PowerButton, qmldir
├── themes/
│   ├── Nord/Theme.qml      # palette, font, app defaults
│   └── TokyoNight/Theme.qml
├── system/
│   └── greetd/             # root-owned files for the greeter, installed to /etc/greetd/
│       ├── config.toml
│       ├── hyprland.lua    # minimal session that hosts the greeter
│       └── quickshell/     # greeter shell.qml + qmldir (PowerButton and Theme come from elsewhere)
├── bin/                    # helper scripts, linked to ~/.local/bin (empty for now)
├── packages/               # planned: package lists read by the installer
├── install/                # planned: modular install steps
└── src/
```

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

In progress / planned:
- Quickshell-based **greetd greeter** (login screen): written (`system/greetd/`, `install-greeter.sh`) but untested, and not part of `install.sh`
- Runtime theme switching (`theme-set`) that reloads apps and syncs the greeter
- Package lists in `packages/*.txt` and a modular `install/` directory
- Brightness control in the control center

## Known limitations

- Developed and tested in a VM so far; real hardware (GPU, laptop battery and backlight) is less tested
- The Hyprland Lua config format is new; if something misbehaves after a Hyprland update, check `hyprctl configerrors` and the Hyprland wiki
- The Quickshell COPR is a third-party dependency, so builds may lag behind or break after Fedora updates
- Fedora versions tested: _fill in_

## License

See [LICENSE](LICENSE).
