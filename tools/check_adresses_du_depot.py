#!/usr/bin/env python3
"""Verifie que les adresses GitHub du code pointent vers le depot reel.

Pourquoi ce controle existe
--------------------------

L'application annonce deux adresses qui sortent du binaire :

  * `supportUrl`, affichee dans les parametres et sur les fiches de magasin ;
  * `openFoodFactsUserAgent`, dont la politique d'Open Food Facts exige qu'il
    permette d'identifier l'auteur de l'application.

Toutes deux pointaient vers `axox934/assiette`, un depot qui n'existe pas : le
lien d'assistance renvoyait 404, et l'identifiant envoye a Open Food Facts ne
permettait de joindre personne. Rien ne l'avait signale, parce qu'aucun
controle ne comparait ces adresses au depot reel.

La source de verite est le remote Git : c'est lui qui determine ou le code est
reellement publie. Le controle echoue si une adresse GitHub du code compile
designe un autre depot.

Usage : python3 tools/check_adresses_du_depot.py
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

MARQUEUR = "[adresse]"

# Sources qui finissent dans le binaire ou engagent l'editeur.
DOSSIERS = ("app/lib",)

# Adresses legitimement exterieures au depot : dependances citees, outils.
EXTERIEURES = {
    "flutter/flutter",
    "dart-lang/sdk",
    "actions/checkout",
}

MOTIF = re.compile(r"https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)")
MOTIF_SANS_DEPOT = re.compile(r"https://github\.com/([A-Za-z0-9_.-]+)(?![A-Za-z0-9_./-])")


def remote() -> str | None:
    """`proprietaire/depot` tel que declare par le remote `origin`."""
    resultat = subprocess.run(
        ["git", "remote", "get-url", "origin"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if resultat.returncode != 0:
        return None

    url = resultat.stdout.strip()
    # Deux formes : https://github.com/proprietaire/depot.git
    #              git@github.com:proprietaire/depot.git
    correspondance = re.search(r"github\.com[:/]([^/]+)/([^/\s]+?)(?:\.git)?$", url)
    if not correspondance:
        return None
    return f"{correspondance.group(1)}/{correspondance.group(2)}"


def sources() -> list[Path]:
    resultat = subprocess.run(
        ["git", "ls-files", "-z", *DOSSIERS],
        cwd=ROOT,
        capture_output=True,
        check=False,
    )
    noms = [n for n in resultat.stdout.decode("utf-8", errors="replace").split("\0") if n]
    return [ROOT / nom for nom in noms]


def main() -> int:
    attendu = remote()
    if attendu is None:
        print(
            f"{MARQUEUR} remote 'origin' illisible : impossible de savoir vers quel "
            "depot le code est publie. Le controle ne peut rien prouver.",
            file=sys.stderr,
        )
        return 1

    proprietaire, depot = attendu.split("/", 1)
    defauts: list[str] = []
    verifications = 0
    adresses_vues = 0

    for chemin in sources():
        if chemin.suffix.lower() not in (".dart", ".md", ".yaml", ".yml", ".json"):
            continue
        try:
            texte = chemin.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue

        relatif = chemin.relative_to(ROOT).as_posix()

        for correspondance in MOTIF.finditer(texte):
            verifications += 1
            adresses_vues += 1
            cible = f"{correspondance.group(1)}/{correspondance.group(2)}"
            if cible == attendu or cible in EXTERIEURES:
                continue
            ligne = texte[: correspondance.start()].count("\n") + 1
            defauts.append(
                f"{MARQUEUR} {relatif}:{ligne} annonce '{cible}' "
                f"alors que le depot est '{attendu}'"
            )

        # Une adresse reduite au compte (`https://github.com/proprietaire`) doit
        # designer le proprietaire du depot, pas un homonyme.
        for correspondance in MOTIF_SANS_DEPOT.finditer(texte):
            verifications += 1
            adresses_vues += 1
            if correspondance.group(1) == proprietaire:
                continue
            ligne = texte[: correspondance.start()].count("\n") + 1
            defauts.append(
                f"{MARQUEUR} {relatif}:{ligne} annonce le compte "
                f"'{correspondance.group(1)}' alors que le depot appartient a "
                f"'{proprietaire}'"
            )

    # Un controle qui ne lit aucune adresse ne prouve rien : l'application en
    # declare au moins une, donc zero est le signe que la mesure a echoue.
    if adresses_vues == 0:
        print(
            f"{MARQUEUR} aucune adresse GitHub trouvee dans {', '.join(DOSSIERS)} : "
            "la mesure n'a rien regarde",
            file=sys.stderr,
        )
        return 1

    if defauts:
        print("Adresses GitHub incoherentes avec le depot :", file=sys.stderr)
        for defaut in defauts:
            print(f"  - {defaut}", file=sys.stderr)
        print(f"\n{len(defauts)} defaut(s), {verifications} verifications.", file=sys.stderr)
        return 1

    print(f"{verifications} verifications sur {adresses_vues} adresses — depot '{attendu}'.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
