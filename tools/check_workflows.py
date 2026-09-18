#!/usr/bin/env python3
"""Valide les fichiers de workflow GitHub Actions avant de pousser.

Un YAML invalide ne casse rien en local : il casse sur GitHub, apres le push,
et le message d'erreur est peu exploitable. Ce controle attrape la faute tot.

Trois niveaux de verification :
  1. le YAML est syntaxiquement valide ;
  2. chaque workflow declare un nom, un declencheur et au moins un job ;
  3. chaque job declare un runner et au moins une etape.

Si PyYAML est absent, le controle le signale et se limite a une analyse
structurelle par indentation, plutot que de faire semblant d'avoir valide.

Usage : python3 tools/check_workflows.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKFLOWS_DIR = ROOT / ".github" / "workflows"

try:
    import yaml  # type: ignore
except ImportError:  # pragma: no cover
    yaml = None


def load(path: Path) -> dict:
    with open(path, encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def check_without_yaml(path: Path) -> list[str]:
    """Repli : on verifie ce qui est verifiable sans analyseur YAML."""
    problems: list[str] = []
    lines = path.read_text(encoding="utf-8").splitlines()

    if not any(line.startswith("name:") for line in lines):
        problems.append(f"{path.name} : aucune cle 'name:' en racine")
    if not any(line.startswith("on:") for line in lines):
        problems.append(f"{path.name} : aucun declencheur 'on:' en racine")
    if not any(line.startswith("jobs:") for line in lines):
        problems.append(f"{path.name} : aucune section 'jobs:'")

    for index, line in enumerate(lines, start=1):
        if "\t" in line:
            problems.append(f"{path.name}:{index} : tabulation interdite en YAML")

    return problems


def main() -> int:
    if not WORKFLOWS_DIR.is_dir():
        print(f"Dossier introuvable : {WORKFLOWS_DIR}", file=sys.stderr)
        return 1

    files = sorted(WORKFLOWS_DIR.glob("*.y*ml"))
    if not files:
        print("Aucun workflow trouve.", file=sys.stderr)
        return 1

    if yaml is None:
        print("PyYAML absent : validation structurelle seule (installez pyyaml pour un controle complet).")

    problems: list[str] = []

    for path in files:
        if yaml is None:
            problems.extend(check_without_yaml(path))
            continue

        try:
            document = load(path)
        except yaml.YAMLError as error:
            problems.append(f"{path.name} : YAML invalide — {error}")
            continue

        if not isinstance(document, dict):
            problems.append(f"{path.name} : le document racine doit etre un objet")
            continue

        # `on` peut etre interprete comme le booleen True par YAML 1.1.
        if "name" not in document:
            problems.append(f"{path.name} : cle 'name' manquante")
        if "on" not in document and True not in document:
            problems.append(f"{path.name} : declencheur 'on' manquant")

        jobs = document.get("jobs")
        if not isinstance(jobs, dict) or not jobs:
            problems.append(f"{path.name} : aucun job declare")
            continue

        for job_name, job in jobs.items():
            if not isinstance(job, dict):
                problems.append(f"{path.name} : job '{job_name}' mal forme")
                continue
            if "runs-on" not in job:
                problems.append(f"{path.name} : job '{job_name}' sans 'runs-on'")
            steps = job.get("steps")
            if not isinstance(steps, list) or not steps:
                problems.append(f"{path.name} : job '{job_name}' sans etapes")

    if problems:
        print("Workflows invalides :", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    for path in files:
        print(f"  OK  {path.name}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
