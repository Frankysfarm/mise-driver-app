#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mise-offer-contract.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
cp ios-contract-tests/OfferContractTests.swift "$TMP_ROOT/main.swift"
swiftc ios-resources/OfferContract.swift "$TMP_ROOT/main.swift" -o "$TMP_ROOT/tests"
"$TMP_ROOT/tests"
cp ios-contract-tests/EmitNativeOfferFixture.swift "$TMP_ROOT/main.swift"
swiftc ios-resources/OfferContract.swift "$TMP_ROOT/main.swift" -o "$TMP_ROOT/emit-fixture"
"$TMP_ROOT/emit-fixture" > "$TMP_ROOT/native-offer.json"
node ios-contract-tests/validate-web-offer-contract.mjs "$TMP_ROOT/native-offer.json"
python3 ios-contract-tests/PlistContractTests.py
