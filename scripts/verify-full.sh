#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${ROOT}"

./scripts/verify-fast.sh

echo "== Full verification =="

run_js_script() {
  local script="$1"
  local code=0
  python3 - "${script}" <<'PY' || code=$?
import json, pathlib, subprocess, sys
name = sys.argv[1]
p = pathlib.Path("package.json")
if not p.exists():
    raise SystemExit(3)
data = json.loads(p.read_text())
if name not in (data.get("scripts") or {}):
    raise SystemExit(4)
if pathlib.Path("pnpm-lock.yaml").exists():
    cmd = ["pnpm", "run", name]
elif pathlib.Path("yarn.lock").exists():
    cmd = ["yarn", name]
else:
    cmd = ["npm", "run", name]
print("+", " ".join(cmd))
raise SystemExit(subprocess.run(cmd, check=False).returncode)
PY
  if [[ ${code} -eq 3 || ${code} -eq 4 ]]; then
    return 0
  fi
  return ${code}
}

if [[ -f package.json ]]; then
  run_js_script test
  run_js_script test:integration
  run_js_script test:e2e
  run_js_script test:dispatch
  run_js_script test:load
  run_js_script build
fi

if [[ -f pyproject.toml || -f requirements.txt || -f setup.cfg ]]; then
  if command -v pytest >/dev/null 2>&1 && [[ -d tests ]]; then
    echo "+ pytest -q"
    pytest -q
  fi
fi

if [[ -x ./scripts/project-verify-full.sh ]]; then
  echo "+ ./scripts/project-verify-full.sh"
  ./scripts/project-verify-full.sh
else
  echo "[verify-full] Kein projektspezifisches scripts/project-verify-full.sh vorhanden."
  echo "[verify-full] Mobile-Geräte-, Staging-, Replay- und Lastprüfungen müssen im realen Repository ergänzt werden."
fi

echo "== Full verification complete =="
