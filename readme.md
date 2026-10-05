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
- A minimal SDDM login screen (the same setup Omarchy uses): the time, the date and a password field, in the active theme's colors
- Hyprland, started through `uwsm`
- Quickshell as the shell layer (replaces Waybar, Mako and a standalone polkit agent)

**Quickshell components** (`config/quickshell/`)

| Component | What it does |
|---|---|
| Bar (`Bar.qml`) | Top bar on every monitor: Hypora menu button, workspaces 1-9, clock, tray and status icons (network, volume, battery, Do Not Disturb) |
| Menu (`AppMenu.qml`, `AppMenuPanel.qml`) | Omarchy-style menu from the Hypora logo at the top left. Five sections: **Apps** (everything installed), **Style** (Theme, Next wallpaper), **Settings** (Display, Network, Bluetooth, Sound), **Files** (Home, Documents, Downloads, ...) and **Tools** (Terminal, Claude Code, Hermes Agent, region screenshot). Enter or Right opens a section; Esc or Left goes back; typing searches apps. Power actions are in the control center |
| Theme picker (`ThemePicker.qml`) | **SUPER + ALT + T** (or menu > Settings > Theme): a card per installed theme with its wallpaper, a miniature desktop in its colors and its palette. Arrows to choose, Enter or click to apply |
| Wallpaper (`Wallpaper.qml`) | Draws the wallpaper on every monitor, cross-fading between images. Each theme has three; cycle with menu > Settings > **Next wallpaper** (or `qs ipc call wallpaper next`). Your choice is remembered |
| Clock and calendar (`Clock.qml`, `CalendarPanel.qml`) | Click the clock in the middle of the bar: time, date and a month calendar. Arrows or scrolling change the month; click the month name to jump back to today |
| Control center (`ControlCenter.qml`, `ControlPanel.qml`) | GNOME/macOS-style quick settings: click the status icons at the top right. Lock / Log out / Restart / Power off (the last three ask for a second click), volume and brightness sliders, power mode (Saver / Balanced / Performance), and Wi-Fi, Bluetooth, Do Not Disturb and Night Light tiles. The arrows and the mixer button open the TUIs below |
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
| Launcher (`Launcher.qml`) | App launcher on **SUPER + R**: type to filter installed apps, Up/Down or Tab to select, Enter to launch, Esc to close |
| Polkit (`PolkitDialog.qml`) | Full-screen authentication prompt (works with `pkexec` and other polkit requests) |

**Terminal tools** (the same ones Omarchy has used)

| Tool | For | Opened from |
|---|---|---|
| `impala` | Wi-Fi, advanced (needs iwd; falls back to `nmtui`) | Network window > Advanced |
| `bluetui` | Bluetooth, advanced | Bluetooth window > Advanced |
| `wiremix` | Sound outputs, inputs and per-app volume | Mixer button in the control center, menu > Sound |

Network and Bluetooth have proper Quickshell windows (above); the `impala` and `bluetui` TUIs are still one click away under "Advanced..." in each.

**Fonts and icons**
- **JetBrainsMono Nerd Font** for monospace and the shell UI, with **Liberation Sans / Serif** for the rest, the same defaults Omarchy uses. Set system-wide in `/etc/fonts/conf.d/50-hypora.conf`
- **Papirus-Dark** icons for apps, the launcher and the app menu (GTK settings and gsettings are set to match)

**AI tools**
- **Claude Code** from Anthropic's signed dnf repository (stable channel; `sudo dnf upgrade claude-code` to update). Run `claude` to log in
- **Hermes Agent** (Nous Research), installed per-user under `~/.hermes` with its official script. Run `hermes setup` to pick a model provider

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
5. Installs JetBrainsMono Nerd Font, sets the system font defaults, and installs Claude Code (adds `/etc/yum.repos.d/claude-code.repo` after checking the signing key's fingerprint) and Hermes Agent
6. Enables NetworkManager, upower, bluetooth and power profiles, switches NetworkManager's Wi-Fi backend to iwd on machines that have a Wi-Fi radio (taking effect at the next reboot), and sets the default boot target to graphical
7. Installs the theme palettes and templates into `~/.config/hypora/` and applies the chosen theme with `hypora-theme`
8. **Copies** `config/hypr/hyprland.lua`, `config/quickshell/`, the GTK settings and the themes into `~/.config/`, and `applications/*.desktop` (e.g. Display Settings) into `~/.local/share/applications/`
9. Installs the SDDM login theme (colors generated from the chosen theme), disables GDM/LightDM/greetd and enables SDDM
10. Copies the scripts in `bin/` (such as `hypora-theme`) into `~/.local/bin/`

Anything it replaces that you had changed is saved as `<name>.bak.<timestamp>`.

Configs are **copies**, so the clone can be moved or deleted after installing. To update, `git pull` (or clone again) and re-run `./install.sh`. It records a checksum of every file it installs: files you haven't touched are updated quietly, files you edited are saved as `<name>.bak.<timestamp>` before being replaced, and files Hypora no longer ships are removed (unless you edited them). Quickshell live-reloads when you edit `~/.config/quickshell/*.qml`.

### Starting the desktop

Reboot. SDDM shows the Hypora login screen (logo and password box, styled after Omarchy's) and starts the **Hyprland (uwsm-managed)** session. On machines with more than one user, the name appears above the box; click it or press Up/Down to switch.

Without the login screen, start it from a text console (TTY) with `uwsm start hyprland-uwsm.desktop` (or `start-hyprland`). Quickshell starts from the `hyprland.start` hook in `hyprland.lua` either way.

## Keybindings

| Keys | Action |
|---|---|
| SUPER + Enter | Terminal |
| SUPER + B | Browser (Firefox; change `browser` in `hyprland.lua`) |
| SUPER + R | App launcher |
| SUPER + ALT + T | Theme picker |
| SUPER + L | Lock |
| SUPER + Q | Close window |
| SUPER + V | Toggle floating |
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
│   │                       # Clock, CalendarPanel, ThemePicker, Wallpaper,
│   │                       # Icon, Net, ShellState, Slider, PowerButton
│   ├── kitty/kitty.conf    # terminal (colors come from the theme)
│   ├── zsh/zshrc           # -> ~/.zshrc
│   ├── fastfetch/          # config.jsonc and the hypora.txt ASCII logo
│   ├── nvim/               # the one LazyVim plugin file Hypora owns
│   └── uwsm/env            # session environment (Qt apps use qt6ct)
├── bin/
│   ├── hypora-theme        # applies a theme everywhere
│   └── hypora-wallgen      # draws each theme's pixel-art wallpapers
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
- **Shell:** `~/.zshrc.local` for your own zsh settings; `config/zsh/zshrc` for Hypora's
- **fetch readout:** `config/fastfetch/config.jsonc`, with the logo in `hypora.txt`

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
