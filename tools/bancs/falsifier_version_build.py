#!/usr/bin/env python3
"""Falsifie `tools/version_build.sh` a travers `tools/verifier_version_build.py`.

Le raisonnement
---------------
`version_build.sh` decide de la version inscrite dans l'APK, l'AAB **et** l'IPA.
Il ne tourne nulle part en local : il ne s'execute que dans GitHub Actions, sur
un tag, c'est-a-dire sur une version que l'on ne peut pas rejouer sans creer un
nouveau tag. Un garde-fou casse y resterait donc invisible jusqu'a ce qu'un
binaire livre annonce une version fausse.

Ce banc retire un garde-fou a la fois et verifie que le controle tombe. Il
verifie aussi le **temoin negatif** : une mutation qui ne change pas le
comportement — ici, un commentaire reformule — ne doit rien declencher. Sans ce
temoin, rien ne prouverait que le controle distingue un defaut d'un texte
different, plutot qu'il ne reagit a n'importe quelle modification.

Usage : python3 tools/bancs/falsifier_version_build.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, Banc  # noqa: E402

SCRIPT = RACINE / "tools" / "verifier_version_build.py"
CIBLE = "tools/version_build.sh"

# Le controle ecrit `ECHEC` sur chaque cas non conforme, et sort non nul. Le
# marqueur porte donc sur le comportement observe, pas sur un message interne.
MARQUEUR = "ECHEC"


def principal() -> int:
    banc = Banc(SCRIPT)
    script = banc.suivre(CIBLE)

    # --- etat initial : le controle doit etre vert ------------------------
    initial = banc.etat_initial()
    if initial.code != 0:
        print("le controle n'est pas vert avant la campagne :", file=sys.stderr)
        print(initial.texte, file=sys.stderr)
        return 1
    print(f"etat initial : {initial.texte.strip().splitlines()[-1]}")

    # --- les mutations ----------------------------------------------------

    # 1. La priorite s'inverse : une version saisie a la main l'emporte sur le
    #    tag. C'est la faute la plus probable en retouchant le script, et elle
    #    rendrait un tag incapable de fixer la version publiee.
    def priorite_inversee() -> None:
        script.muter(
            b'if [ "${GITHUB_REF_TYPE:-}" = "tag" ]; then\n'
            b"  NAME=\"${GITHUB_REF_NAME#v}\"",
            b'if [ -n "${BUILD_NAME_IMPOSE:-}" ] && [ "${GITHUB_REF_TYPE:-}" = "tag" ]; then\n'
            b'  NAME="$BUILD_NAME_IMPOSE"',
        )

    banc.cas("priorite : le tag perd contre la saisie", MARQUEUR, priorite_inversee)

    # 2. Le prefixe `v` n'est plus retire : le tag `v0.1.1` donnerait `v0.1.1`,
    #    refuser par le format — mais le message accuserait le tag, pas le
    #    script. Le cas « tag v0.1.1 » doit tomber.
    def prefixe_non_retire() -> None:
        script.muter(b'NAME="${GITHUB_REF_NAME#v}"', b'NAME="${GITHUB_REF_NAME}"')

    banc.cas("prefixe v non retire", MARQUEUR, prefixe_non_retire)

    # 3. Le format de la version n'est plus verifie. C'est le garde-fou qui
    #    empeche iOS et Android de diverger en silence.
    def format_version_non_verifie() -> None:
        script.muter(
            b"if ! printf '%s' \"$NAME\" | grep -Eq '^[0-9]+(\\.[0-9]+)*$'; then\n"
            b"  echo \"Version refusee : '$NAME' (source : $ORIGINE).\" >&2\n"
            b"  echo \"Format attendu : des chiffres separes par des points, par exemple 0.1.2.\" >&2\n"
            b"  echo \"Motif : iOS et Android n'en garderaient pas la meme valeur, en silence.\" >&2\n"
            b"  exit 1\n"
            b"fi\n",
            b"",
        )

    banc.cas("format de version non verifie", MARQUEUR, format_version_non_verifie)

    # 4. Le format du numero de compilation n'est plus verifie.
    def format_numero_non_verifie() -> None:
        script.muter(
            b"if ! printf '%s' \"$NUM\" | grep -Eq '^[0-9]+$'; then\n"
            b"  echo \"Numero de compilation refuse : '$NUM' (source : $ORIGINE).\" >&2\n"
            b"  echo \"Format attendu : un entier, par exemple 42.\" >&2\n"
            b"  exit 1\n"
            b"fi\n",
            b"",
        )

    banc.cas("format du numero non verifie", MARQUEUR, format_numero_non_verifie)

    # 5. Un pubspec absent n'est plus refuse : le script continuerait avec une
    #    version vide, et `--build-name=` echouerait vingt minutes plus tard,
    #    sur un message qui ne nomme pas la cause.
    def pubspec_absent_tolere() -> None:
        script.muter(
            b'if [ ! -f "$PUBSPEC" ]; then\n'
            b'  echo "pubspec introuvable : $PUBSPEC" >&2\n'
            b"  exit 1\n"
            b"fi\n",
            b"",
        )

    banc.cas("pubspec absent tolere", MARQUEUR, pubspec_absent_tolere)

    # 6. Les sorties ne sont plus ecrites : le flux recevrait des sorties vides
    #    et passerait `--build-name=` a Flutter.
    def sorties_non_ecrites() -> None:
        script.muter(
            b'    echo "name=${NAME}"\n'
            b'    echo "number=${NUM}"\n'
            b'    echo "version=${NAME}+${NUM}"\n',
            b"",
        )

    banc.cas("sorties non ecrites", MARQUEUR, sorties_non_ecrites)

    # --- temoin negatif ---------------------------------------------------
    #
    # Un commentaire reformule ne change rien au comportement. Si le controle
    # tombait ici, c'est qu'il mesure le texte et non l'effet — et ses six
    # verdicts precedents ne voudraient rien dire.
    def commentaire_reformule() -> None:
        script.muter(
            b"# Usage : bash tools/version_build.sh [chemin/vers/pubspec.yaml]\n",
            b"# Usage : bash tools/version_build.sh <pubspec>\n",
        )

    banc.cas("temoin : commentaire reformule", MARQUEUR, commentaire_reformule, attendu=False)

    # --- etat final -------------------------------------------------------
    code = banc.tableau()

    final = banc.executer()
    print(f"\netat final : code {final.code}")
    if final.code != 0:
        print(final.texte, file=sys.stderr)
        return 1
    print("vert — le script est restaure a l'identique.")
    return code


if __name__ == "__main__":
    sys.exit(principal())
