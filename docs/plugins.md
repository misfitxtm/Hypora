# Plugins

A plugin adds a bar item to Hypora: a battery readout, a status icon, a widget with a dropdown. It
lives in its own repository and is installed with one command:

```bash
git clone https://github.com/someone/their-plugin.git
cd their-plugin
hypora-install-plugin        # same as: hypora-plugin install
```

`hypora-plugin install` also takes a directory (`hypora-plugin install ~/src/their-plugin`) or a
git URL (`hypora-plugin install https://github.com/someone/their-plugin --commit <sha>`).

## What you are agreeing to

A plugin is code that runs as you, inside the shell. Hypora cannot make that safe; it can only make
sure you are asked and know what you were asked. Before anything is written, `install` prints:

- the plugin's name, version, licence and where it came from, with the commit if it's a git checkout,
  and a warning if the working tree has changes that were never committed
- **every file it will write**, with a short SHA-256
- **every script it will run**, with a short SHA-256, marked `RUNS AS YOU`

Then it waits for a yes. Run without a terminal it refuses rather than guessing; `--yes` is for
scripts, and you still get the summary. Read the scripts first — they are in the repository.

What it will not do, whatever the manifest says:

- **Use root.** It refuses to run as root and never calls `sudo`. A plugin cannot install anything
  into `/usr/local/bin`, and cannot replace one of Hypora's root-owned commands.
  A setup script may itself run `sudo` for something that genuinely needs root (read the script, it is listed
  with its checksum); `sudo` then asks for your password, and `hypora-plugin` is not involved.
- **Overwrite a file that is not its own.** If `~/.config/quickshell/Clock.qml`, or anything the
  Hypora installer put in place, or a file from another plugin is in the way, the install stops
  before writing anything.
- **Follow links or leave its repository.** Files must be regular files inside the plugin; paths
  with `..`, absolute paths and symlinks are refused.
- **Clone from odd places.** Only `https://`, `ssh://git@…` and `git@…` URLs are accepted — not
  `file://`, and not git's `ext::` transport, which runs commands.

Pin a URL install to a commit you have read (`--commit`, a full 40-character id), the same way the
Hypora installer pins everything it fetches. `--ref` takes a branch or tag, which can move.

## Commands

| Command | Does |
|---|---|
| `hypora-plugin install [SOURCE]` | Install from a directory (default: the current one) or a git URL. Installing again updates |
| `hypora-plugin list [--json]` | What is installed, where in the bar, enabled or not |
| `hypora-plugin disable ID` / `enable ID` | Hide or show the bar item; nothing is removed |
| `hypora-plugin update ID` | Install again from where it came from, with the same summary and question (always asked; `update` has no `--yes`, because it fetches new code) |
| `hypora-plugin remove ID` | Undo the install: its remove script, then its files |

Files you edited are never deleted or silently replaced: on update the old copy is saved as
`<name>.bak.<timestamp>`, and `remove` leaves it where it is and says so, which is how the main
installer treats your edits too.

## Where things go

| Path | What |
|---|---|
| `~/.config/quickshell/<Name>.qml` | the plugin's QML, beside Hypora's own components, so it can use `Theme`, `Dropdown`, `Icon` and the rest by name |
| `~/.local/bin/<command>` | commands the plugin ships (`[bin]`) |
| `~/.config/hypora/plugins/<id>/` | what was installed and from where, so `remove` and `update` work after the clone is gone |
| `~/.config/hypora/plugins.json` | the list the bar reads. Edited by `hypora-plugin`, not by hand |

The Hypora installer never touches any of these: it only prunes files it recorded itself, so re-running
`./install.sh` leaves plugins alone. `Bar.qml` has three `BarPlugins` slots, and that is the only hook —
the bar reads `plugins.json` and loads the matching components, so enabling or removing a plugin shows up
without restarting the shell.

## Writing a plugin

A plugin repository has a `hypora-plugin.toml` at its root:

```toml
id = "my-plugin"                 # lowercase letters, digits, dashes
name = "My plugin"
version = "0.1.0"
description = "One line."
license = "MIT"

[widget]
component = "MyPlugin"          # the QML type shown in the bar; needs MyPlugin.qml in files
slot = "right"                  # left, center or right of the bar
hide_tray = ["spotify"]         # optional: hide tray icons whose id or title contains one of these
files = ["qml/MyPlugin.qml", "qml/MyPluginPanel.qml"]

[bin]                           # optional: commands for ~/.local/bin
files = ["bin/my-tool"]

[setup]                         # optional: scripts that run as the user
install = "scripts/install.sh"  # after the files are written
remove = "scripts/uninstall.sh" # before they are removed; a copy is kept, so it works after the clone is deleted
env = { SKIP_WIDGET = "1" }     # extra environment for both; HYPORA_PLUGIN=1 is always set
```

Unknown keys are an error, so a typo does not silently do nothing.

QML file names must be QML type names (`MyPlugin.qml`, not `my-plugin.qml`), and they all land in one
directory, so choose names unlikely to clash; a clash is refused at install time, not discovered later.

The bar item follows the same pattern as `Clock.qml`: it takes the bar's window and hides itself with
`visible: false`.

```qml
import QtQuick

Rectangle {
    id: root
    required property var window       // the bar window, for placing a Dropdown under it

    visible: somethingToShow           // a hidden plugin leaves no gap in the bar
    implicitWidth: label.implicitWidth + 16
    implicitHeight: 24
    radius: height / 2
    color: area.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

    Text { id: label; anchors.centerIn: parent; text: "hello"; color: Theme.fg
           font.family: Theme.font; font.pixelSize: Theme.fontSize }
    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; onClicked: drop.open = true }

    Dropdown { id: drop; screen: root.window.screen; barHeight: root.window.height; anchorItem: root
               /* your panel here */ }
}
```

The item is shown on the main display's bar only (Display Settings, **Main display**); other monitors' bars never load it, so the plugin does not need to check.

`Theme` is the current theme's palette, so the item follows theme changes with no extra work.

**Placeholders.** In `.qml` files, `@BIN_DIR@` becomes the absolute path of `~/.local/bin` at install
time. Use it to run your own command: Quickshell is often started without `~/.local/bin` on its
`PATH`, so a bare command name may not be found. Test for it being unreplaced if the file can also run
outside Hypora (`"@BIN_DIR@".startsWith("@")`).

**Treat text from outside as text.** Anything a device or service sends you — a Bluetooth name, a
song title — can contain markup or control characters. Set `textFormat: Text.PlainText` on text you
did not write yourself.

## Testing

`python3 tools/test-plugin.py` covers the manifest rules, the install/update/remove round trip, the
refusals above and the setup scripts, in a throwaway home directory.
