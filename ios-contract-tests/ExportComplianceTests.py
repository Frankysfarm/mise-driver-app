#!/usr/bin/env python3
"""Check the exact plist field Apple's upload processing uses."""
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts' / 'ensure_export_compliance.py'


class ExportComplianceTests(unittest.TestCase):
    def test_prepares_and_checks_boolean_without_changing_other_permissions(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'Info.plist'
            target.write_bytes(plistlib.dumps({'NSCameraUsageDescription': 'QR scannen'}))
            command = [sys.executable, str(SCRIPT), str(target)]
            subprocess.run(command, check=True, capture_output=True)
            first = target.read_bytes()
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(first, target.read_bytes())
            values = plistlib.loads(first)
            self.assertIs(values['ITSAppUsesNonExemptEncryption'], False)
            self.assertEqual(values['NSCameraUsageDescription'], 'QR scannen')
            subprocess.run(command + ['--check'], check=True, capture_output=True)

    def test_missing_or_string_value_cannot_pass_archive_check(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'Info.plist'
            for values in ({}, {'ITSAppUsesNonExemptEncryption': 'false'},
                           {'ITSAppUsesNonExemptEncryption': True}):
                target.write_bytes(plistlib.dumps(values))
                result = subprocess.run([sys.executable, str(SCRIPT), str(target), '--check'],
                                        capture_output=True)
                self.assertNotEqual(result.returncode, 0)

    def test_declared_non_exempt_encryption_requires_review_not_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'Info.plist'
            for values in ({'ITSAppUsesNonExemptEncryption': True},
                           {'ITSEncryptionExportComplianceCode': 'approved-code'}):
                target.write_bytes(plistlib.dumps(values))
                before = target.read_bytes()
                result = subprocess.run([sys.executable, str(SCRIPT), str(target)],
                                        capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(before, target.read_bytes())


if __name__ == '__main__':
    unittest.main()
