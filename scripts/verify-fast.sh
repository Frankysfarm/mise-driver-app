#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${ROOT}"

echo "== Fast verification =="

python3 scripts/validate-agent-system.py

./scripts/check-no-secrets.sh

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
  run_js_script lint
  run_js_script typecheck
  run_js_script test:unit
fi

if [[ -f pyproject.toml || -f requirements.txt || -f setup.cfg ]]; then
  if command -v ruff >/dev/null 2>&1; then
    echo "+ ruff check ."
    ruff check .
  fi
  if [[ -d tests/unit ]] && command -v pytest >/dev/null 2>&1; then
    echo "+ pytest -q tests/unit"
    pytest -q tests/unit
  fi
fi

if [[ -f go.mod ]] && command -v go >/dev/null 2>&1; then
  echo "+ go test ./..."
  go test ./...
fi

if [[ -f Cargo.toml ]] && command -v cargo >/dev/null 2>&1; then
  echo "+ cargo check"
  cargo check
  echo "+ cargo test --lib"
  cargo test --lib
fi

echo "== Fast verification complete =="
