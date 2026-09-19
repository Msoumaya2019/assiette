#!/usr/bin/env python3
"""Lance tous les bancs de `tools/bancs/` et rapporte leur code de sortie.

Ce lanceur existe pour une raison precise : lire le code de sortie **apres un
tube** rend celui du tube, pas celui de la commande. Trois bancs ont ainsi ete
annonces verts alors que l'un d'eux avait plante. Ici, chaque code de sortie est
lu directement sur `subprocess.run(...).returncode`.

Usage : python3 tools/lancer_bancs.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
BANCS = RACINE / "tools" / "bancs"

# Le banc du serveur a besoin de Deno ; les autres, de rien d'autre que Python.
ORDRE = [
    "falsifier_fins_de_ligne.py",
    "falsifier_ios.py",
    "falsifier_adresses.py",
    "falsifier_client_deepseek_dart.py",
    "falsifier_proxy_dart.py",
    "falsifier_version_build.py",
    "falsifier_client_deepseek.py",
]


def main() -> int:
    resultats: list[tuple[str, int]] = []

    for nom in ORDRE:
        chemin = BANCS / nom
        if not chemin.is_file():
            print(f"  ABSENT  {nom}", file=sys.stderr)
            resultats.append((nom, 1))
            continue

        print(f"\n=== {nom} ===", flush=True)
        resultat = subprocess.run(
            [sys.executable, str(chemin)],
            cwd=RACINE,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        sortie = (resultat.stdout or "").strip().splitlines()
        for ligne in sortie:
            print(f"    {ligne}")
        if resultat.stderr.strip():
            for ligne in resultat.stderr.strip().splitlines():
                print(f"    ! {ligne}", file=sys.stderr)

        resultats.append((nom, resultat.returncode))

    print("\n" + "=" * 60)
    for nom, code in resultats:
        print(f"  {'vert' if code == 0 else f'ECHEC (code {code})':<14} {nom}")

    rates = [nom for nom, code in resultats if code != 0]
    print()
    if rates:
        print(f"{len(rates)} banc(s) en echec sur {len(resultats)}.", file=sys.stderr)
        return 1
    print(f"{len(resultats)} bancs, tous verts.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
