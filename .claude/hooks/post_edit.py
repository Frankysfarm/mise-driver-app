#!/usr/bin/env python3
"""Fast syntax validation for files touched by Claude Code.

The hook reads Claude Code's JSON payload from stdin. It performs only local,
deterministic checks and never formats or mutates files.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"[post-edit-check] {message}", file=sys.stderr)
    raise SystemExit(2)


def run(command: list[str], cwd: Path) -> None:
    proc = subprocess.run(
        command,
        cwd=str(cwd),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
        check=False,
    )
    if proc.returncode != 0:
        fail(f"Syntaxprüfung fehlgeschlagen: {' '.join(command)}\n{proc.stdout[-4000:]}")


try:
    payload = json.load(sys.stdin)
except Exception:
    # A malformed or absent hook payload must not break normal editing.
    raise SystemExit(0)

tool_input = payload.get("tool_input") or {}
raw_path = tool_input.get("file_path") or tool_input.get("path")
if not raw_path:
    raise SystemExit(0)

path = Path(raw_path)
if not path.is_absolute():
    project_dir = Path(payload.get("cwd") or ".")
    path = project_dir / path

if not path.exists() or not path.is_file():
    raise SystemExit(0)

suffix = path.suffix.lower()
cwd = path.parent

try:
    if suffix == ".py":
        compile(path.read_text(encoding="utf-8"), str(path), "exec")
    elif suffix in {".json", ".jsonc"} and suffix != ".jsonc":
        json.loads(path.read_text(encoding="utf-8"))
    elif suffix in {".sh", ".bash"}:
        run(["bash", "-n", path.name], cwd)
    elif suffix in {".yaml", ".yml"}:
        try:
            import yaml  # type: ignore
        except Exception:
            print("[post-edit-check] PyYAML fehlt; YAML-Syntax wird im Full Verify geprüft.")
        else:
            yaml.safe_load(path.read_text(encoding="utf-8"))
except Exception as exc:
    fail(f"{path}: {exc}")

print(f"[post-edit-check] OK: {path}")
