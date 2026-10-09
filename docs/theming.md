# Making a theme

A Hypora theme is **one file of colours and a folder of wallpapers**. There is no theme
engine, no per-app config to keep in sync, and nothing to compile.

[← back to the readme](../readme.md)

```
themes/YourTheme/
├── colors.toml          # 31 keys: the whole theme
└── backgrounds/         # wallpapers, cycled by the shell
```

`bin/hypora-theme` renders every file in `themes/templates/` with those values and symlinks
the results into place, so one palette drives the Quickshell shell, kitty, Hyprland's
borders, hyprlock, GTK 3/4, Qt, `eza`, the SDDM login screen, the Plymouth splash and the
GRUB menu. Add a key to the palette and every template can use it; add a template and every
theme gets it for free.

## Make one

```bash
cd ~/.local/share/hypora
cp -r themes/Nord themes/YourTheme
rm themes/YourTheme/backgrounds/*          # supply your own
$EDITOR themes/YourTheme/colors.toml       # set name = "YourTheme" and the colours
tools/check-theme.py themes/YourTheme      # verify before you look at it
hypora-theme YourTheme                     # apply
```

Starting from an existing theme rather than a blank file matters: all 31 keys have to be
present, and `hypora-theme` warns rather than fails when one is missing, so the first sign
of an omission is usually a blank row somewhere rather than an error.

The theme picker (**SUPER + ALT + T**) finds it automatically — it lists whatever is in
`~/.config/hypora/themes/`, which `install.sh` populates from this directory.

## The 31 keys

**Identity**

| Key | Notes |
|---|---|
| `name` | Shown in the picker. Match the directory name |
| `mode` | `dark` or `light`. Sets `prefer-dark`, so GTK and Qt apps follow |

**Interface** — these eight do most of the work

| Key | Where it lands |
|---|---|
| `background` | Window and bar background, the base everything sits on |
| `surface` | Panels, popups, cards — one step up from the background |
| `foreground` | Body text and icons |
| `dim` | Secondary text: timestamps, hints, inactive workspaces |
| `accent` | The colour the eye should find — active workspace, focused border, toggles |
| `error` | Failures and warnings. Never the only signal, but always this colour |
| `selection` | Selected rows and text selection |
| `muted` | Disabled controls and separators |

**Terminal** — `term_foreground` plus the sixteen ANSI colours (`black` … `bright_white`).
These reach further than the terminal: `eza`'s listing colours are built from them, and so
is Neovim's palette when no colorscheme matches.

**System** — `font` (a family name, must be installed), `gtk_theme` (e.g. `adw-gtk3-dark`),
`icon_theme`, `color_scheme` (`prefer-dark` or `prefer-light`).

Every colour is `#rrggbb`. Not `#rgb`, not `rgba()`, not a name — the templates substitute
the string as-is into files with ten different syntaxes, and only full hex works everywhere.

## Check it before you look at it

```bash
tools/check-theme.py                 # every theme
tools/check-theme.py themes/Nord     # one
```

It verifies all 31 keys are present, every colour parses as `#rrggbb`, `mode` is valid, and
the combinations Hypora actually renders meet WCAG contrast:

| Pair | Floor | Why |
|---|---|---|
| `foreground` on `background` | 4.5 | body text |
| `foreground` on `surface` | 4.5 | text on panels, popups, the bar |
| `dim` on `background` | 3.0 | secondary text is still text |
| `accent` on `background` | 3.0 | a control you are meant to find |
| `error` on `background` | 3.0 | the one colour that must never be missed |

`dim` is the one that catches people. It is *meant* to recede, which makes it easy to push
until it stops being readable on a laptop panel at low brightness. The shipped TokyoNight
currently fails this check at 2.76 — a real bug, not a tolerance.

The checker exits non-zero on failure and changes nothing.

## Wallpapers

Drop images in `themes/YourTheme/backgrounds/`. The shell cycles them (menu > Style > **Next
wallpaper**, or `qs ipc call wallpaper next`) and remembers your choice per theme.

Two conventions worth following, both visible in the shipped themes:

- **Name them `N-short-description.ext`** — `3-rainy-street.jpg`, not `IMG_2841.jpg`. The
  number sets the order; the description is what makes the set reviewable a year later.
- **JPEG for photographs, PNG for flat art.** PNG is lossless, which is right for pixel art,
  line art and anything with few colours — and badly wrong for a photograph: one 4K
  photographic PNG in this repo was 7.2 MB and became 632 KB as a JPEG with no visible loss.
  `identify -format '%k' file.png` prints the colour count; a few dozen means PNG is
  correct, hundreds of thousands means it should be a JPEG.

Qt cannot decode WebP without `qt6-qtimageformats`, so convert those:
`magick in.webp -quality 92 out.jpg`.

## Neovim

`config/nvim/lua/plugins/hypora.lua` maps a Hypora theme to a Neovim colorscheme by name.
If yours has no upstream Neovim port, leave it out — it falls through to the default. A
deliberate mismatch is better than pointing at something merely dark and hoping.

## Adding a template

To theme something Hypora does not touch yet, add `themes/templates/yourapp.conf.tpl` using
`{{ key }}` for any palette value. `hypora-theme` renders it to
`~/.config/hypora/current/yourapp.conf` on every switch; add a `link` line in `bin/hypora-theme`
if the app needs it at a fixed path.

Three substitution forms are available for each colour:

| Form | Produces | For |
|---|---|---|
| `{{ accent }}` | `#88c0d0` | CSS, most config formats |
| `{{ accent_hex }}` | `88c0d0` | Hyprland's `0xAARRGGBB`, anything that supplies its own prefix |
| `{{ accent_rgb }}` | `136;192;208` | ANSI truecolor — this is how `eza` gets its colours |

Plus `{{ home }}`, `{{ name }}`, `{{ prefer_dark }}` and `{{ icon_theme }}`.

If a template references a key the palette does not define, `hypora-theme` prints a warning
naming the template and leaves the `{{ key }}` in the output — so a new key must be added to
**every** theme, not just the one you are testing. `tools/check-theme.py` run with no
arguments is the quickest way to confirm that.

## Contributing one back

Open a [pull request](https://github.com/misfitxtm/Hypora/pulls) with the theme directory
and, please, wallpapers you have the right to redistribute — that is the part most likely to
be a problem. `tools/check-theme.py` should pass before you send it.
