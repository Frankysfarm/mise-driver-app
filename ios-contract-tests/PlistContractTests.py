#!/usr/bin/env python3
import importlib.util
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "ensure_url_scheme", ROOT / "scripts" / "ensure_url_scheme.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class PlistContractTests(unittest.TestCase):
    def test_adds_scheme_without_replacing_existing_types(self):
        plist = {
            "CFBundleURLTypes": [
                {"CFBundleURLName": "existing", "CFBundleURLSchemes": ["other"]}
            ]
        }
        self.assertTrue(MODULE.ensure_url_scheme(plist))
        self.assertEqual(plist["CFBundleURLTypes"][0]["CFBundleURLSchemes"], ["other"])
        self.assertIn(
            "mise-driver",
            plist["CFBundleURLTypes"][1]["CFBundleURLSchemes"],
        )

    def test_is_idempotent(self):
        plist = {}
        self.assertTrue(MODULE.ensure_url_scheme(plist))
        self.assertFalse(MODULE.ensure_url_scheme(plist))
        matching = [
            entry
            for entry in plist["CFBundleURLTypes"]
            if "mise-driver" in entry.get("CFBundleURLSchemes", [])
        ]
        self.assertEqual(len(matching), 1)

    def test_script_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "Info.plist"
            with path.open("wb") as handle:
                plistlib.dump({"CFBundleIdentifier": "app.mise.driver"}, handle)
            command = [sys.executable, str(ROOT / "scripts" / "ensure_url_scheme.py"), str(path)]
            subprocess.run(command, check=True)
            subprocess.run(command, check=True)
            subprocess.run(
                [sys.executable, str(ROOT / "scripts" / "ensure_url_scheme.py"), "--check", str(path)],
                check=True,
            )
            with path.open("rb") as handle:
                result = plistlib.load(handle)
            matching = [
                entry
                for entry in result["CFBundleURLTypes"]
                if "mise-driver" in entry.get("CFBundleURLSchemes", [])
            ]
            self.assertEqual(len(matching), 1)


if __name__ == "__main__":
    unittest.main()
