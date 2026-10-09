# Desktop: workspaces, customizing, replacing another DE

Living with the desktop once it is installed.

[← back to the readme](../readme.md)

## The main display

Hyprland has no primary-monitor concept, so this is Hypora's own and it means three things: that screen starts focused, Hypora's single-instance panels (app menu, clipboard history) open there rather than on whichever output Quickshell enumerated first, and **the SDDM login screen appears there**.

Set it in Display Settings with the **Main display** toggle. It can only be moved to another screen, never switched off — "no main display" isn't a useful state.

The first two are stored in `~/.config/hypr/monitors.lua` as `HYPORA_PRIMARY`, read by `hyprland.lua` and by `ShellState.qml`. The login screen needs more than that: **the greeter runs as the `sddm` user and never reads your `~/.config`**, which is why a second monitor can host the login prompt and then stop being the main display the moment you log in.

So `bin/hypora-greeter` — root-owned, reached through `pkexec` — writes one generated file next to the greeter's own config, which loads it if present. That file is root-owned on purpose: anything the greeter reads before login must not be writable by the user it is about to authenticate.

Two deliberate choices in how little it does:

- It sets the output with `hyprctl dispatch focusmonitor`, not a monitor or window rule. This file is loaded by the config that draws the login screen, and a key some Hyprland version doesn't recognise would be a config error at the one moment there is no way to log in and fix it. A shell command that fails leaves the greeter exactly where it would have been.
- The greeter's `hyprland.lua` checks the file exists and `pcall`s it. A login screen on the wrong monitor is a nuisance; no login screen is a rescue disk.

The password prompt appears only when the main display actually changes — everything else in Display Settings applies without ever asking. Dismissing it costs the login screen's placement and nothing else, and the window says so. `install.sh` also re-applies whatever `monitors.lua` says on every run, so a dismissed prompt repairs itself next time you run the installer.

```
hypora-greeter status            # what the greeter is currently told
sudo hypora-greeter set DP-3     # by hand, if you prefer
sudo hypora-greeter clear        # back to letting Hyprland decide
```

## Workspaces and monitors

Every monitor has its own independent set of workspaces. Workspace 1 exists on each screen at the same time, SUPER + 1 switches the monitor you're pointing at, and sending a window to the other screen leaves it on the workspace you sent it to rather than dropping it wherever that screen happened to be.

**Five per monitor are permanent**, so they're always there to switch to and the bar can always show them. **Numbers 6 to 0 are made when you first use them** and disappear again once they're empty.

Hyprland numbers workspaces globally — a workspace belongs to one monitor at a time — so a per-monitor set is built by giving each monitor a block of ten numbers:

| monitor | permanent | on demand |
|---|---|---|
| 0 | 1–5 | 6–10 |
| 1 | 11–15 | 16–20 |
| 2 | 21–25 | 26–30 |

Every number in a block is pinned to its monitor with a `hl.workspace_rule`, and the first five of each are `persistent`. The bar subtracts the block's base before drawing, which is why each screen shows its own `1 2 3 4 5`. To change how many: `WS_STATIC` and `WS_STRIDE` at the top of the workspace section in `config/hypr/hyprland.lua` — keep `WS_STRIDE` at least as large as the number of keys you bind, or two monitors' blocks will overlap.

The workspace keybinds are Lua functions rather than plain dispatchers, because the target depends on which monitor has focus when you press them. Two things that caused this to be written carefully, both worth knowing if you edit it:

- `hl.get_active_monitor()` is only meaningful **inside** the callback. Called while the config is being read it returns nil, and it is never re-evaluated ([#14878](https://github.com/hyprwm/Hyprland/discussions/14878)).
- `hl.dsp.*` builds an object and does nothing on its own; it has to be handed to `hl.dispatch()`. Returning it from a bind callback silently does nothing ([#14282](https://github.com/hyprwm/Hyprland/discussions/14282)).

The rules are applied from the `hyprland.start` hook rather than at the top level, because `hl.get_monitors()` is still empty while the config is being read, and again on `monitor.added` so a screen plugged in later gets its own set.

## Customizing

- **Colors and font:** edit `themes/<Name>/colors.toml`, or copy a theme folder to `themes/<NewName>/`, re-run `./install.sh`, then `hypora-theme <NewName>`. To theme another app, add a template to `themes/templates/` and link its output in `bin/hypora-theme`
- **Terminal and TUIs launched by widgets:** `terminal`, `mixer`, `network` and `bluetooth` in `themes/templates/Theme.qml.tpl`
- **Autostart, keybinds:** `config/hypr/hyprland.lua`
- **Apps that should float instead of tile:** add the Wayland app ID to the `floatingApps` list near the window rules in `config/hypr/hyprland.lua` (Calculator is there already). `hyprctl clients` prints the ID as `class` for any window you have open
- **Monitors:** Display Settings, or edit `~/.config/hypr/monitors.lua` (loaded by `hyprland.lua`)
- **Workspaces per monitor:** `WS_STATIC` and `WS_STRIDE` at the top of the workspace section in `config/hypr/hyprland.lua` (see [Workspaces and monitors](#workspaces-and-monitors))
- **Bar contents:** `Bar.qml` (the right-hand `Row` holds the tray and the control center button)
- **Control center:** `ControlPanel.qml` (tiles are `Tile {}` items in the `GridLayout`)
- **Menu sections:** the `pages` list in `AppMenuPanel.qml`
- **Security:** menu > Security; anything needing root asks through the polkit prompt
- **Boot screen:** `themes/templates/plymouth.plymouth.tpl` for layout, `bin/hypora-plymouth` for the images (see [Boot screen](boot.md#boot-screen))
- **Text console colours:** `sudo hypora-console apply` (see [Text console](boot.md#text-console))
- **DNS resolver:** `system/systemd/resolved.conf.d/hypora-dns.conf`, then re-run `./install.sh` (see [DNS](network.md#dns))
- **MAC randomization:** `system/NetworkManager/conf.d/hypora-mac.conf`, or per network with `nmcli connection modify` (see [MAC addresses](network.md#mac-addresses))
- **What updates on its own:** `system/dnf/automatic.conf` (see [Automatic updates](security.md#automatic-updates))
- **Keybinds:** menu > Help > Keybindings, or the `keys` table at the top of the keybindings section in `config/hypr/hyprland.lua`
- **Shell:** `~/.zshrc.local` for your own zsh settings; `config/zsh/zshrc` for Hypora's
- **fetch readout:** `config/fastfetch/config.jsonc`, with the logo in `hypora.txt` — that logo is generated from the same geometry the shell draws, so edit `tools/gen-ascii-logo.py` and re-run it rather than editing the art by hand
- **System usage readings:** click the widget in the bar, or edit `~/.config/hypora/sysinfo.json`

## Replacing another desktop

If another desktop environment or window manager is installed, the installer names it and offers to remove it — last, after everything else has succeeded, and only if one is actually there.

```
hypora-replace-de list              # what is installed, and what removing it would take
hypora-replace-de check             # leftovers and PAM damage, changes nothing
sudo hypora-replace-de remove       # asks first, and shows the full plan
```

Recognises GNOME, KDE Plasma, Xfce, Cinnamon, MATE, LXQt, Budgie, COSMIC, Sway and i3.

Removal runs in **three phases**, because the first alone leaves most of the desktop on disk:

| Phase | What goes | Why it is separate |
|---|---|---|
| 1. Session | The shell, session manager, greeter | The pieces that make it a desktop rather than a pile of apps |
| 2. Leftovers | Every remaining package belonging to that desktop that nothing Hypora keeps still needs | Removing `gnome-shell` leaves `gnome-weather`, `gnome-logs`, `gnome-settings-daemon` and two dozen more, because nothing ever depended on them |
| 3. Orphans | `dnf autoremove` | The libraries that only existed to serve what just left — `gjs`, `mozjs`, `webkit` and so on |

On a real Fedora Workstation machine the three phases together removed **47 packages and freed 251 MiB** that phase 1 alone left behind. Use `--session-only` for the old narrow behaviour, or `--no-autoremove` to skip phase 3.

**The settings schemas and Hypora's own applications are never removed**, because Hypora is built on top of several of them:

- `gsettings-desktop-schemas` provides `org.gnome.desktop.interface`, which `bin/hypora-theme` writes, and `org.gnome.desktop.privacy`, which the Security window reads. Lose it and theming stops working and two rows of that window go blank.
- `nautilus`, `gnome-calculator`, `gnome-disk-utility`, `gnome-software` and `adw-gtk3-theme` are installed by Hypora deliberately.

So "remove GNOME" here means the session and its leftovers, not the component layer underneath.

### What makes phase 2 safe is the closure, not the name

A package being called `gnome-*` says nothing about whether Hypora needs it. `nautilus` requires `libgnome-autoar-0.so.0` and `libgnome-desktop-4.so.2`; `gnome-software` requires `gnome-app-list`. Query those by package name with `rpm -q --whatrequires` and they look like leaves, because the dependency is on a soname rather than a name — so a name-based sweep would mark them removable and take Nautilus with them.

So before anything is proposed, the full `requires` closure of the keep list is walked with `rpm` and subtracted. Names pick candidates; the closure vetoes them. The same filter is what stops a false positive: on a machine that never had Plasma, eight `kf6-*` Frameworks libraries match the KDE patterns — they arrive as Qt dependencies, one of them via `f44-backgrounds-base`. A separate `evidence` list, naming packages only that desktop's own install brings, decides whether the desktop was ever there at all.

### What makes phase 3 safe is `dnf mark user`

`autoremove` removes anything installed as a dependency that nothing requires any more, and after a desktop leaves, that describes several things Hypora needs: `gsettings-desktop-schemas` and `xorg-x11-server-Xwayland` are both reason `Dependency` on a stock install.

This is not hypothetical. On the machine this was developed against, a plain `dnf autoremove` run by hand after removing `gnome-shell` took **`gnome-keyring-pam` and `gcr`** with it. That disables [keyring auto-unlock](security.md#secrets-and-the-keyring) *silently*: `authselect` leaves the PAM stack referencing `pam_gnome_keyring.so`, and because those lines are `optional` and prefixed with `-`, PAM skips the missing module without even logging it. Login works. The keyring just never unlocks, and nothing anywhere says why.

So every installed keep-list package is marked user-installed before phase 1 starts — which takes it out of autoremove's reach permanently, including a later `dnf autoremove` you run by hand — and the keep list is passed as `--exclude` as well. `hypora-replace-de check` reports that specific damage if it has already happened, with the command to repair it.

Three further things make the whole operation safe rather than hopeful:

- **The plan is printed before anything happens**, including every package the dependency chain would drag along. That list is worth reading. Two entries in it were found exactly this way and are now permanently excluded: `xorg-x11-server-Xwayland`, without which no X11 application runs under Hyprland, and `gnome-keyring-pam`, which provides the `pam_gnome_keyring.so` that [keyring auto-unlock](security.md#secrets-and-the-keyring) depends on. Neither has a name that suggests GNOME owns it.
- **It refuses if you are running the desktop in question.** Removing a shell out from under a live session takes the terminal the command was typed into with it, part-way through a dnf transaction. Running the installer from a GNOME terminal is the normal case, so expect that refusal — reboot into Hypora and run it again.
- **It checks afterwards** that the schemas and applications Hypora needs are still installed, comparing against what was there before rather than against a list in the abstract, and prints the command to put anything back.

One wrinkle worth knowing: Fedora marks `gnome-shell` as a **dnf-protected package**, so you cannot remove your own desktop by accident. There is no flag to bypass that for one package — `--setopt=protected_packages` is additive, and clearing it entirely would also unprotect systemd, sudo, grub2, shim and the SELinux policy. So the single `protected.d` file naming that desktop is moved aside for the duration of the transaction and put back afterwards, including if the removal fails part-way.
