#!/usr/bin/env python3
"""Tests for the risky parts of bin/hypora-theme and bin/hypora-security.
Run: python3 tools/test-security.py

hypora-theme pastes palette values into a sed script, and a colors.toml is something people
share, so its validator is the only thing between a theme and a shell command. The swapfile
code rewrites /etc/fstab as root, where a mistake is a machine that does not boot.
"""
import importlib.machinery
import importlib.util
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent


def load(name):
    loader = importlib.machinery.SourceFileLoader(name.replace("-", "_"), str(ROOT / "bin" / name))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


class ThemeValidatorTests(unittest.TestCase):
    def run_theme(self, colors):
        with tempfile.TemporaryDirectory() as home:
            d = Path(home) / ".config/hypora/themes/Evil"
            d.mkdir(parents=True)
            (d / "colors.toml").write_text(colors)
            return subprocess.run(["bash", str(ROOT / "bin/hypora-theme"), "Evil"],
                                  env={"HOME": home, "PATH": os.environ["PATH"]},
                                  capture_output=True, text=True)

    def test_refuses_sed_injection(self):
        for bad in ('accent = "#112233|e"', 'font = "x|w /tmp/x"', 'font = "a;b"',
                    'accent = "#12345"'):
            r = self.run_theme(f'name = "Evil"\n{bad}\n')
            self.assertEqual(r.returncode, 1, bad)
            self.assertIn("Refusing theme", r.stderr, bad)

    def test_refuses_bad_theme_name(self):
        r = subprocess.run(["bash", str(ROOT / "bin/hypora-theme"), "../x"],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 1)
        self.assertIn("Not a plain theme name", r.stderr)


class SwapfileTests(unittest.TestCase):
    def setUp(self):
        self.hs = load("hypora-security")
        self.tmp = Path(tempfile.mkdtemp())
        self.fstab = self.tmp / "fstab"
        self.fstab.write_text("UUID=abc / btrfs defaults 0 0")   # no trailing newline
        self.swap = self.tmp / "swapfile"
        patches = [mock.patch.object(self.hs, "FSTAB", self.fstab),
                   mock.patch.object(self.hs, "SWAPFILE", self.swap),
                   mock.patch.object(self.hs.os, "geteuid", return_value=0),
                   mock.patch.object(self.hs, "run", return_value=(0, ""))]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def state(self, **kw):
        base = {"exists": self.swap.is_file(), "active": False, "rootFs": "btrfs",
                "rootEncrypted": True, "supported": True}
        return {**base, **kw}

    def test_add_then_remove_keeps_other_lines(self):
        def fake_create(st, size):
            self.swap.write_text("x")
        with mock.patch.object(self.hs, "swapfile_state", side_effect=lambda: self.state()), \
             mock.patch.object(self.hs, "_create_swapfile", side_effect=fake_create):
            self.hs.add_swapfile("1g")
            text = self.fstab.read_text()
            self.assertEqual(text.count(f"{self.swap} none swap defaults,nofail 0 0"), 1)
            self.assertIn("UUID=abc / btrfs defaults 0 0\n", text)   # newline was added

            self.hs.remove_swapfile()
        self.assertEqual(self.fstab.read_text(), "UUID=abc / btrfs defaults 0 0\n")
        self.assertFalse(self.swap.exists())

    def test_refuses_plaintext_root_and_bad_size(self):
        with mock.patch.object(self.hs, "swapfile_state",
                               return_value=self.state(rootEncrypted=False)):
            with self.assertRaises(SystemExit):
                self.hs.add_swapfile("1g")
        with self.assertRaises(SystemExit):
            self.hs.add_swapfile("1g; rm -rf /")
        self.assertEqual(self.fstab.read_text(), "UUID=abc / btrfs defaults 0 0")


class SelinuxBootTests(unittest.TestCase):
    def test_disabled_is_refused(self):
        hs = load("hypora-security")
        with mock.patch.object(hs.os, "geteuid", return_value=0):
            with self.assertRaises(SystemExit):
                hs.set_selinux_boot("disabled")


if __name__ == "__main__":
    unittest.main()
