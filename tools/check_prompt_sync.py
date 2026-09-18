#!/usr/bin/env python3
"""Verifie que les prompts d'analyse ne divergent pas entre l'application et le backend.

Le texte des prompts existe en deux copies : une en Dart (mode direct, ou
l'utilisateur fournit sa propre cle) et une en TypeScript (Edge Function, mode
production). Les deux doivent declarer le meme numero de version.

Ce controle est execute en CI. Il ne compare pas le texte caractere par
caractere — seul le numero de version fait foi, car une reformulation
volontaire est un changement de version, pas une divergence silencieuse.

Usage : python tools/check_prompt_sync.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# (libelle, fichier Dart, nom de constante Dart, fichier TS, nom de constante TS)
PAIRS = [
    (
        "prompt repas",
        ROOT / "app/lib/data/vision/meal_prompt.dart",
        "promptVersion",
        ROOT / "backend/supabase/functions/_shared/meal_prompt.ts",
        "PROMPT_VERSION",
    ),
    (
        "prompt etiquette",
        ROOT / "app/lib/data/vision/label_prompt.dart",
        "promptVersion",
        ROOT / "backend/supabase/functions/_shared/label_prompt.ts",
        "LABEL_PROMPT_VERSION",
    ),
]


# Motifs de recherche de la constante de version.
#
# En Dart la declaration porte presque toujours son type (`const String x = '...'`),
# mais rien ne l'impose : on rend donc l'annotation de type optionnelle. Sans cela
# le controle echouerait pour une raison qui n'est pas dans le fichier verifie.
# Les deux langages sont acceptes avec guillemets simples ou doubles.
DART_VERSION = r"const\s+(?:String\s+)?{name}\s*=\s*['\"]([^'\"]+)['\"]"
TS_VERSION = r"export\s+const\s+{name}\s*=\s*['\"]([^'\"]+)['\"]"


def extract(path: Path, template: str, name: str) -> str | None:
    if not path.exists():
        return None
    text = path.read_text(encoding="utf-8")
    match = re.search(template.format(name=re.escape(name)), text)
    return match.group(1) if match else None


def main() -> int:
    failures: list[str] = []

    for label, dart_path, dart_const, ts_path, ts_const in PAIRS:
        dart_version = extract(dart_path, DART_VERSION, dart_const)
        ts_version = extract(ts_path, TS_VERSION, ts_const)

        if dart_version is None:
            failures.append(f"{label} : version introuvable dans {dart_path.relative_to(ROOT)}")
            continue
        if ts_version is None:
            failures.append(f"{label} : version introuvable dans {ts_path.relative_to(ROOT)}")
            continue
        if dart_version != ts_version:
            failures.append(
                f"{label} : divergence — Dart '{dart_version}' vs TypeScript '{ts_version}'"
            )
            continue

        print(f"  OK  {label} : {dart_version}")

    if failures:
        print("\nEchec du controle de synchronisation des prompts :", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
