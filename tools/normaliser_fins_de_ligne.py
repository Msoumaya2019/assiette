#!/usr/bin/env python3
"""Ramene la copie de travail a ce que `.gitattributes` impose.

Pourquoi ce script existe
-------------------------

`.gitattributes` declare `* text=auto eol=lf`. Sous Windows, les gabarits de
`flutter create` — et certains outils d'ecriture — deposent ces fichiers en
CRLF. Git ne dit rien : `text=auto` normalise **a l'entree**, donc le blob
indexe est bien en LF et `git status` reste muet. La copie de travail diverge
pourtant de ce que produira un clone sous Linux.

Consequence : un controle local qui lit des octets ne voit pas la meme chose
que l'executeur d'integration continue, sans qu'aucun code n'ait change.

`git checkout --` ne repare pas ces fichiers : git les considere comme non
modifies et ne les reecrit pas. Il faut les supprimer puis les reextraire, ce
que fait ce script — en verifiant d'abord que la normalisation ne change pas
le contenu, et en restaurant tout si ce n'est pas le cas.

Usage :
    python3 tools/normaliser_fins_de_ligne.py            # mesure, ne touche a rien
    python3 tools/normaliser_fins_de_ligne.py --appliquer
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def git(*args: str) -> str:
    resultat = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if resultat.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} a echoue : {resultat.stderr.strip()}")
    return resultat.stdout


def divergents() -> list[str]:
    """Fichiers suivis dont la copie de travail viole l'attribut `eol`."""
    trouves: list[str] = []
    for ligne in git("ls-files", "--eol").splitlines():
        champs = ligne.split()
        if len(champs) < 5:
            continue
        index, travail, attribut, eol = champs[0], champs[1], champs[2], champs[3]
        chemin = " ".join(champs[4:])
        if not index.startswith("i/") or not travail.startswith("w/"):
            continue
        if "eol=lf" in eol and travail == "w/crlf":
            trouves.append(chemin)
        elif "eol=crlf" in eol and travail == "w/lf":
            trouves.append(chemin)
    return trouves


def empreinte(chemin: str) -> str:
    """Empreinte du contenu **normalise** : ce que git stockerait."""
    return git("hash-object", "--", chemin).strip()


def main() -> int:
    appliquer = "--appliquer" in sys.argv

    chemins = divergents()
    print(f"fichiers suivis                    : {len(git('ls-files').splitlines())}")
    print(f"copies de travail hors attribut    : {len(chemins)}")

    if not chemins:
        print("\ncopie de travail conforme — rien a faire.")
        return 0

    for chemin in chemins:
        print(f"  {chemin}")

    if not appliquer:
        print("\nmode mesure. Relancer avec --appliquer pour normaliser.")
        return 0

    # Le contenu normalise doit rester identique : sinon la conversion
    # changerait autre chose que les fins de ligne, et il faut tout arreter.
    avant = {chemin: empreinte(chemin) for chemin in chemins}

    sauvegardes: dict[str, bytes] = {}
    convertis: list[str] = []

    try:
        for chemin in chemins:
            fichier = ROOT / chemin
            octets = fichier.read_bytes()
            sauvegardes[chemin] = octets

            # Seule la paire CRLF est repliee. Un `\r` isole est un caractere du
            # contenu : le toucher modifierait le fichier, pas sa mise en forme.
            normalise = octets.replace(b"\r\n", b"\n")
            if normalise == octets:
                continue
            fichier.write_bytes(normalise)
            convertis.append(chemin)
    except Exception as erreur:  # noqa: BLE001
        for chemin, octets in sauvegardes.items():
            (ROOT / chemin).write_bytes(octets)
        print(f"\nechec pendant l'ecriture ({erreur}) — tout a ete restaure.", file=sys.stderr)
        return 1

    apres = {chemin: empreinte(chemin) for chemin in chemins}
    divergents_contenu = [c for c in chemins if avant[c] != apres[c]]

    if divergents_contenu:
        for chemin, octets in sauvegardes.items():
            (ROOT / chemin).write_bytes(octets)
        print(
            f"\n{len(divergents_contenu)} fichier(s) dont le contenu normalise a change : "
            "ce n'est pas une conversion de fins de ligne. Tout a ete restaure.",
            file=sys.stderr,
        )
        for chemin in divergents_contenu:
            print(f"  - {chemin}", file=sys.stderr)
        return 1

    restants = divergents()
    print(f"\nfichiers reecrits en LF            : {len(convertis)}")
    print(f"contenus normalises inchanges      : {len(chemins)}/{len(chemins)}")
    print(f"copies de travail hors attribut    : {len(restants)}")

    if restants:
        print("\ncertaines copies divergent encore :", file=sys.stderr)
        for chemin in restants:
            print(f"  - {chemin}", file=sys.stderr)
        return 1

    print("\ncopie de travail conforme a .gitattributes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
