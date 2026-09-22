#!/usr/bin/env python3
"""Falsifie la ligne comparable, telle qu'une liste de resultats l'ecrit.

Ce que ce banc vise
-------------------
`ligneComparable` (`ui/widgets/common.dart`) rend le chiffre des 100 g, pret a
ecrire, et le `null` quand il n'y a rien a comparer. Elle existe pour **une**
raison : le nombre et son etiquette ne doivent pas pouvoir diverger.

Le defaut qu'elle rend impossible a vecu dans un ecran : « 12 g de glucides pour
1 pot (125 g) », ou 12 est la valeur des 100 g — le pot en contient 15. Un nombre
avec la mauvaise unite se lit comme une information ; c'est pourquoi la ligne est
construite en un seul endroit, appele par les deux listes de l'application.

Ce banc tient trois fautes, et la premiere est ce defaut lui-meme :

1. **L'etiquette de la ligne devient celle de la portion.** Le chiffre des 100 g
   sous l'unite du pot : exactement le defaut d'origine, reproduit a l'identique.

2. **La ligne compte le mauvais nutriment.** Un nombre juste sous un nom qui ne
   lui correspond pas — ici des kilocalories annoncees en grammes de glucides.
   C'est la meme faute que la premiere, un cran plus bas.

3. **La ligne est rendue meme sans comparable.** L'apercu **est** alors la valeur
   des 100 g : la ligne la repete, et deux formes du meme chiffre se lisent comme
   deux mesures.

Le dernier cas est le temoin negatif : une reformulation de commentaire ne doit
rien faire tomber.

Usage : python3 tools/bancs/falsifier_ligne_comparable_dart.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, MesureImpossible  # noqa: E402
from banc_flutter import BancFlutter  # noqa: E402
from environnement_flutter import executable_flutter  # noqa: E402

DEPOT = "app/lib/ui/widgets/common.dart"
TESTS = "test/ui/ligne_comparable_test.dart"

# A mettre a jour en meme temps que le fichier de tests, jamais pour faire
# passer le banc.
TESTS_ATTENDUS = 4

# --- ancres : au niveau octet, telles que `dart format` les ecrit ---

GARDE_NUL = b"  if (comparable == null) {\n    return null;\n  }\n"
GARDE_QUI_REPETE = (
    b"  if (comparable == null) {\n"
    b"    return 'soit ${Format.number(apercu.valeurs.carbs)} g de glucides "
    b"$reference100g';\n"
    b"  }\n"
)

LIGNE = (
    b"  return 'soit ${Format.number(comparable.carbs)} g de glucides "
    b"$reference100g';\n"
)
LIGNE_AVEC_L_UNITE_DE_LA_PORTION = (
    b"  return 'soit ${Format.number(comparable.carbs)} g de glucides "
    b"${apercu.reference}';\n"
)
LIGNE_QUI_COMPTE_LES_KCAL = (
    b"  return 'soit ${Format.number(comparable.kcal)} g de glucides "
    b"$reference100g';\n"
)

COMMENTAIRE = (
    b"/// Un seul endroit, donc : les deux listes de l'application l'appellent, et\n"
)
COMMENTAIRE_REFORMULE = (
    b"/// Un seul endroit, donc : les deux listes de l'application l'appellent,\n"
)

# --- noms des tests qui doivent tomber -----------------------------------------

T_CHIFFRE = "la ligne porte le chiffre des 100 g, et le dit"
T_ETIQUETTE = "l'etiquette de la ligne n'est jamais celle de la portion"
T_SANS_PORTION = "sans portion, il n'y a pas de ligne"


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

    def etiquette_de_la_portion() -> None:
        banc.suivre(DEPOT).muter(LIGNE, LIGNE_AVEC_L_UNITE_DE_LA_PORTION)

    def mauvais_nutriment() -> None:
        banc.suivre(DEPOT).muter(LIGNE, LIGNE_QUI_COMPTE_LES_KCAL)

    def ligne_sans_comparable() -> None:
        banc.suivre(DEPOT).muter(GARDE_NUL, GARDE_QUI_REPETE)

    def commentaire_reformule() -> None:
        banc.suivre(DEPOT).muter(COMMENTAIRE, COMMENTAIRE_REFORMULE)

    banc.cas(
        "l'etiquette de la ligne est celle de la portion",
        T_ETIQUETTE,
        etiquette_de_la_portion,
    )
    banc.cas(
        "la ligne compte les kilocalories",
        T_CHIFFRE,
        mauvais_nutriment,
    )
    banc.cas(
        "la ligne est rendue meme sans comparable",
        T_SANS_PORTION,
        ligne_sans_comparable,
    )
    banc.cas("commentaire reformule", T_CHIFFRE, commentaire_reformule, attendu=False)

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

    print("vert — la ligne tombe sur ses trois fautes, et pas sur une reformulation.")
    return 0


if __name__ == "__main__":
    sys.exit(principal())
