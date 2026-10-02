#!/usr/bin/env python3
"""Declare the reviewed OS-only encryption use of this native wrapper.

Native encryption: Apple CryptoKit (GPS at rest), Security/Keychain, and
URLSession/WKWebView HTTPS. No proprietary crypto implementation is bundled.
Reassess this declaration when adding SDKs or encryption implementations.
See docs/TESTFLIGHT-RELEASE.md for evidence and Apple's guidance.
"""
import argparse
import plistlib
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('plist', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    data = plistlib.loads(args.plist.read_bytes())
    key = 'ITSAppUsesNonExemptEncryption'
    if 'ITSEncryptionExportComplianceCode' in data or data.get(key) is True:
        raise SystemExit('Existing non-exempt encryption declaration requires review')
    if args.check:
        if data.get(key) is not False:
            raise SystemExit('Archive is missing the reviewed boolean encryption declaration')
    else:
        data[key] = False
        args.plist.write_bytes(plistlib.dumps(data, sort_keys=False))
    print('OS-only encryption declaration: verified')


if __name__ == '__main__':
    main()
