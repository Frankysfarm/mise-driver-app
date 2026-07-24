#!/usr/bin/env python3
"""Idempotently ensure the native offer ACK/auth URL scheme exists."""

from __future__ import annotations

import plistlib
import sys
from pathlib import Path


def ensure_url_scheme(plist: dict, scheme: str = "mise-driver") -> bool:
    url_types = plist.setdefault("CFBundleURLTypes", [])
    for entry in url_types:
        schemes = entry.get("CFBundleURLSchemes", [])
        if scheme in schemes:
            return False
    url_types.append(
        {
            "CFBundleURLName": "app.mise.driver.offer-contract",
            "CFBundleURLSchemes": [scheme],
        }
    )
    return True


def main() -> int:
    check_only = len(sys.argv) == 3 and sys.argv[1] == "--check"
    if len(sys.argv) not in (2, 3) or (len(sys.argv) == 3 and not check_only):
        print("usage: ensure_url_scheme.py [--check] Info.plist", file=sys.stderr)
        return 2
    path = Path(sys.argv[2] if check_only else sys.argv[1])
    with path.open("rb") as handle:
        plist = plistlib.load(handle)
    changed = ensure_url_scheme(plist)
    if check_only:
        return 1 if changed else 0
    with path.open("wb") as handle:
        plistlib.dump(plist, handle, sort_keys=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
