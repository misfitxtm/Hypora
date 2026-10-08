# Security: secrets, firmware and updates

The keyring, firmware updates from LVFS, and what patches itself.

[← back to the readme](../readme.md)

## Secrets and the keyring

Fedora Workstation starts `gnome-keyring` from the GNOME session. Hyprland starts nothing, and an app that asks the Secret Service API where to keep a token and finds no provider at all may fall back to writing it to disk unencrypted — so Hypora installs `gnome-keyring` and starts it from `hyprland.lua` with `--components=secrets,ssh`. `SSH_AUTH_SOCK` is set in `config/uwsm/env` so everything in the session agrees on one agent socket.

### Auto-unlock

The keyring is a file encrypted with a password, so something has to supply that password. Hypora adds three lines to `/etc/pam.d/sddm` so your login password does it, which is what GDM does — the same three lines are in `/etc/pam.d/gdm-password` on any Fedora Workstation:

```
-auth      optional  pam_gnome_keyring.so
-password  optional  pam_gnome_keyring.so use_authtok
-session   optional  pam_gnome_keyring.so auto_start
```

Each one earns its place. `auth` captures the password you just typed; `session` uses it to unlock the keyring; `password` re-keys the keyring when you change your account password — **without that third line, changing your password orphans the keyring** behind a password you no longer know, and the only way out is to delete it and lose what was in it.

This edits the file that decides whether you can log in, so it is done carefully:

- **Appended, not inserted.** PAM keeps a separate stack per module type and runs each in file order, so a line at the end of the file joins the end of its own type's stack. Hypora therefore never has to parse or reorder what Fedora put there. The side effect is that the `auth` and `password` lines sit below the `session` block in the file, which looks odd and reads fine to PAM.
- **`-` and `optional` together.** The dash skips the line silently if the module is missing; `optional` makes PAM ignore its result either way. Neither can turn a working login into a failing one.
- **The original is backed up** to `/etc/pam.d/sddm.hypora-<timestamp>` before anything is written, and the installer prints the path.
- **It is idempotent** — a second run detects the lines and leaves them alone.

Skip it with `KEYRING_AUTOUNLOCK=no ./install.sh`, or undo it by deleting those three lines.

If you are **still** asked for a keyring password after this, the usual cause is a login keyring that already exists with a *different* password — PAM is offering your login password and the keyring wants the old one. Either change the keyring's password to match your login password in Seahorse (`gnome-keyring` ships it as **Passwords and Keys**), or delete `~/.local/share/keyrings/login.keyring` and let it be recreated, which loses whatever was stored in it.

## Firmware updates

**Menu > Security > Check for firmware updates** opens a floating, pinned terminal running `bin/hypora-firmware`, which refreshes from the [Linux Vendor Firmware Service](https://fwupd.org) and installs whatever applies to the machine:

```
fwupdmgr refresh --force
fwupdmgr get-updates --no-unreported-check
fwupdmgr update -y --no-reboot-check
```

This is a button rather than part of the automatic updates on purpose. Firmware is written to the hardware itself, some of it only takes effect after a restart, and a motherboard update interrupted half way is how machines get bricked — so it happens when you ask, in a window you can watch. fwupd asks polkit before touching any device, so Hypora's password prompt appears before anything is written.

The window is `float` + `pin` so it stays in front and remains visible if you change workspace mid-update. It's matched on its title, and the Security window passes `--title` when launching the terminal: Hyprland decides float and pin at the moment a window is **mapped**, so a title the program sets afterwards arrives too late and the window ends up tiled. The script prints the title escape sequence too, which covers running `hypora-firmware` yourself in a terminal started without the flag. This assumes a terminal that accepts `--title` — kitty, alacritty and foot all do.

Two things worth knowing:

- **Checking contacts fwupd.org.** It's the one part of Hypora that reaches an outside server without you typing something first, which is why it isn't done in the background. Devices whose vendors don't publish to LVFS never appear — those update from the vendor's own tool or the UEFI setup screen.
- **"No updates" is a success, not a failure.** `fwupdmgr` exits 2 for "ran fine, nothing to do" and 3 for "not found". The script treats both as success; reading them as errors is what would make a fully-updated machine look broken.

## Automatic updates

Nothing covers both halves of this system, so there are two timers.

**System packages** go through `dnf5-automatic.timer` (daily at 06:00, up to an hour of jitter, catching up on missed runs), configured in `/etc/dnf/automatic.conf`. Both timers are enabled but not started by the installer, so they begin at the reboot it ends with:

```ini
[commands]
apply_updates = yes
download_updates = yes
upgrade_type = security
reboot = never
```

`upgrade_type = security` limits unattended installs to packages carrying a Fedora security advisory, which has two consequences:

- **It excludes the Hyprland COPR.** Third-party repositories publish no advisory metadata, so nothing from them can ever match — meaning the compositor this desktop depends on never updates while you're using it. COPR updates stay a decision you make by running `sudo dnf upgrade` yourself.
- **It also excludes real fixes** that Fedora shipped as a bugfix or enhancement update rather than a security one, which happens often enough to matter. This narrows the window on the worst holes; it is not a substitute for updating.

`reboot = never`, because a desktop deciding on its own to restart is worse than a kernel that waits. `dnf5 needs-restarting -r` says when a reboot is due.

**Flatpak apps** — including Firefox, where most of the day-to-day risk actually lives — are invisible to dnf, so `hypora-flatpak-update.timer` runs `flatpak update --system` daily at 07:00. Old runtimes aren't cleaned up automatically; `flatpak uninstall --unused` does that, or Warehouse.

Check both:

```bash
systemctl list-timers 'dnf*' 'hypora*'
journalctl -u dnf5-automatic -u hypora-flatpak-update
sudo systemctl start hypora-flatpak-update.service   # run the flatpak one now
sudo dnf5 automatic --no-installupdates              # see what the package one would do
```

To go back to updating by hand, `sudo systemctl disable --now dnf5-automatic.timer hypora-flatpak-update.timer`. To install everything rather than security advisories only, set `upgrade_type = default` in `system/dnf/automatic.conf` and re-run the installer — understanding that this includes the COPR.
