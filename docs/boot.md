# Boot: menu, splash and console

Everything between pressing the power button and the login screen.

[← back to the readme](../readme.md)

## Boot menu

The GRUB menu is the first screen of the boot, and Fedora leaves it as white-on-black in 80×25 text mode. `bin/hypora-grub` generates a theme from the active palette, laid out after Limine's menu: the title centred along the top, key legends in the two top corners, the kernel list alone in open space with an accent rule down the left of the current entry, and the theme name in the bottom corner. Nothing moves, no chrome, no distro branding.

```
hypora-grub print      # the theme.txt that would be written, no root needed
hypora-grub status     # what GRUB is currently set to do
sudo hypora-grub apply # install it and switch GRUB to graphics mode
sudo hypora-grub remove
```

`install.sh` applies it automatically when GRUB is present, and skips silently when it isn't — a machine booting via systemd-boot has nothing here to theme.

Three things about GRUB make this more than dropping a file in place, and each one is a way to end up with a theme that appears broken rather than one that is:

- **A theme does nothing in text mode.** Fedora ships `GRUB_TERMINAL_OUTPUT="console"`, which is exactly that. A theme installed without changing it is invisible, and looks for all the world like the theme is at fault. `apply` switches it to `gfxterm`, sets `GRUB_GFXMODE=auto`, and sets `GRUB_GFXPAYLOAD_LINUX=keep` so the handover to the kernel doesn't flash back to text.
- **GRUB has no system fonts.** It reads only its own `.pf2` format, so fonts are converted with `grub2-mkfont` — one file per size, because GRUB cannot scale a font. The names have to match `theme.txt` exactly; a name that doesn't match falls back to the built-in font with no error. Note that `grub2-mkfont -n` takes the *family* and appends the style and size itself, so the family is `Hypora Mono` and the result is `Hypora Mono Regular 16`.
- **The selected row cannot be marked with a colour alone.** `selected_item_color` sets the *text* colour, not the background, so any mark beside the current entry has to be an image. Hypora uses the `_w` west slice of a nine-slice with a transparent `_c` centre, which draws a rule down the left edge rather than a bar behind the text. The west slice stretches vertically only, so a uniform rule scales exactly at any item height — an arrow glyph there, which is what Limine draws, would be smeared by that same stretch. The PNGs are written straight from `zlib`.

`/etc/default/grub` is backed up to `/etc/default/grub.hypora-<timestamp>` before each change, and every line the script owns is marked:

```
# was, before hypora-grub: GRUB_TERMINAL_OUTPUT="console"
GRUB_TERMINAL_OUTPUT="gfxterm"  # set by hypora-grub
```

That marker is what makes the edit safe to repeat: without it, each theme switch commented out the previous switch's line, and `remove` then restored a stack of dead lines as live config. `remove` puts the original back exactly.

Switching themes does **not** re-theme the boot menu, because that means regenerating `grub.cfg` as root — far too much to do behind a theme switch. `hypora-theme` compares the installed theme against what the current palette would produce and tells you to run `sudo hypora-grub apply` only when they actually differ.

## Boot screen

![Hypora boot screen in Nord, Tokyo Night and Catppuccin Mocha](images/boot-screen.png)

The boot splash and the **LUKS passphrase prompt** are the same screen: `systemd-cryptsetup` asks through `systemd-ask-password`, and Plymouth draws it. So theming the unlock prompt means shipping a Plymouth theme, which Hypora generates from the active palette like everything else.

Two halves:

- `themes/templates/plymouth.plymouth.tpl` → `/usr/share/plymouth/themes/hypora/hypora.plymouth`. It uses `two-step`, the module Fedora's own themes are built on, and takes the background and progress-bar colours straight from the palette.
- `bin/hypora-plymouth` draws `entry.png`, `bullet.png`, `lock.png`, `capslock.png` and `watermark.png` in the palette's colours. Everything the module doesn't colour itself is a PNG, so the images have to be generated per theme. It uses signed distance fields and the standard library only — no Pillow, no ImageMagick — because this has to work on a machine mid-install.

The padlock is the same geometry as the shell's `lock` icon, and the watermark is the same hexagon mark as the bar and the login screen. The mark keeps its own gradient in every palette, matching `Logo.qml`.

**Don't put Plymouth's own key names in the comments.** `plymouth-set-default-theme` and `plymouth-populate-initrd` read this file with unanchored greps and expand the result unquoted, so a comment containing `ModuleName=` matches alongside the real line. The value becomes two lines, `[ ! -e $VALUE.so ]` fails with *"too many arguments"*, and — because that failure makes the guarding `if` false rather than true — the module is then installed under a mangled path and **never reaches the initramfs**, leaving a boot screen that silently falls back to text. `ModuleName` and `ImageDir` have no guard at all; `Font`, `TitleFont` and `MonospaceFont` take the first match, so a comment above the real line shadows it. The installer checks for this and refuses to switch themes rather than leaving you with a text prompt.

**It lives in the initramfs.** Plymouth runs before the root filesystem is mounted, so the theme is copied into the initramfs by dracut. That has two consequences:

- Switching themes updates `/usr/share/plymouth/themes/hypora/` but **not** what renders at boot until `sudo dracut -f`. `hypora-theme` prints this rather than running it, because a dracut rebuild takes 20–30 seconds and needs root — too much to do silently behind a theme switch.
- The font is handled for you: `plymouth-populate-initrd` runs `fc-match` on the `Font=` line and copies the matching file in. JetBrainsMono Nerd Font is installed to `/usr/local/share/fonts`, system-wide, so root's fontconfig finds it.

**What can't be themed.** `two-step` has no key for the prompt text's colour — it always draws it white. Fine for the three dark palettes here; a light palette would need the `script` module instead (`plymouth-plugin-script`), which replaces the ini with a real script at the cost of debugging failures in early boot.

Preview it without rebooting, which is worth doing before trusting it on an encrypted disk:

```bash
sudo plymouthd --debug --tty=/dev/tty2 ; sudo plymouth --show-splash
sudo plymouth ask-for-password          # the prompt, on tty2
sudo plymouth quit
```

If the theme ever fails to render on a machine that needs a passphrase, **Esc** drops Plymouth to the plain text prompt. The installer also refuses to switch to the theme unless `entry.png` and `bullet.png` are actually on disk, so a half-generated theme can't lock you out.


### Handing over to the login screen

Plymouth draws into its own buffer, so when it exits the framebuffer underneath still holds whatever was there before — on a themed setup, the GRUB menu. That is why the menu appears to come back for a moment between the splash ending and SDDM arriving: it is not being redrawn, it was never painted over.

A drop-in on `plymouth-quit.service` passes `--retain-splash`, which leaves the splash's last frame on screen so SDDM paints over Hypora's own artwork instead:

```
/etc/systemd/system/plymouth-quit.service.d/10-hypora-retain-splash.conf
```

The empty `ExecStart=` in that file is required rather than decorative — `plymouth-quit.service` is a oneshot with one `ExecStart`, and systemd refuses a second unless the list is cleared first.

Worth knowing the trade: if SDDM never starts, the splash stays on screen rather than dropping to a console, so a failed boot looks like a frozen splash. `Ctrl+Alt+F3` still gets a TTY and `journalctl -b -u sddm` says what happened.

## Text console

The boot screen above is Plymouth drawing on a graphics device. When there isn't one — a VM with no KMS, a GPU whose driver loads after the initramfs asks for your passphrase, or any boot where you press Esc — Plymouth falls back to its text module and you get a plain console instead.

That fallback can't be themed through Plymouth: `text.plymouth` has no colour settings and the module hard-codes them. What *can* be changed is the Linux virtual terminal's own 16-colour palette, which is a kernel parameter:

```bash
hypora-console print      # the arguments for the current theme
hypora-console status     # what the running kernel is using
sudo hypora-console apply # set them; takes effect at the next boot
sudo hypora-console remove
```

It has to be a kernel argument rather than a config file because the palette is set when the console initialises — before the initramfs asks for a passphrase. Anything that waits for a service to start is already too late.

Slot 0 is the console background and slot 7 the foreground, so those take the theme's `background` and `foreground` rather than its black and white; the other fourteen are the palette's ANSI colours. `apply` writes through `grubby` **and** `/etc/kernel/cmdline` — updating only the boot entries is how the colours quietly vanish one kernel update later, since new kernels take their command line from that file.

Two things it deliberately doesn't do: it isn't run by `hypora-theme` on every theme switch (editing the kernel command line shouldn't be a side effect of picking a colour scheme — `hypora-theme` just prints a reminder when the console is out of step), and it leaves the cursor alone. Add `vt.global_cursor_default=0` yourself if you'd rather not have the blinking block.

Related knobs this doesn't touch: the console font is `FONT=` in `/etc/vconsole.conf` (`terminus-fonts-console` provides `ter-v22n` and similar), and `loglevel=3` next to `quiet` stops kernel messages scrolling the passphrase prompt away.
