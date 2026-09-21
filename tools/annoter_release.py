#!/usr/bin/env python3
"""Prepend un avertissement aux notes d'une release deja publiee.

Une release publiee ne se reecrit pas : ses fichiers restent tels quels. Ses
**notes**, elles, peuvent gagner un avertissement quand on decouvre apres coup
que la version est defectueuse. Laisser un binaire casse en ligne sans rien dire
couterait la confiance de la personne qui l'installe.

Le texte est passe par un **fichier**, jamais par la ligne de commande : entre
les accents graves et les apostrophes, un argument de shell finit toujours par
etre reecrit a notre insu.

Usage :
    python tools/annoter_release.py v0.1.3 avertissement.md
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path


def lire_notes(etiquette: str) -> str:
    resultat = subprocess.run(
        ["gh", "release", "view", etiquette, "--json", "body", "-q", ".body"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=True,
    )
    return resultat.stdout


def sans_avertissement(notes: str) -> str:
    """Retire un avertissement deja present, pour que l'ajout soit idempotent.

    Un avertissement est un bloc de citation en tete. Sans ce retrait, relancer
    le script empile les avertissements — ce qui est arrive, la premiere fois,
    parce que le texte avait ete abime par le shell entre-temps et ne
    correspondait donc plus a celui qu'on cherchait.

    Suppose que les notes d'origine ne commencent pas par une citation : celles
    que produit `publier_une_version.py` commencent par « Artefacts de ... ».
    """
    lignes = notes.split("\n")
    i = 0
    while i < len(lignes) and (not lignes[i].strip() or lignes[i].lstrip().startswith(">")):
        i += 1
    return "\n".join(lignes[i:])


def ecrire_notes(etiquette: str, notes: str) -> None:
    # `gh` est un binaire natif : il ne voit pas les chemins `/tmp` de Git Bash.
    # On ecrit donc dans le dossier temporaire de Windows.
    with tempfile.NamedTemporaryFile(
        "w", suffix=".md", delete=False, encoding="utf-8", newline="\n"
    ) as flux:
        flux.write(notes)
        chemin = Path(flux.name)

    try:
        subprocess.run(
            ["gh", "release", "edit", etiquette, "--notes-file", str(chemin)],
            check=True,
        )
    finally:
        chemin.unlink(missing_ok=True)


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2

    etiquette = sys.argv[1]
    avertissement = Path(sys.argv[2]).read_text(encoding="utf-8").rstrip() + "\n\n"
    notes = sans_avertissement(lire_notes(etiquette))

    ecrire_notes(etiquette, avertissement + notes)
    print(f"Avertissement ajoute aux notes de {etiquette}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
