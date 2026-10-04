#!/usr/bin/env python3
"""Idempotently ensure the native offer ACK/auth URL scheme exists."""

from __future__ import annotations

import argparse
import plistlib
import sys
from pathlib import Path


def ensure_url_scheme(plist: dict, scheme: str = "mise-driver", bundle_id: str = "app.mise.driver") -> bool:
    url_types = plist.setdefault("CFBundleURLTypes", [])
    for entry in url_types:
        schemes = entry.get("CFBundleURLSchemes", [])
        if scheme in schemes:
            return False
    url_types.append(
        {
            "CFBundleURLName": bundle_id + ".offer-contract",
            "CFBundleURLSchemes": [scheme],
        }
    )
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--scheme", default="mise-driver")
    parser.add_argument("--bundle-id", default="app.mise.driver")
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    check_only = args.check
    path = args.path
    with path.open("rb") as handle:
        plist = plistlib.load(handle)
    changed = ensure_url_scheme(plist, args.scheme, args.bundle_id)
    if check_only:
        return 1 if changed else 0
    with path.open("wb") as handle:
        plistlib.dump(plist, handle, sort_keys=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
