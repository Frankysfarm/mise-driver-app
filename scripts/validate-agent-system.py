#!/usr/bin/env python3
"""Validate the project-local Claude Code delivery finish scaffold.

No network access and no repository mutations. The validator checks JSON, YAML
(when PyYAML is installed), agent/skill frontmatter, duplicate names, script
syntax, and required files.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterator

ROOT = Path(__file__).resolve().parents[1]
ERRORS: list[str] = []
WARNINGS: list[str] = []

# Only project-owned source files belong to scaffold validation. Dependency
# trees, nested Claude worktrees and generated output can contain arbitrary
# third-party JSON/YAML/Python and must not affect this repository's result.
EXCLUDED_DIRECTORY_NAMES = {
    ".cache",
    ".git",
    ".gradle",
    ".next",
    ".pytest_cache",
    ".turbo",
    ".venv",
    "__pycache__",
    "build",
    "coverage",
    "DerivedData",
    "dist",
    "node_modules",
    "out",
    "Pods",
    "venv",
}
EXCLUDED_DIRECTORY_PATHS = {Path(".claude/worktrees")}


def error(message: str) -> None:
    ERRORS.append(message)


def warning(message: str) -> None:
    WARNINGS.append(message)


def is_excluded_directory(path: Path) -> bool:
    relative = path.relative_to(ROOT)
    return (
        path.name in EXCLUDED_DIRECTORY_NAMES
        or relative in EXCLUDED_DIRECTORY_PATHS
    )


def project_files(*suffixes: str) -> Iterator[Path]:
    """Yield source-tree files without descending into generated trees."""
    wanted = set(suffixes)
    for current, directories, filenames in os.walk(ROOT):
        current_path = Path(current)
        directories[:] = sorted(
            directory
            for directory in directories
            if not is_excluded_directory(current_path / directory)
        )
        for filename in sorted(filenames):
            path = current_path / filename
            if path.suffix in wanted:
                yield path


def parse_frontmatter(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        error(f"{path.relative_to(ROOT)}: YAML frontmatter fehlt")
        return {}
    try:
        _, raw, body = text.split("---", 2)
    except ValueError:
        error(f"{path.relative_to(ROOT)}: Frontmatter ist nicht geschlossen")
        return {}
    if not body.strip():
        error(f"{path.relative_to(ROOT)}: Prompt-/Skill-Body ist leer")

    try:
        import yaml  # type: ignore
    except ImportError:
        data: dict[str, Any] = {}
        for line in raw.splitlines():
            match = re.match(r"^([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$", line)
            if match:
                value = match.group(2).strip().strip('"').strip("'")
                data[match.group(1)] = value
        return data
    try:
        loaded = yaml.safe_load(raw)
    except Exception as exc:  # pragma: no cover - defensive
        error(f"{path.relative_to(ROOT)}: ungültiges YAML-Frontmatter: {exc}")
        return {}
    if not isinstance(loaded, dict):
        error(f"{path.relative_to(ROOT)}: Frontmatter muss ein Mapping sein")
        return {}
    return loaded


def validate_agents() -> None:
    names: dict[str, Path] = {}
    valid_models = {"fable", "opus", "sonnet", "haiku", "inherit"}
    valid_permissions = {
        "default", "acceptEdits", "auto", "dontAsk", "bypassPermissions", "plan", "manual"
    }
    for path in sorted((ROOT / ".claude" / "agents").rglob("*.md")):
        data = parse_frontmatter(path)
        name = data.get("name")
        description = data.get("description")
        if not isinstance(name, str) or not re.fullmatch(r"[a-z0-9-]+", name):
            error(f"{path.relative_to(ROOT)}: ungültiger oder fehlender Agentenname")
            continue
        if name in names:
            error(
                f"Doppelter Agentenname {name}: {names[name].relative_to(ROOT)} und {path.relative_to(ROOT)}"
            )
        names[name] = path
        if not isinstance(description, str) or not description.strip():
            error(f"{path.relative_to(ROOT)}: description fehlt")
        model = data.get("model", "inherit")
        if isinstance(model, str) and model not in valid_models and not model.startswith("claude-"):
            warning(f"{path.relative_to(ROOT)}: unbekannter model-Wert {model!r}")
        permission = data.get("permissionMode", "default")
        if permission not in valid_permissions:
            error(f"{path.relative_to(ROOT)}: ungültiger permissionMode {permission!r}")
        isolation = data.get("isolation")
        if isolation not in {None, "worktree"}:
            error(f"{path.relative_to(ROOT)}: isolation muss worktree oder leer sein")
    if len(names) < 20:
        error(f"Zu wenige Agenten gefunden: {len(names)}")


def validate_skills() -> None:
    names: dict[str, Path] = {}
    for path in sorted((ROOT / ".claude" / "skills").glob("*/SKILL.md")):
        data = parse_frontmatter(path)
        command = path.parent.name
        declared = data.get("name", command)
        if declared != command:
            warning(
                f"{path.relative_to(ROOT)}: Projekt-Skill wird als /{command} aufgerufen; name={declared!r} ist nur Anzeige"
            )
        if command in names:
            error(f"Doppelter Skill-Befehl /{command}")
        names[command] = path
        if not data.get("description"):
            error(f"{path.relative_to(ROOT)}: description fehlt")
    required = {
        "bootstrap-audit", "bug-fix-loop", "vertical-slice", "dispatch-evaluation",
        "release-gate", "shadow-rollout", "incident-learning",
    }
    missing = required - names.keys()
    if missing:
        error(f"Fehlende Skills: {', '.join(sorted(missing))}")


def validate_data_files() -> None:
    for path in project_files(".json"):
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:
            error(f"{path.relative_to(ROOT)}: ungültiges JSON: {exc}")
    yaml_paths = list(project_files(".yaml", ".yml"))
    try:
        import yaml  # type: ignore
    except ImportError:
        if yaml_paths:
            warning("PyYAML fehlt; Daten-YAML wurde nicht vollständig geparst")
    else:
        for path in yaml_paths:
            try:
                yaml.safe_load(path.read_text(encoding="utf-8"))
            except Exception as exc:
                error(f"{path.relative_to(ROOT)}: ungültiges YAML: {exc}")


def validate_scripts() -> None:
    for path in sorted((ROOT / "scripts").glob("*.sh")):
        proc = subprocess.run(
            ["bash", "-n", str(path)], text=True, capture_output=True, check=False
        )
        if proc.returncode:
            error(f"{path.relative_to(ROOT)}: Bash-Syntaxfehler: {proc.stderr.strip()}")
    for path in project_files(".py"):
        try:
            compile(path.read_text(encoding="utf-8"), str(path), "exec")
        except SyntaxError as exc:
            error(f"{path.relative_to(ROOT)}: Python-Syntaxfehler: {exc}")


def validate_required_files() -> None:
    required = [
        "00-START-HERE.md",
        "CLAUDE.md",
        "MASTER-PROMPT-FABLE-5.md",
        ".claude/settings.json",
        "docs/04-DISPATCH-ENGINE-SPEC.md",
        "docs/05-TRACKING-AND-ALERTING.md",
        "docs/10-DEFINITION-OF-DONE.md",
        "evals/scenarios.yaml",
        "evals/release-gates.yaml",
    ]
    for relative in required:
        if not (ROOT / relative).is_file():
            error(f"Pflichtdatei fehlt: {relative}")


def main() -> int:
    validate_required_files()
    validate_agents()
    validate_skills()
    validate_data_files()
    validate_scripts()

    print(f"Validated scaffold: {ROOT}")
    print(f"Agents: {len(list((ROOT / '.claude' / 'agents').rglob('*.md')))}")
    print(f"Skills: {len(list((ROOT / '.claude' / 'skills').glob('*/SKILL.md')))}")
    for item in WARNINGS:
        print(f"WARNING: {item}")
    for item in ERRORS:
        print(f"ERROR: {item}", file=sys.stderr)
    if ERRORS:
        print(f"FAILED: {len(ERRORS)} error(s), {len(WARNINGS)} warning(s)", file=sys.stderr)
        return 1
    print(f"OK: 0 errors, {len(WARNINGS)} warning(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
