#!/usr/bin/env bash
set -euo pipefail

if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[secret-check] Kein Git-Repository; Dateinamenprüfung übersprungen."
  exit 0
fi

bad_files="$(
  git ls-files |
    grep -E '(^|/)(\.env($|\.)|id_rsa$|id_ed25519$|.*\.p12$|.*\.pfx$|.*\.key$|credentials(\.json)?$|service-account.*\.json$)' ||
    true
)"

if [[ -n "${bad_files}" ]]; then
  echo "[secret-check] Potenziell geheime Dateien sind versioniert:"
  echo "${bad_files}"
  exit 1
fi

patterns='BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|xox[baprs]-[0-9A-Za-z-]{10,}'
matches="$(git grep -nE "${patterns}" -- . ':(exclude)*.md' ':(exclude)*.lock' 2>/dev/null || true)"

if [[ -n "${matches}" ]]; then
  echo "[secret-check] Potenzielles Secret-Muster gefunden. Manuell prüfen:"
  echo "${matches}"
  exit 1
fi

echo "[secret-check] OK"
