#!/usr/bin/env python3
"""Verifie `tools/version_build.sh` sur tous ses cas, hors GitHub Actions.

Pourquoi ce controle existe
---------------------------
`version_build.sh` decide de la version inscrite dans l'APK, l'AAB **et** l'IPA.
Une erreur ici ne se voit qu'a la publication — apres vingt minutes de
compilation, et sur un tag, donc sur une version que l'on ne peut pas rejouer
sans creer un nouveau tag. C'est le pire rapport cout/visibilite du depot.

Ce qu'il verifie, et pourquoi chacun de ces cas
-----------------------------------------------
  1. tag `v0.1.1`          -> 0.1.1 + numero de run (le cas nominal)
  2. branche               -> la version du pubspec (compilation de controle)
  3. version imposee       -> celle saisie (l'option de `workflow_dispatch`)
  4. tag + version imposee -> le tag gagne (deux sources, un seul vainqueur)
  5. tag sans prefixe `v`  -> accepte (`0.1.3` est un tag valide)
  6. pubspec absent        -> echec franc, pas une version vide
  7. `version:` illisible  -> echec franc (un pubspec mal forme ne doit pas
                              produire `--build-name=`, qui echouerait bien
                              plus loin avec une erreur qui ne nomme pas la cause)
  8. tag non numerique     -> refus franc (`release-2.0`, `1.2.3-beta`, `../x`)

Le cas 8 merite un mot. Pour iOS, Flutter retire **en silence** tout caractere
hors `[0-9.]` avant d'ecrire `CFBundleShortVersionString` (`build_info.dart`,
`validatedBuildNameForPlatform`). Un tag `release-2.0` donnerait donc `2.0.0`
sur iOS et `release-2.0` sur Android : deux versions pour un meme tag, sans
aucun signal. Le script refuse desormais ces valeurs, et ce cas le tient.

Chaque cas de refus verifie aussi **la cause annoncee** dans le message
d'erreur, pas seulement le code de sortie. Sans cela, un refus obtenu pour une
autre raison passerait pour le refus attendu — c'est arrive : le cas « pubspec
absent » reussissait alors que son garde-fou avait disparu du script, parce
qu'un garde-fou situe plus loin attrapait le vide laisse derriere.

Ce que ce controle ne peut PAS voir : ce que Flutter fait de `--build-name`
une fois recu. Il verifie la valeur **passee**, pas la valeur **inscrite**. La
seule preuve de la seconde est d'ouvrir un binaire livre.

Usage : python3 tools/verifier_version_build.py
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SCRIPT = RACINE / "tools" / "version_build.sh"

VARIABLES_GITHUB = (
    "GITHUB_REF_TYPE",
    "GITHUB_REF_NAME",
    "GITHUB_RUN_NUMBER",
    "BUILD_NAME_IMPOSE",
    "GITHUB_OUTPUT",
)


class Echec(Exception):
    """Un cas attendu n'a pas rendu ce qu'il devait rendre."""


def executer(
    env_sup: dict[str, str],
    pubspec: str | None = None,
) -> tuple[int, dict[str, str], str]:
    """Lance le script dans un environnement isole.

    Les variables GitHub sont retirees de l'environnement courant avant d'etre
    reposees : sans cela, un `GITHUB_REF_TYPE` herite de l'appelant ferait
    passer un cas pour un autre, et le controle mesurerait l'environnement de la
    machine au lieu du script.
    """
    with tempfile.TemporaryDirectory() as dossier:
        sortie = Path(dossier) / "github_output"
        sortie.write_text("", encoding="utf-8")

        env = {cle: valeur for cle, valeur in os.environ.items() if cle not in VARIABLES_GITHUB}
        env["GITHUB_OUTPUT"] = str(sortie)
        env.update(env_sup)

        commande = ["bash", str(SCRIPT)]
        if pubspec is not None:
            commande.append(pubspec)

        resultat = subprocess.run(
            commande,
            env=env,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
        )

        sorties: dict[str, str] = {}
        for ligne in sortie.read_text(encoding="utf-8").splitlines():
            if "=" in ligne:
                cle, _, valeur = ligne.partition("=")
                sorties[cle] = valeur

        return resultat.returncode, sorties, resultat.stderr


def cas(
    libelle: str,
    env_sup: dict[str, str],
    attendu: dict[str, str],
    pubspec: str | None = None,
    doit_echouer: bool = False,
    cause: str | None = None,
) -> bool:
    """Un cas, nominal ou de refus.

    `cause` n'est pas un ornement. Un refus ne vaut que s'il **nomme sa cause** :
    un script qui sortirait en erreur pour une raison quelconque passerait un
    controle qui se contente de lire le code de sortie. Mesure faite : le cas
    « pubspec absent » reussissait alors meme que le garde-fou avait disparu du
    script, parce qu'un autre garde-fou, plus loin, attrapait le vide. Le cas ne
    distinguait donc rien. Exiger le message oblige chaque refus a etre celui
    qu'on annonce.
    """
    try:
        code, sorties, erreur = executer(env_sup, pubspec)
    except (OSError, subprocess.SubprocessError) as probleme:
        print(f"  ECHEC  {libelle}")
        print(f"         impossible d'executer le script : {probleme}")
        return False

    if doit_echouer:
        if code == 0:
            print(f"  ECHEC  {libelle}")
            print(f"         le script a reussi alors qu'il devait refuser — sorties : {sorties}")
            return False
        if cause is not None and cause not in erreur:
            print(f"  ECHEC  {libelle}")
            print(f"         refuse, mais pas pour la cause annoncee.")
            print(f"         attendu dans le message d'erreur : {cause!r}")
            print(f"         message recu : {erreur.strip()!r}")
            return False
        print(f"  ok     {libelle}  (refuse : {cause or 'sans cause precisee'})")
        return True

    if code != 0:
        print(f"  ECHEC  {libelle}")
        print(f"         code {code} — {erreur.strip().splitlines()[-1] if erreur.strip() else 'sans message'}")
        return False

    manquants = {cle: valeur for cle, valeur in attendu.items() if sorties.get(cle) != valeur}
    if manquants:
        print(f"  ECHEC  {libelle}")
        for cle, valeur in manquants.items():
            print(f"         {cle} : attendu {valeur!r}, obtenu {sorties.get(cle)!r}")
        return False

    print(f"  ok     {libelle}  ({' '.join(f'{c}={v}' for c, v in attendu.items())})")
    return True


def main() -> int:
    if not SCRIPT.is_file():
        print(f"introuvable : {SCRIPT}", file=sys.stderr)
        return 1

    print(f"Controle de {SCRIPT.name} sur ses cas nominaux et ses cas limites.\n")

    resultats = [
        cas(
            "tag v0.1.1",
            {"GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": "v0.1.1", "GITHUB_RUN_NUMBER": "42"},
            {"name": "0.1.1", "number": "42", "version": "0.1.1+42"},
        ),
        cas(
            "branche : version du pubspec",
            {"GITHUB_REF_TYPE": "branch", "GITHUB_REF_NAME": "main", "GITHUB_RUN_NUMBER": "7"},
            {"name": "0.1.0", "number": "1", "version": "0.1.0+1"},
        ),
        cas(
            "version imposee a la main",
            {
                "GITHUB_REF_TYPE": "branch",
                "GITHUB_REF_NAME": "main",
                "GITHUB_RUN_NUMBER": "9",
                "BUILD_NAME_IMPOSE": "0.2.0",
            },
            {"name": "0.2.0", "number": "9", "version": "0.2.0+9"},
        ),
        cas(
            "tag prioritaire sur la version imposee",
            {
                "GITHUB_REF_TYPE": "tag",
                "GITHUB_REF_NAME": "v0.1.2",
                "GITHUB_RUN_NUMBER": "3",
                "BUILD_NAME_IMPOSE": "9.9.9",
            },
            {"name": "0.1.2", "number": "3", "version": "0.1.2+3"},
        ),
        cas(
            "tag sans prefixe v",
            {"GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": "0.1.3", "GITHUB_RUN_NUMBER": "5"},
            {"name": "0.1.3", "number": "5", "version": "0.1.3+5"},
        ),
        cas(
            "pubspec absent : refus franc",
            {"GITHUB_REF_TYPE": "branch", "GITHUB_REF_NAME": "main", "GITHUB_RUN_NUMBER": "1"},
            {},
            pubspec="app/pubspec-inexistant.yaml",
            doit_echouer=True,
            cause="pubspec introuvable",
        ),
        cas(
            "pubspec sans version : refus franc",
            {"GITHUB_REF_TYPE": "branch", "GITHUB_REF_NAME": "main", "GITHUB_RUN_NUMBER": "1"},
            {},
            pubspec="app/ios/Podfile",
            doit_echouer=True,
            cause="Version illisible",
        ),
        # Les trois suivants ne sont pas des variantes du meme cas : chacun
        # couvre une facon differente de produire une version que les deux
        # plateformes n'interpreterai pas pareil.
        cas(
            "tag non numerique : refus franc",
            {"GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": "release-2.0", "GITHUB_RUN_NUMBER": "1"},
            {},
            doit_echouer=True,
            cause="Version refusee",
        ),
        cas(
            "version avec suffixe : refus franc",
            {
                "GITHUB_REF_TYPE": "branch",
                "GITHUB_REF_NAME": "main",
                "GITHUB_RUN_NUMBER": "1",
                "BUILD_NAME_IMPOSE": "1.2.3-beta",
            },
            {},
            doit_echouer=True,
            cause="Version refusee",
        ),
        cas(
            "version avec traversee de chemin : refus franc",
            {
                "GITHUB_REF_TYPE": "branch",
                "GITHUB_REF_NAME": "main",
                "GITHUB_RUN_NUMBER": "1",
                "BUILD_NAME_IMPOSE": "../../x",
            },
            {},
            doit_echouer=True,
            cause="Version refusee",
        ),
        cas(
            "numero de compilation non entier : refus franc",
            {"GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": "v0.1.1", "GITHUB_RUN_NUMBER": "abc"},
            {},
            doit_echouer=True,
            cause="Numero de compilation refuse",
        ),
    ]

    reussis = sum(resultats)
    print(f"\n{reussis}/{len(resultats)} cas conformes.")
    return 0 if reussis == len(resultats) else 1


if __name__ == "__main__":
    sys.exit(main())
