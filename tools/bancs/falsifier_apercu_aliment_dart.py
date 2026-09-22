#!/usr/bin/env python3
"""Falsifie l'apercu de portion, et le chiffre comparable qu'il rend.

Ce que ce banc vise
-------------------
Un aliment est chiffre sur **deux** bases selon ce qu'on sait de lui : la
portion quand elle est connue (« pour 1 pot (125 g) »), les 100 g sinon. C'est
ce que l'utilisateur a demande, et la portion reste donc mise en avant.

Mais une **liste** sert a comparer, et deux produits chiffres sur deux bases ne
se comparent pas sans un calcul mental. `apercuDePortion` rend donc, avec les
valeurs et leur etiquette, le chiffre comparable — les memes valeurs ramenees a
100 g. Il vaut `null` quand l'apercu **est** deja la valeur des 100 g : l'ecrire
deux fois serait du bruit.

Ce banc tient trois fautes :

1. **Le comparable porte les valeurs de la portion.** C'est le piege evident, et
   il est silencieux : la ligne comparable annoncerait « 15 g pour 100 g » la ou
   l'aliment en contient 12, en se donnant l'air d'une mesure.

2. **Le comparable est rendu meme sans portion.** L'ecran afficherait alors deux
   fois le meme chiffre, sous deux formes — « 12 g pour 100 g » puis « soit 12 g
   de glucides pour 100 g » — ce qui laisse croire a une seconde mesure.

3. **L'unite de reference change.** Les 100 g sont l'unite de toutes les tables
   de composition. Un aliment solide chiffre « pour 100 ml » est faux, et le
   chiffre qui l'accompagne devient ininterpretable.

Le dernier cas est le temoin negatif : une reformulation de commentaire ne doit
rien faire tomber.

Usage : python3 tools/bancs/falsifier_apercu_aliment_dart.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, MesureImpossible  # noqa: E402
from banc_flutter import BancFlutter  # noqa: E402
from environnement_flutter import executable_flutter  # noqa: E402

DEPOT = "app/lib/models/apercu_aliment.dart"
TESTS = "test/models/apercu_aliment_test.dart"

# A mettre a jour en meme temps que le fichier de tests, jamais pour faire
# passer le banc.
TESTS_ATTENDUS = 8

# --- ancres : au niveau octet, telles que `dart format` les ecrit ---

REFERENCE = b"const String reference100g = 'pour 100 g';\n"
REFERENCE_VOLUME = b"const String reference100g = 'pour 100 ml';\n"

SANS_PORTION = (
    b"    return (valeurs: food.per100g, reference: reference100g, comparable: null);\n"
)
SANS_PORTION_MAIS_COMPARABLE = (
    b"    return (valeurs: food.per100g, reference: reference100g, "
    b"comparable: food.per100g);\n"
)

COMPARABLE_DES_100_G = b"    comparable: food.per100g,\n"
COMPARABLE_DE_LA_PORTION = b"    comparable: food.per100g.forGrams(portion.grams),\n"

COMMENTAIRE = b"/// L'unite de reference de toutes les tables, nommee une seule fois.\n"
COMMENTAIRE_REFORMULE = (
    b"/// L'unite de reference de toutes les tables, nommee en un seul endroit.\n"
)

# --- noms des tests qui doivent tomber -----------------------------------------

T_SANS_PORTION = "sans portion, les valeurs restent celles des 100 g"
T_COMPARABLE = "une liste recoit de quoi comparer deux produits"
T_RIEN_A_COMPARER = "sans portion, il n'y a rien a comparer"


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

    def comparable_de_la_portion() -> None:
        banc.suivre(DEPOT).muter(COMPARABLE_DES_100_G, COMPARABLE_DE_LA_PORTION)

    def comparable_sans_portion() -> None:
        banc.suivre(DEPOT).muter(SANS_PORTION, SANS_PORTION_MAIS_COMPARABLE)

    def reference_en_volume() -> None:
        banc.suivre(DEPOT).muter(REFERENCE, REFERENCE_VOLUME)

    def commentaire_reformule() -> None:
        banc.suivre(DEPOT).muter(COMMENTAIRE, COMMENTAIRE_REFORMULE)

    banc.cas(
        "le comparable porte les valeurs de la portion",
        T_COMPARABLE,
        comparable_de_la_portion,
    )
    banc.cas(
        "le comparable est rendu meme sans portion",
        T_RIEN_A_COMPARER,
        comparable_sans_portion,
    )
    banc.cas(
        "l'unite de reference devient un volume",
        T_SANS_PORTION,
        reference_en_volume,
    )
    banc.cas("commentaire reformule", T_COMPARABLE, commentaire_reformule, attendu=False)

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
        "vert — l'apercu tombe sur ses trois fautes, et pas sur une reformulation."
    )
    return 0


if __name__ == "__main__":
    sys.exit(principal())
