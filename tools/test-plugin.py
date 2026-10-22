#!/usr/bin/env python3
"""Tests for bin/hypora-plugin. Run: python3 tools/test-plugin.py"""
import importlib.machinery
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
loader = importlib.machinery.SourceFileLoader("hypora_plugin", str(ROOT / "bin" / "hypora-plugin"))
spec = importlib.util.spec_from_loader("hypora_plugin", loader)
hp = importlib.util.module_from_spec(spec)
loader.exec_module(hp)

MANIFEST = """
id = "demo-pods"
name = "Demo"
version = "1.0"
description = "A demo"
license = "MIT"
[widget]
component = "Demo"
slot = "right"
files = ["qml/Demo.qml", "qml/DemoPanel.qml"]
[bin]
files = ["bin/demo-tool"]
"""


def make_plugin(root, manifest=MANIFEST, extra=None):
    (root / "qml").mkdir(parents=True)
    (root / "bin").mkdir()
    (root / "hypora-plugin.toml").write_text(manifest)
    (root / "qml/Demo.qml").write_text('Item { property string tool: "@BIN_DIR@/demo-tool" }')
    (root / "qml/DemoPanel.qml").write_text("Item {}")
    (root / "bin/demo-tool").write_text("#!/bin/sh\necho hi\n")
    for rel, text in (extra or {}).items():
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        (root / rel).write_text(text)


class ManifestTests(unittest.TestCase):
    def bad(self, text, fragment):
        with self.assertRaises(hp.PluginError) as ctx:
            hp.parse_manifest(text)
        self.assertIn(fragment, str(ctx.exception))

    def test_valid(self):
        m = hp.parse_manifest(MANIFEST)
        self.assertEqual((m.id, m.slot, m.component), ("demo-pods", "right", "Demo"))

    def test_rejects_bad_id_slot_and_unknown_keys(self):
        self.bad(MANIFEST.replace('id = "demo-pods"', 'id = "Demo Pods"'), "id must be")
        self.bad(MANIFEST.replace('slot = "right"', 'slot = "top"'), "slot must be")
        self.bad(MANIFEST.replace('slot = "right"', 'slot = "right"\nhide_tray = ["A b"]'), "hide_tray")
        self.bad('surprise = 1\n' + MANIFEST, "unknown keys")

    def test_rejects_path_escapes(self):
        self.bad(MANIFEST.replace("qml/Demo.qml", "../Demo.qml"), "inside the plugin")
        self.bad(MANIFEST.replace("qml/Demo.qml", "/etc/Demo.qml"), "inside the plugin")
        self.bad(MANIFEST.replace("bin/demo-tool", "~/demo-tool"), "inside the plugin")

    def test_component_must_have_a_file(self):
        self.bad(MANIFEST.replace('component = "Demo"', 'component = "Other"'), "no Other.qml")

    def test_qml_names_must_be_types(self):
        self.bad(MANIFEST.replace("DemoPanel.qml", "demo-panel.qml"), "named like a QML type")

    def test_cannot_shadow_root_owned_commands(self):
        self.bad(MANIFEST.replace("demo-tool", "hypora-security"), "root-owned")

    def test_setup_env_is_checked(self):
        self.bad(MANIFEST + '\n[setup]\nenv = { "bad name" = "x" }\n', "setup.env")


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name) / "home"
        self.home.mkdir()
        os.environ.pop("XDG_CONFIG_HOME", None)
        self.old_home = os.environ.get("HOME")
        os.environ["HOME"] = str(self.home)
        self.paths = hp.Paths(self.home)
        self.paths.qs.mkdir(parents=True)
        self.src = Path(self.tmp.name) / "plugin"
        self.out = []

    def tearDown(self):
        os.environ["HOME"] = self.old_home
        self.tmp.cleanup()

    def install(self, **kw):
        hp.install(self.paths, str(self.src), assume_yes=True, out=self.out.append, **kw)

    def test_install_writes_files_state_and_list(self):
        make_plugin(self.src)
        self.install()
        qml = (self.paths.qs / "Demo.qml").read_text()
        self.assertIn(str(self.paths.bin) + "/demo-tool", qml)   # placeholder replaced
        self.assertNotIn("@BIN_DIR@", qml)
        self.assertEqual(os.stat(self.paths.bin / "demo-tool").st_mode & 0o777, 0o755)
        listed = json.loads(self.paths.list_file.read_text())
        self.assertEqual(listed, [{"id": "demo-pods", "component": "Demo", "slot": "right", "hide_tray": []}])

    def test_summary_names_every_file(self):
        make_plugin(self.src)
        self.install()
        text = "\n".join(self.out)
        for name in ("Demo.qml", "DemoPanel.qml", "demo-tool"):
            self.assertIn(name, text)

    def test_reinstall_is_idempotent_and_keeps_edits(self):
        make_plugin(self.src)
        self.install()
        (self.paths.qs / "DemoPanel.qml").write_text("Item { /* my edit */ }")
        self.install()
        backups = list(self.paths.qs.glob("DemoPanel.qml.bak.*"))
        self.assertEqual(len(backups), 1)
        self.assertIn("my edit", backups[0].read_text())
        self.assertEqual((self.paths.qs / "DemoPanel.qml").read_text(), "Item {}")

    def test_refuses_to_overwrite_someone_elses_file(self):
        make_plugin(self.src)
        (self.paths.qs / "Demo.qml").write_text("mine")
        with self.assertRaises(hp.PluginError) as ctx:
            self.install()
        self.assertIn("not from this plugin", str(ctx.exception))
        self.assertEqual((self.paths.qs / "Demo.qml").read_text(), "mine")
        self.assertFalse((self.paths.bin / "demo-tool").exists())      # nothing half-installed

    def test_refuses_files_hypora_installed(self):
        make_plugin(self.src)
        core = self.paths.core_manifest
        core.parent.mkdir(parents=True)
        core.write_text("0" * 64 + "  " + str(self.paths.qs / "Demo.qml") + "\n")
        with self.assertRaises(hp.PluginError) as ctx:
            self.install()
        self.assertIn("belongs to Hypora", str(ctx.exception))

    def test_refuses_symlinked_source_files(self):
        make_plugin(self.src)
        (self.src / "qml/DemoPanel.qml").unlink()
        (self.src / "qml/DemoPanel.qml").symlink_to("/etc/hostname")
        with self.assertRaises(hp.PluginError) as ctx:
            self.install()
        self.assertIn("regular file", str(ctx.exception))

    def test_refuses_without_confirmation_off_a_terminal(self):
        make_plugin(self.src)
        with self.assertRaises(hp.PluginError) as ctx:
            hp.install(self.paths, str(self.src), assume_yes=False, out=self.out.append)
        self.assertIn("--yes", str(ctx.exception))
        self.assertFalse((self.paths.qs / "Demo.qml").exists())

    def test_remove_deletes_unchanged_files_and_keeps_edited_ones(self):
        make_plugin(self.src)
        self.install()
        (self.paths.qs / "DemoPanel.qml").write_text("changed")
        hp.remove(self.paths, "demo-pods", assume_yes=True, out=self.out.append)
        self.assertFalse((self.paths.qs / "Demo.qml").exists())
        self.assertFalse((self.paths.bin / "demo-tool").exists())
        self.assertEqual((self.paths.qs / "DemoPanel.qml").read_text(), "changed")
        self.assertEqual(json.loads(self.paths.list_file.read_text()), [])
        self.assertFalse((self.paths.plugins / "demo-pods").exists())

    def test_disable_hides_without_removing(self):
        make_plugin(self.src)
        self.install()
        hp.set_enabled(self.paths, "demo-pods", False, out=self.out.append)
        self.assertEqual(json.loads(self.paths.list_file.read_text()), [])
        self.assertTrue((self.paths.qs / "Demo.qml").exists())
        hp.set_enabled(self.paths, "demo-pods", True, out=self.out.append)
        self.assertEqual(len(json.loads(self.paths.list_file.read_text())), 1)

    def test_setup_scripts_run_with_their_environment_and_remove_copy_is_kept(self):
        manifest = MANIFEST + '\n[setup]\ninstall = "run/in.sh"\nremove = "run/out.sh"\nenv = { SKIP_WIDGET = "1" }\n'
        mark = Path(self.tmp.name) / "marks"
        make_plugin(self.src, manifest, {
            "run/in.sh": f'#!/bin/sh\necho "in $SKIP_WIDGET $HYPORA_PLUGIN" >> {mark}\n',
            "run/out.sh": f'#!/bin/sh\necho out >> {mark}\n'})
        for f in ("run/in.sh", "run/out.sh"):
            os.chmod(self.src / f, 0o755)
        self.install()
        self.assertIn("RUNS AS YOU", "\n".join(self.out))
        self.assertEqual(mark.read_text().strip(), "in 1 1")
        (self.src / "run/out.sh").unlink()          # the clone may be deleted; the copy must survive
        hp.remove(self.paths, "demo-pods", assume_yes=True, out=self.out.append)
        self.assertEqual(mark.read_text().split(), ["in", "1", "1", "out"])

    def test_failed_setup_leaves_files_and_says_how_to_retry(self):
        make_plugin(self.src, MANIFEST + '\n[setup]\ninstall = "run/in.sh"\n', {"run/in.sh": "#!/bin/sh\nexit 3\n"})
        os.chmod(self.src / "run/in.sh", 0o755)
        with self.assertRaises(hp.PluginError) as ctx:
            self.install()
        self.assertIn("update demo-pods", str(ctx.exception))
        self.assertTrue((self.paths.qs / "Demo.qml").exists())


class MiscTests(unittest.TestCase):
    def test_urls(self):
        for ok in ("https://github.com/a/b", "git@github.com:a/b.git", "ssh://git@host/a/b"):
            self.assertTrue(hp.URL_RE.match(ok), ok)
        for bad in ("file:///etc", "ext::sh -c id", "http://x/y", "--upload-pack=x", "ftp://x"):
            self.assertFalse(hp.URL_RE.match(bad), bad)

    def test_clean_strips_terminal_escapes(self):
        self.assertEqual(hp.clean("Name\x1b[31m\n\x07"), "Name[31m")
        self.assertEqual(len(hp.clean("x" * 500)), 200)

    def test_root_owned_list_matches_installer(self):
        # install.sh and hypora-plugin each list the root-owned helpers and must agree, or a plugin could shadow one.
        text = (ROOT / "install.sh").read_text()
        body = text.split("ROOT_OWNED=(", 1)[1].split(")", 1)[0]
        self.assertEqual(set(body.split()), hp.ROOT_OWNED)


if __name__ == "__main__":
    unittest.main()
