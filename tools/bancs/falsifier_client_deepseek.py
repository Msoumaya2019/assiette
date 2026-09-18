#!/usr/bin/env python3
"""Falsifie les tests du client DeepSeek.

Le client envoyait sa requete sans le champ `thinking`. Or le mode reflexion est
**actif par defaut, effort `high`**, et ses jetons sont factures comme des jetons
de sortie. Le fournisseur appliquait donc son defaut, et `temperature` etait
ignore en silence.

Ce banc restaure le defaut exact et verifie que les tests tombent.

Usage : python3 tools/bancs/falsifier_client_deepseek.py
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, Banc  # noqa: E402

SCRIPT = RACINE / "tools" / "check_prompt_sync.py"  # inutilise : ce banc n'appelle pas de controle
CLIENT = "backend/supabase/functions/_shared/deepseek.ts"
# Chemin relatif a `backend/`, puisque c'est le dossier de travail du processus.
TESTS = "tests/deepseek_test.ts"

# Le banc doit poser son environnement lui-meme : lance depuis un script, il
# n'herite pas d'un `export PATH` fait a la main.
DENO = Path.home() / ".deno" / "bin" / ("deno.exe" if os.name == "nt" else "deno")

LIGNE_REFLEXION = b'    thinking: { type: thinking ? "enabled" : "disabled" },\n'
LIGNE_TEMPERATURE = b'  if (!thinking) body.temperature = temperature;\n'


class BancDeepSeek(Banc):
    """Le banc des controles compare des marqueurs ; celui-ci compare des tests."""

    def executer(self):  # type: ignore[override]
        resultat = subprocess.run(
            [str(DENO), "test", "--unstable", "--allow-net", "--allow-env", TESTS],
            cwd=RACINE / "backend",
            capture_output=True,
            text=True,
            check=False,
        )
        return ResultatDeepSeek(resultat.returncode, resultat.stdout, resultat.stderr)


class ResultatDeepSeek:
    def __init__(self, code: int, sortie: str, erreur: str) -> None:
        self.code = code
        self.sortie = sortie
        self.erreur = erreur

    @property
    def texte(self) -> str:
        return f"{self.sortie}\n{self.erreur}"


def principal() -> int:
    if not DENO.exists():
        print(f"deno introuvable : {DENO}", file=sys.stderr)
        return 2

    banc = BancDeepSeek(SCRIPT)

    initial = banc.executer()
    print(f"etat initial : code {initial.code}")
    if initial.code != 0:
        print(initial.texte[-2000:], file=sys.stderr)
        print("les tests echouent deja avant toute mutation.", file=sys.stderr)
        return 2

    def reflexion_non_annoncee() -> None:
        # Le defaut d'origine : le champ n'est pas transmis du tout.
        banc.suivre(CLIENT).muter(LIGNE_REFLEXION, b"")

    def temperature_toujours_envoyee() -> None:
        # Le second defaut : `temperature` transmis meme en mode reflexion, ou le
        # fournisseur l'ignore en silence.
        banc.suivre(CLIENT).muter(
            LIGNE_TEMPERATURE, b"  body.temperature = temperature;\n"
        )

    banc.cas("champ thinking non transmis", "le mode reflexion est desactive par defaut", reflexion_non_annoncee)
    banc.cas("temperature envoyee en mode reflexion", "temperature n'est pas envoye", temperature_toujours_envoyee)

    code = banc.tableau()

    final = banc.executer()
    print(f"\netat final : code {final.code}")
    if final.code != 0:
        print(final.texte[-1500:], file=sys.stderr)
        return 1

    if code != 0:
        return code

    print("vert — les deux defauts sont detectes, et les tests repassent.")
    return 0


if __name__ == "__main__":
    sys.exit(principal())
