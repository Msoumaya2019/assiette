#!/usr/bin/env python3
"""Falsifie les pierres tombales du depot local.

Ce que ce banc vise
-------------------
Une suppression logique ecrit **deux** dates : `deleted_at`, et `updated_at`.
Les deux sont necessaires, et l'oubli de la seconde est un defaut qui a vecu :
`arbitrer` (`models/arbitrage.dart`) compare `updatedAt` **d'abord**, et ne
regarde la suppression qu'a **date egale**. Une suppression qui laisse
`updated_at` a sa valeur d'avant perd donc contre n'importe quelle version
distante plus recente — la ligne **ressuscite** sur l'appareil qui vient de la
supprimer, ce qui est exactement le defaut que la pierre tombale existe pour
eviter. Cinq des six tables faisaient cela ; seule `deleteFavorite`, la plus
recente, ecrivait les deux dates.

Ce banc tient deux fautes, et elles sont de nature differente :

1. **La fabrique oublie `updated_at`.** Une seule ligne, et les six tables
   deviennent fausses d'un coup.

2. **Une suppression contourne la fabrique.** C'est ainsi que le defaut est
   apparu : six copies d'une meme regle, dont cinq avaient oublie la moitie.
   La fabrique unique existe pour que cela ne puisse plus arriver — ce cas
   verifie qu'on ne peut pas non plus la contourner.

Le dernier cas est le temoin negatif : une reformulation de commentaire ne doit
rien faire tomber.

Usage : python3 tools/bancs/falsifier_pierres_tombales_dart.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, MesureImpossible  # noqa: E402
from banc_flutter import BancFlutter  # noqa: E402
from environnement_flutter import executable_flutter  # noqa: E402

DEPOT = "app/lib/data/local/app_database.dart"
TESTS = "test/data/app_database_test.dart"

# A mettre a jour en meme temps que le fichier de tests, jamais pour faire
# passer le banc.
TESTS_ATTENDUS = 35

# --- ancres : au niveau octet, telles que `dart format` les ecrit ---

DEUX_DATES = b"    return {'deleted_at': maintenant, 'updated_at': maintenant};\n"
DATE_SEULE = b"    return {'deleted_at': maintenant};\n"

SUPPRESSION_PAR_LA_FABRIQUE = b"      'meals',\n      _pierreTombale(),\n"
SUPPRESSION_QUI_CONTOURNE = (
    b"      'meals',\n      {'deleted_at': _horloge.maintenantMs()},\n"
)

COMMENTAIRE = b"  /// Les deux dates d'une pierre tombale, **egales**.\n"
COMMENTAIRE_REFORMULE = (
    b"  /// Les deux dates d'une pierre tombale, et elles sont egales.\n"
)

# --- noms des tests qui doivent tomber -----------------------------------------

T_DEUX_DATES = "les deux dates sont egales, sur les six tables"
T_RESSUSCITE = "la suppression bat une modification anterieure"


def principal() -> int:
    flutter = executable_flutter()
    if flutter is None:
        print(
            "flutter introuvable : ni dans le SDK local, ni dans le PATH.",
            file=sys.stderr,
        )
        return 2

    banc = BancFlutter(RACINE / DEPOT, flutter, TESTS, TESTS_ATTENDUS)

    try:
        initial = banc.executer()
    except MesureImpossible as erreur:
        print(f"la suite de tests ne tourne pas : {erreur}", file=sys.stderr)
        return 2

    print(
        f"etat initial : code {initial.code}, {initial.executes} test(s) execute(s), "
        f"{len(initial.echecs)} en echec"
    )
    if initial.code != 0:
        print(initial.sortie[-3000:], file=sys.stderr)
        print(initial.erreur[-2000:], file=sys.stderr)
        print("les tests echouent deja avant toute mutation.", file=sys.stderr)
        return 2

    def fabrique_sans_date_de_modification() -> None:
        banc.suivre(DEPOT).muter(DEUX_DATES, DATE_SEULE)

    def suppression_qui_contourne() -> None:
        banc.suivre(DEPOT).muter(
            SUPPRESSION_PAR_LA_FABRIQUE, SUPPRESSION_QUI_CONTOURNE
        )

    def commentaire_reformule() -> None:
        banc.suivre(DEPOT).muter(COMMENTAIRE, COMMENTAIRE_REFORMULE)

    banc.cas(
        "la fabrique oublie la date de modification",
        T_DEUX_DATES,
        fabrique_sans_date_de_modification,
    )
    banc.cas(
        "une suppression contourne la fabrique",
        T_RESSUSCITE,
        suppression_qui_contourne,
    )
    banc.cas("commentaire reformule", T_RESSUSCITE, commentaire_reformule, attendu=False)

    code = banc.tableau()

    try:
        final = banc.executer()
    except MesureImpossible as erreur:
        print(f"\nla suite de tests ne tourne plus : {erreur}", file=sys.stderr)
        return 1

    print(
        f"\netat final : code {final.code}, {final.executes} test(s) execute(s), "
        f"{len(final.echecs)} en echec"
    )
    if final.code != 0:
        print(final.sortie[-2000:], file=sys.stderr)
        return 1

    if code != 0:
        return code

    print(
        "vert — les pierres tombales tombent sur leurs deux fautes, et pas sur "
        "une reformulation."
    )
    return 0


if __name__ == "__main__":
    sys.exit(principal())
