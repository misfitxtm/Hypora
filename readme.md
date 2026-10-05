# Hypora

An [Omarchy](https://omarchy.org)-inspired Hyprland desktop for **Fedora**, installed with a single post-install script on top of a stock Fedora install (no custom ISO). The shell is built on [Quickshell](https://quickshell.org): a custom bar, control center, notification daemon and polkit prompt, all themeable from one palette file.

> **Status: early / work in progress.** The desktop shell, installer and SDDM login screen are ready for testing on a fresh install. See [Status](#status).

## Goals

- Omarchy's "install and it just looks good" experience, on Fedora instead of Arch
- A small, readable codebase: plain shell scripts and QML, no framework on top
- One place to change colors; the Quickshell shell reads everything from the active theme
- Ships Claude Code and Hermes Agent out of the box

## What you get

**Desktop**
- A minimal SDDM login screen (the same setup Omarchy uses) with the Hypora logo, following the active theme
- Hyprland, started through `uwsm`
- Quickshell as the shell layer (replaces Waybar, Mako and a standalone polkit agent)

**Quickshell components** (`config/quickshell/`)

| Component | What it does |
|---|---|
| Bar (`Bar.qml`) | Top bar on every monitor: Hypora menu button, workspaces 1-9, clock, tray and status icons (network, volume, battery, Do Not Disturb) |
| App menu (`AppMenu.qml`, `AppMenuPanel.qml`) | ArcMenu-style menu from the Hypora logo at the top left: app search, categories and all installed apps, plus a sidebar with places (Home, Documents, ...), settings (Display, Network, Bluetooth, Sound, Terminal) and session buttons |
| Control center (`ControlCenter.qml`, `ControlPanel.qml`) | GNOME/macOS-style quick settings: click the status icons at the top right. Lock / Log out / Restart / Power off (the last three ask for a second click), volume and brightness sliders, power mode (Saver / Balanced / Performance), and Wi-Fi, Bluetooth, Do Not Disturb and Night Light tiles. The arrows and the mixer button open the TUIs below |
| Display Settings (`DisplaySettings.qml`) | Resolution, refresh rate, scale, rotation, position and on/off per monitor. Changes apply live and revert after 15 seconds unless you keep them; kept settings go to `~/.config/hypr/monitors.lua` |
| Workspaces | Click to switch; highlights the focused workspace and dims empty ones |
| Volume (`Volume.qml`) | PipeWire volume icon in the bar. Scroll over it to change the volume |
| Network (`Network.qml`, `Net.qml`) | Wi-Fi (with signal strength) / Ethernet icon from NetworkManager; updates live via `nmcli monitor`. The Wi-Fi tile's arrow opens `impala` |
| Tray (`Tray.qml`) | System tray: left click activates, middle click secondary action, right click menu |
| Battery (`Battery.qml`) | Icon and percentage, laptops only; turns red when low |
| Icons (`Icon.qml`, `Logo.qml`) | Line icons and the Hypora logo, drawn from inline SVG in the theme colors, so no icon font is needed |
| Notifications (`Notifications.qml`) | Quickshell *is* the notification daemon: popups top-right, auto-expire, critical ones persist, action buttons supported |
| Launcher (`Launcher.qml`) | App launcher on **SUPER + R**: type to filter installed apps, Up/Down or Tab to select, Enter to launch, Esc to close |
| Polkit (`PolkitDialog.qml`) | Full-screen authentication prompt (works with `pkexec` and other polkit requests) |

**Terminal tools** (the same ones Omarchy has used)

| Tool | For | Opened from |
|---|---|---|
| `impala` | Wi-Fi (needs iwd; falls back to `nmtui`) | Wi-Fi tile arrow, menu > Network |
| `bluetui` | Bluetooth devices | Bluetooth tile arrow, menu > Bluetooth |
| `wiremix` | Sound outputs, inputs and per-app volume | Mixer button in the control center, menu > Sound |

**Fonts and icons**
- **JetBrainsMono Nerd Font** for monospace and the shell UI, with **Liberation Sans / Serif** for the rest, the same defaults Omarchy uses. Set system-wide in `/etc/fonts/conf.d/50-hypora.conf`
- **Papirus-Dark** icons for apps, the launcher and the app menu (GTK settings and gsettings are set to match)

**AI tools**
- **Claude Code** from Anthropic's signed dnf repository (stable channel; `sudo dnf upgrade claude-code` to update). Run `claude` to log in
- **Hermes Agent** (Nous Research), installed per-user under `~/.hermes` with its official script. Run `hermes setup` to pick a model provider

**Theming**
- `themes/<Name>/Theme.qml` holds the palette, font and a few app defaults (terminal and the TUIs above)
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
3. Installs required packages (warns and continues if an optional one is unavailable): PipeWire with wiremix, BlueZ, iwd, tuned-ppd for power modes, and downloads impala and bluetui into `/usr/local/bin`
4. Installs JetBrainsMono Nerd Font, sets the system font defaults, and installs Claude Code (adds `/etc/yum.repos.d/claude-code.repo` after checking the signing key's fingerprint) and Hermes Agent
5. Enables NetworkManager, upower, bluetooth and power profiles, switches NetworkManager's Wi-Fi backend to iwd (after the next reboot), and sets the default boot target to graphical
6. Points `~/.config/hypora/themes/current` at the chosen theme
7. **Copies** `config/hypr/hyprland.lua`, `config/quickshell/`, the GTK settings and the themes into `~/.config/`, and `applications/*.desktop` (e.g. Display Settings) into `~/.local/share/applications/`
8. Installs the SDDM login theme (colors generated from the chosen theme), disables GDM/LightDM/greetd and enables SDDM
9. Copies any scripts in `bin/` into `~/.local/bin/`

Anything it replaces that you had changed is saved as `<name>.bak.<timestamp>`.

Configs are **copies**, so the clone can be moved or deleted after installing. To update, `git pull` (or clone again) and re-run `./install.sh`. It records a checksum of every file it installs: files you haven't touched are updated quietly, files you edited are saved as `<name>.bak.<timestamp>` before being replaced, and files Hypora no longer ships are removed (unless you edited them). Quickshell live-reloads when you edit `~/.config/quickshell/*.qml`.

### Starting the desktop

Reboot. SDDM shows the Hypora login screen (logo and password box, styled after Omarchy's) and starts the **Hyprland (uwsm-managed)** session. On machines with more than one user, the name appears above the box; click it or press Up/Down to switch.

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
qs ipc call menu toggle     # open the app menu
qs ipc call display open    # open Display Settings
```

Don't run another notification daemon (Mako, dunst, swaync) or polkit agent alongside Quickshell. They will conflict with it.

## Repository layout

```
.
├── install.sh              # main installer
├── config/                 # copied into ~/.config
│   ├── hypr/hyprland.lua
│   ├── quickshell/         # shell.qml, Bar, ControlCenter, Tray, Volume, Network,
│   │                       # Battery, Notifications, PolkitDialog, Launcher, ControlPanel, Tile,
│   │                       # AppMenu, AppMenuPanel, Apps, Dropdown, DisplaySettings, Logo,
│   │                       # Icon, Net, ShellState, Slider, PowerButton
│   └── gtk-3.0, gtk-4.0/   # icon theme and dark preference
├── applications/           # .desktop entries copied into ~/.local/share/applications
├── themes/
│   ├── Nord/Theme.qml      # palette, font, app defaults
│   └── TokyoNight/Theme.qml
├── system/
│   ├── fontconfig/         # system font defaults -> /etc/fonts/conf.d/
│   ├── yum.repos.d/        # Claude Code repository -> /etc/yum.repos.d/
│   └── sddm/               # login screen, installed by install.sh
│       ├── 10-hypora.conf  # -> /etc/sddm.conf.d/ (Wayland greeter on Hyprland, hypora theme)
│       ├── hyprland.lua    # minimal Hyprland session that hosts the greeter
│       └── hypora/         # SDDM theme -> /usr/share/sddm/themes/hypora/
└── LICENSE
```

Not created yet: `bin/` (helper scripts; `install.sh` links anything placed there into `~/.local/bin/`), `packages/` and `install/` (see [Status](#status)).

## Customizing

- **Colors and font:** edit `themes/Nord/Theme.qml`, or copy the folder to `themes/<NewName>/` and install with `THEME=<NewName>`
- **Terminal and TUIs launched by widgets:** `terminal`, `mixer`, `network` and `bluetooth` in `Theme.qml`
- **Autostart, keybinds:** `config/hypr/hyprland.lua`
- **Monitors:** Display Settings, or edit `~/.config/hypr/monitors.lua` (loaded by `hyprland.lua`)
- **Bar contents:** `Bar.qml` (the right-hand `Row` holds the tray and the control center button)
- **Control center:** `ControlPanel.qml` (tiles are `Tile {}` items in the `GridLayout`)
- **App menu sidebar:** the `SidebarItem` entries in `AppMenuPanel.qml`

## Status

Working:
- Installer for packages, services, theme and config links
- Quickshell bar, app menu, control center, display settings, tray, volume, network, battery, notifications and polkit prompt
- Hyprland Lua config with keybinds, Nord-style borders and Quickshell autostart
- SDDM login screen (needs testing on real hardware)

In progress / planned:
- Runtime theme switching (`theme-set`) that reloads apps and syncs the login screen
- Package lists in `packages/*.txt` and a modular `install/` directory

## Known limitations

- Developed and tested in a VM so far; real hardware (GPU, laptop battery and backlight) is less tested
- Hyprland window borders are hardcoded to Nord colors in `hyprland.lua` and don't follow the selected theme yet
- The Hyprland Lua config format is new; if something misbehaves after a Hyprland update, check `hyprctl configerrors` and the Hyprland wiki
- Hyprland comes from the third-party `sdegler/hyprland` COPR, so builds may lag behind or break after Fedora updates
- impala needs iwd: the installer switches NetworkManager's Wi-Fi backend to iwd. If Wi-Fi misbehaves, delete `/etc/NetworkManager/conf.d/hypora-iwd.conf`, run `sudo systemctl enable wpa_supplicant`, and reboot (`nmtui` then works as before)
- Don't add a `qmldir` to `config/quickshell/`: it hides every component not listed in it (`Bar is not a type`). Quickshell finds `Theme.qml` on its own via `pragma Singleton`
- Fedora versions tested: _fill in_

## License

See [LICENSE](LICENSE).
