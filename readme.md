# Hypora

A **privacy-focused Hyprland desktop for Fedora**, installed with a single post-install script on top of a stock Fedora install (no custom ISO). The shell is built on [Quickshell](https://quickshell.org): a custom bar, control center, notification daemon and polkit prompt, all themeable from one palette file.

Privacy here means specific things, not a slogan:

- **Nothing phones home.** No telemetry, no analytics, no update pings of our own.
- **The weather widget never geolocates you.** You pick a city by name; only that name is sent, and until you pick one no weather request is made at all.
- **AI tooling is opt-in.** The installer asks before installing Claude Code, and the default answer is no.
- **Your security state is visible and adjustable** — Secure Boot, firmware checks, SELinux, camera, microphone, location and file history all in one window, with each switch saying plainly what it does and does not cover.
- **Flatpak apps come with the tools to audit them:** Flatseal for permissions, Warehouse for what's installed and what data it left behind.
- **Secrets stay out of argv and privileged paths stay out of `$HOME`.** Wi-Fi passwords are handed to `nmcli` on stdin, never as a command-line argument that any process could read from `/proc`; the one helper that runs as root lives in a root-owned directory.

> **Status: early / work in progress.** The desktop shell, installer and SDDM login screen are ready for testing on a fresh install. See [Status](#status).

## Goals

- An "install it and it just looks good" experience on Fedora, without giving up control of it
- A small, readable codebase: plain shell scripts and QML, no framework on top
- One place to change colors; the Quickshell shell reads everything from the active theme
- Optional AI tooling: Claude Code, offered during install but never assumed

## What you get

**Desktop**
- A minimal SDDM login screen: the time, the date and a password field, in the active theme's colors
- Hyprland, started through `uwsm`
- Quickshell as the shell layer (replaces Waybar, Mako and a standalone polkit agent)

**Quickshell components** (`config/quickshell/`)

| Component | What it does |
|---|---|
| Bar (`Bar.qml`) | Top bar on every monitor: Hypora menu button, workspaces 1-9, clock, tray and status icons (network, volume, battery, Do Not Disturb) |
| Menu (`AppMenu.qml`, `AppMenuPanel.qml`) | Menu from the Hypora logo at the top left. Five sections: **Apps**, **Style** (Theme, Next wallpaper), **Settings** (Display, Network, Bluetooth, Sound, plus any control panels installed), **Security**, **Tools** (Terminal, Claude Code, region screenshot) and **Help** (Keybindings). Enter or Right opens a section; Esc or Left goes back; typing searches apps. Power actions are in the control center |
| Security (`SecuritySettings.qml`) | Menu > Security. **Device Security**: whether Secure Boot is on, and fwupd's firmware checks (the HSI level, how many passed, and which didn't). **SELinux**: the running mode and the one set for next boot, switchable between Enforcing and Permissive. **Hardware**: camera (unloads the `uvcvideo` driver) and microphone (mutes it in PipeWire). **Privacy**: location (masks GeoClue) and GTK file history, with a Clear button. Readings and root actions go through `hypora-security`, installed to `/usr/local/bin` and owned by root — pkexec runs it as root, so it must not sit anywhere you could write. Run `hypora-security status` to see exactly what it reads |
| Keyboard shortcuts (`KeybindHelp.qml`) | Menu > Help > Keybindings: every shortcut, grouped, and click one to rebind it — press the new combination and it's saved. Changes go to `~/.config/hypr/keybinds.lua`, which `hyprland.lua` merges over its defaults, then Hyprland reloads. Delete that file (or use **Reset all**) to go back to stock |
| Theme picker (`ThemePicker.qml`) | **SUPER + ALT + T** (or menu > Settings > Theme): a card per installed theme with its wallpaper, a miniature desktop in its colors and its palette. Arrows to choose, Enter or click to apply |
| Wallpaper (`Wallpaper.qml`) | Draws the wallpaper on every monitor, cross-fading between images. Each theme has three; cycle with menu > Settings > **Next wallpaper** (or `qs ipc call wallpaper next`). Your choice is remembered |
| Weather (`Weather.qml`) | To the left of the clock: current conditions and a three-day forecast. Pick your city by name — there is no IP geolocation, and nothing is requested until you choose a place. Data from [Open-Meteo](https://open-meteo.com), which needs no account or API key. Your choice lives in `~/.config/hypora/weather.json`; `bin/hypora-weather` does the lookups and can be run on its own |
| Clipboard (`Clipboard.qml`) | Clipboard history to the left of the clock, also on **SUPER + SHIFT + V**: recent copies, click one to put it back on the clipboard, or Clear to wipe it. Recorded by `wl-paste --watch cliphist store` (started from `hyprland.lua`) — Quickshell can't watch the clipboard itself, as it doesn't speak `wlr-data-control` |
| Clock and calendar (`Clock.qml`, `CalendarPanel.qml`) | Click the clock in the middle of the bar: time, date and a month calendar. Arrows or scrolling change the month; click the month name to jump back to today |
| System usage (`SystemUsage.qml`, `SysInfo.qml`) | Live RAM %, CPU %, CPU temperature and, on machines that report them, GPU usage and GPU temperature — left of the control center. Readings warm to the accent colour and then to red as they climb. Click it to pick which ones appear; the choice is kept in `~/.config/hypora/sysinfo.json`. Numbers come from `bin/hypora-sysinfo` (/proc and /sys, or `nvidia-smi` for NVIDIA) |
| Control center (`ControlCenter.qml`, `ControlPanel.qml`) | Quick settings: click the status icons at the top right. Lock / Log out / Restart / Power off (the last three ask for a second click), volume and brightness sliders, power mode (Saver / Balanced / Performance), and Wi-Fi, Bluetooth, Do Not Disturb and Night Light tiles. The arrows and the mixer button open the TUIs below |
| Network (`NetworkSettings.qml`) | Wi-Fi on/off, nearby networks with signal strength, connect (asking for a password when it's a new secured network), disconnect and forget. No terminal needed |
| Bluetooth (`BluetoothSettings.qml`) | Power and scanning, pair, connect, disconnect and forget, with device battery where reported |
| Display Settings (`DisplaySettings.qml`) | Resolution, refresh rate, scale, rotation, position and on/off per monitor. Changes apply live and revert after 15 seconds unless you keep them; kept settings go to `~/.config/hypr/monitors.lua` |
| Workspaces | Click to switch; highlights the focused workspace and dims empty ones |
| Volume (`Volume.qml`) | PipeWire volume icon in the bar. Scroll over it to change the volume |
| Network (`Network.qml`, `Net.qml`) | Wi-Fi (with signal strength) / Ethernet icon from NetworkManager; updates live via `nmcli monitor`. The Wi-Fi tile's arrow opens `impala` |
| Tray (`Tray.qml`) | System tray: left click activates, middle click secondary action, right click menu |
| Battery (`Battery.qml`) | Icon and percentage, laptops only; turns red when low |
| Icons (`Icon.qml`, `Logo.qml`) | Line icons and the Hypora logo, drawn from inline SVG in the theme colors, so no icon font is needed |
| Notifications (`Notifications.qml`) | Quickshell *is* the notification daemon: popups top-right, auto-expire, critical ones persist, action buttons supported |
| Launcher (`Launcher.qml`) | App launcher on **SUPER + R**: type to filter installed apps, Up/Down or Tab to select, Enter to launch, Esc to close. Shows everyday apps only — control panels (anything in the freedesktop `Settings` category, such as qt6ct) live under the menu's Settings section instead |
| Polkit (`PolkitDialog.qml`) | Full-screen authentication prompt (works with `pkexec` and other polkit requests) |

**Terminal tools**

| Tool | For | Opened from |
|---|---|---|
| `impala` | Wi-Fi, advanced (needs iwd; falls back to `nmtui`) | Network window > Advanced |
| `bluetui` | Bluetooth, advanced | Bluetooth window > Advanced |
| `wiremix` | Sound outputs, inputs and per-app volume | Mixer button in the control center, menu > Sound |

Network and Bluetooth have proper Quickshell windows (above); the `impala` and `bluetui` TUIs are still one click away under "Advanced..." in each.

**Fonts and icons**
- **JetBrainsMono Nerd Font** for monospace and the shell UI, with **Liberation Sans / Serif** for the rest. Set system-wide in `/etc/fonts/conf.d/50-hypora.conf`
- **Papirus-Dark** icons for apps, the launcher and the app menu (GTK settings and gsettings are set to match)

**AI tools**
- **Claude Code**, *optional*: the installer asks, and the default answer is no. Answer ahead of time with `INSTALL_CLAUDE=yes ./install.sh` (or `=no`); a non-interactive run skips it. It comes from Anthropic's signed dnf repository (stable channel; `sudo dnf upgrade claude-code` to update) and needs a paid Claude plan. Run `claude` to log in, and remove it with `sudo dnf remove claude-code && sudo rm /etc/yum.repos.d/claude-code.repo`
- Nothing else AI-related is installed, and nothing is installed without asking

**Shell, editor and fetch**
- **zsh** with **Oh My Zsh**, tab completion (menu select, case-insensitive), **autosuggestions** and **syntax highlighting**. Set as your login shell; put your own additions in `~/.zshrc.local`, which Hypora never overwrites
- **Neovim** with the **LazyVim** starter. Its colorscheme follows the active Hypora theme (`~/.config/nvim/lua/plugins/hypora.lua` is the only file Hypora owns there)
- **fastfetch** with a Hypora logo and a short readout: OS (shown as *Hypora Linux* with the running kernel), host, CPU, GPU, RAM, WM, terminal, the active theme and the color palette. It greets you in new shells; set `HYPORA_NO_FETCH=1` to turn that off

**Virtualization and network tools**
- `@virtualization` (libvirt, QEMU/KVM, virt-manager), with `libvirtd` enabled and your user added to the `libvirt` group
- `nmap`, `aircrack-ng` and `wireshark`/`tshark`, with your user added to the `wireshark` group so captures work without root. Both group changes need a logout to take effect

**Themes**
- Included: **Nord** (default), **Tokyo Night** and **Catppuccin Mocha**
- A theme is one palette, `themes/<Name>/colors.toml`, applied everywhere: the Quickshell shell, kitty, Hyprland window borders, the hyprlock lock screen, GTK 3/4 apps (adw-gtk3 + libadwaita colors), Qt apps (qt6ct) and the SDDM login screen
- Each theme comes with three **pixel-art wallpapers drawn from its own palette** by `hypora-wallgen` (peaks, city and grove), so a new theme gets matching wallpapers for free. They land in `~/.config/hypora/themes/<Name>/backgrounds/`; drop your own images in that folder to add them to the rotation
- Switch any time with the theme picker (**SUPER + ALT + T**) or `hypora-theme TokyoNight` (`hypora-theme` alone lists themes). The shell, borders and terminals change immediately; other open apps pick it up when restarted

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

Pick a theme with the `THEME` variable (it must exist under `themes/`). Re-runs keep the theme you last chose with `hypora-theme`:

```bash
THEME=TokyoNight ./install.sh
```

The installer is safe to re-run. It:

1. Checks you're on Fedora and not running as root
2. Enables the `sdegler/hyprland` COPR (Fedora doesn't package Hyprland or uwsm) and checks Hyprland is 0.55+
3. Installs required packages (warns and continues if an optional one is unavailable): PipeWire with wiremix, BlueZ, iwd, tuned-ppd for power modes, zsh, Neovim, fastfetch, the `@virtualization` group (libvirt, QEMU/KVM, virt-manager), network and security tools (nmap, aircrack-ng, wireshark/tshark), and downloads impala and bluetui into `/usr/local/bin`
4. Installs Oh My Zsh and the LazyVim starter, and makes zsh your login shell (an existing `~/.config/nvim` is left alone)
5. Installs JetBrainsMono Nerd Font and sets the system font defaults, then **asks** whether to install Claude Code (default no)
6. Enables NetworkManager, upower, bluetooth and power profiles, switches NetworkManager's Wi-Fi backend to iwd on machines that have a Wi-Fi radio (taking effect at the next reboot), and sets the default boot target to graphical
7. Installs the theme palettes and templates into `~/.config/hypora/` and applies the chosen theme with `hypora-theme`
8. **Copies** `config/hypr/hyprland.lua`, `config/quickshell/`, the GTK settings and the themes into `~/.config/`, and `applications/*.desktop` (e.g. Display Settings) into `~/.local/share/applications/`
9. Installs the SDDM login theme (colors generated from the chosen theme), disables GDM/LightDM/greetd and enables SDDM
10. Copies the scripts in `bin/` (such as `hypora-theme`) into `~/.local/bin/`

Anything it replaces that you had changed is saved as `<name>.bak.<timestamp>`.

Configs are **copies**, so the clone can be moved or deleted after installing. To update, `git pull` (or clone again) and re-run `./install.sh`. It records a checksum of every file it installs: files you haven't touched are updated quietly, files you edited are saved as `<name>.bak.<timestamp>` before being replaced, and files Hypora no longer ships are removed (unless you edited them). Quickshell live-reloads when you edit `~/.config/quickshell/*.qml`.

### Starting the desktop

Reboot. SDDM shows the Hypora login screen and starts the **Hyprland (uwsm-managed)** session. On machines with more than one user, the name appears above the box; click it or press Up/Down to switch.

Without the login screen, start it from a text console (TTY) with `uwsm start hyprland-uwsm.desktop` (or `start-hyprland`). Quickshell starts from the `hyprland.start` hook in `hyprland.lua` either way.

## Keybindings

| Keys | Action |
|---|---|
| SUPER + Enter | Terminal |
| SUPER + B | Browser (Firefox) |
| SUPER + E | Files (Thunar) |
| SUPER + R | App launcher |
| SUPER + A | Hypora menu |
| SUPER + ALT + T | Theme picker |
| SUPER + SHIFT + V | Clipboard history |
| SUPER + SHIFT + S | Screenshot a region |
| SUPER + L | Lock |
| SUPER + M | Log out |
| SUPER + Q | Close window |
| SUPER + V | Toggle floating |
| SUPER + F | Fullscreen |
| SUPER + J | Toggle split |
| SUPER + P | Pseudo-tile |
| SUPER + S / SUPER + ALT + S | Show scratchpad / move window to it |
| SUPER + arrows | Move focus |
| SUPER + 1-0 / SUPER + SHIFT + 1-0 | Switch to / move window to workspace |
| SUPER + scroll | Cycle workspaces |
| SUPER + drag (left / right mouse) | Move / resize window |
| Volume / brightness / media keys | As labelled on the keyboard |

The programs behind these are set at the top of `config/hypr/hyprland.lua` (`terminal`, `browser`, `fileManager`). Every shortcut above can be rebound from **menu > Help > Keybindings**.

These follow Hyprland's own defaults wherever Hypora doesn't need the key. One deliberate difference: Hyprland puts *move window to scratchpad* on SUPER + SHIFT + S, which Hypora gives to the screenshot, so that moves to **SUPER + ALT + S**.

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
│   │                       # Clock, CalendarPanel, ThemePicker, Wallpaper,
│   │                       # SystemUsage, SysInfo, NetworkSettings, BluetoothSettings,
│   │                       # KeybindHelp, Clipboard, SecuritySettings, Weather,
│   │                       # Icon, Net, ShellState, Slider, PowerButton
│   ├── kitty/kitty.conf    # terminal (colors come from the theme)
│   ├── zsh/zshrc           # -> ~/.zshrc
│   ├── fastfetch/          # config.jsonc and the hypora.txt ASCII logo
│   ├── nvim/               # the one LazyVim plugin file Hypora owns
│   └── uwsm/env            # session environment (Qt apps use qt6ct)
├── bin/
│   ├── hypora-theme        # applies a theme everywhere
│   ├── hypora-wallgen      # draws each theme's pixel-art wallpapers
│   ├── hypora-sysinfo      # prints RAM/CPU/GPU stats as JSON for the bar widget
│   ├── hypora-screenshot   # region / window / screen, saved and copied
│   ├── hypora-security     # security status as JSON, and the root actions behind it
│   │                       # (installed root-owned to /usr/local/bin, not ~/.local/bin)
│   └── hypora-weather      # place search and forecast via Open-Meteo
├── applications/           # .desktop entries copied into ~/.local/share/applications
├── themes/
│   ├── Nord/colors.toml    # palette (UI, terminal ANSI colors, GTK/icon theme)
│   ├── TokyoNight/colors.toml
│   ├── CatppuccinMocha/colors.toml
│   └── templates/          # one per app; {{ key }} is filled from colors.toml
├── system/
│   ├── fontconfig/         # system font defaults -> /etc/fonts/conf.d/
│   ├── yum.repos.d/        # Claude Code repository -> /etc/yum.repos.d/
│   └── sddm/               # login screen, installed by install.sh
│       ├── 10-hypora.conf  # -> /etc/sddm.conf.d/ (Wayland greeter on Hyprland, hypora theme)
│       ├── hyprland.lua    # minimal Hyprland session that hosts the greeter
│       └── hypora/         # SDDM theme -> /usr/share/sddm/themes/hypora/
└── LICENSE
```

Not created yet: `packages/` and `install/` (see [Status](#status)).

## Customizing

- **Colors and font:** edit `themes/<Name>/colors.toml`, or copy a theme folder to `themes/<NewName>/`, re-run `./install.sh`, then `hypora-theme <NewName>`. Wallpapers are drawn from the palette, so `hypora-wallgen <NewName>` gives the new theme matching ones. To theme another app, add a template to `themes/templates/` and link its output in `bin/hypora-theme`
- **Terminal and TUIs launched by widgets:** `terminal`, `mixer`, `network` and `bluetooth` in `themes/templates/Theme.qml.tpl`
- **Autostart, keybinds:** `config/hypr/hyprland.lua`
- **Monitors:** Display Settings, or edit `~/.config/hypr/monitors.lua` (loaded by `hyprland.lua`)
- **Bar contents:** `Bar.qml` (the right-hand `Row` holds the tray and the control center button)
- **Control center:** `ControlPanel.qml` (tiles are `Tile {}` items in the `GridLayout`)
- **Menu sections:** the `pages` list in `AppMenuPanel.qml`
- **Security:** menu > Security; anything needing root asks through the polkit prompt
- **Keybinds:** menu > Help > Keybindings, or the `keys` table at the top of the keybindings section in `config/hypr/hyprland.lua`
- **Shell:** `~/.zshrc.local` for your own zsh settings; `config/zsh/zshrc` for Hypora's
- **fetch readout:** `config/fastfetch/config.jsonc`, with the logo in `hypora.txt`
- **System usage readings:** click the widget in the bar, or edit `~/.config/hypora/sysinfo.json`

## Status

Working:
- Installer for packages, services, theme and config links
- Quickshell bar, app menu, control center, display settings, tray, volume, network, battery, notifications and polkit prompt
- Hyprland Lua config with keybinds, Nord-style borders and Quickshell autostart
- SDDM login screen (needs testing on real hardware)

In progress / planned:
- Package lists in `packages/*.txt` and a modular `install/` directory

## Known limitations

- Developed and tested in a VM so far; real hardware (GPU, laptop battery and backlight) is less tested
- The Hyprland Lua config format is new; if something misbehaves after a Hyprland update, check `hyprctl configerrors` and the Hyprland wiki
- Hyprland comes from the third-party `sdegler/hyprland` COPR, so builds may lag behind or break after Fedora updates
- impala needs iwd, so the installer switches NetworkManager's Wi-Fi backend to iwd — but only when the machine actually has a Wi-Fi radio, so VMs are left alone. If Wi-Fi misbehaves, delete `/etc/NetworkManager/conf.d/hypora-iwd.conf`, run `sudo systemctl enable wpa_supplicant`, and reboot (`nmtui` then works as before)
- In a VM with no Wi-Fi or Bluetooth adapter, impala and bluetui exit straight away with "no device" — expected, not a fault. The Network and Bluetooth windows say so plainly too
- Don't add a `qmldir` to `config/quickshell/`: it hides every component not listed in it (`Bar is not a type`). Quickshell finds `Theme.qml` on its own via `pragma Singleton`
- `~/.config/quickshell/Theme.qml`, `~/.config/kitty/current-theme.conf`, `~/.config/hypr/theme.lua`, `hyprlock.conf`, the GTK `gtk.css`/`settings.ini` and `qt6ct.conf` are links to files `hypora-theme` generates; edit the palette or templates instead, or your changes are lost on the next theme switch
- Fedora versions tested: Fedora 44

## License

See [LICENSE](LICENSE).
