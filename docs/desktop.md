# Desktop: workspaces, customizing, replacing another DE

Living with the desktop once it is installed.

[← back to the readme](../readme.md)

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
sudo hypora-replace-de remove       # asks first, and shows the full plan
```

Recognises GNOME, KDE Plasma, Xfce, Cinnamon, MATE, LXQt, Budgie, COSMIC, Sway and i3.

**Only the session is removed** — the shell, the session manager, the greeter. Not the applications, and emphatically not the settings schemas, because Hypora is built on top of several of them:

- `gsettings-desktop-schemas` provides `org.gnome.desktop.interface`, which `bin/hypora-theme` writes, and `org.gnome.desktop.privacy`, which the Security window reads. Lose it and theming stops working and two rows of that window go blank.
- `nautilus`, `gnome-calculator`, `gnome-disk-utility`, `gnome-software` and `adw-gtk3-theme` are installed by Hypora deliberately.

So "remove GNOME" here means `gnome-shell` and `gnome-session`, not GNOME.

Three things make that safe rather than hopeful:

- **The plan is printed before anything happens**, including every package the dependency chain would drag along. That list is worth reading. Two entries in it were found exactly this way and are now permanently excluded: `xorg-x11-server-Xwayland`, without which no X11 application runs under Hyprland, and `gnome-keyring-pam`, which provides the `pam_gnome_keyring.so` that [keyring auto-unlock](security.md#secrets-and-the-keyring) depends on. Neither has a name that suggests GNOME owns it.
- **It refuses if you are running the desktop in question.** Removing a shell out from under a live session takes the terminal the command was typed into with it, part-way through a dnf transaction. Running the installer from a GNOME terminal is the normal case, so expect that refusal — reboot into Hypora and run it again.
- **It checks afterwards** that the schemas and applications Hypora needs are still installed, comparing against what was there before rather than against a list in the abstract, and prints the command to put anything back.

One wrinkle worth knowing: Fedora marks `gnome-shell` as a **dnf-protected package**, so you cannot remove your own desktop by accident. There is no flag to bypass that for one package — `--setopt=protected_packages` is additive, and clearing it entirely would also unprotect systemd, sudo, grub2, shim and the SELinux policy. So the single `protected.d` file naming that desktop is moved aside for the duration of the transaction and put back afterwards, including if the removal fails part-way.
