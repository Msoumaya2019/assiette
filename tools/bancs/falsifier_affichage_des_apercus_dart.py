#!/usr/bin/env python3
"""Falsifie le controle qui exige que les ecrans passent par le point unique.

Ce que ce banc vise
-------------------
`app/test/ui/affichage_des_apercus_test.dart` derive la liste des ecrans qui
recoivent un `Apercu` — ceux qui appellent `apercuDePortion` — et exige que
chacun affiche par le point unique (`ApercuValeurs` ou `ligneComparable`).

Ce controle est ne d'une mesure : un **troisieme** ecran, celui du code-barres,
composait son texte seul et n'affichait donc pas le chiffre comparable. Aucun
banc ne pouvait le voir, parce que les bancs mesurent la fonction et le bloc,
jamais leurs appelants. C'est exactement ce que ce controle ajoute, et c'est
donc lui qu'il faut eprouver.

Deux fautes, et la seconde est celle qui compte :

1. **L'ecran recompose son texte.** On retire l'appel de `ligneComparable` de
   `barcode_screen.dart` : la faute d'origine, telle qu'elle a ete trouvee.

2. **Un ecran neuf recompose son texte.** Un fichier factice apparait sous
   `lib/ui/`, appelle `apercuDePortion` sans passer par le point unique, et le
   controle doit le declarer fautif **sans qu'on ait touche a sa liste**. C'est
   ce cas qui etablit que le controle **derive** les appelants au lieu d'en
   tenir une liste recopiee — une liste aurait rendu le meme service le jour de
   l'audit, et serait devenue fausse au premier ecran ajoute.

Le dernier cas est le temoin negatif : une reformulation de commentaire ne doit
rien faire tomber.

Usage : python3 tools/bancs/falsifier_affichage_des_apercus_dart.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, MesureImpossible  # noqa: E402
from banc_flutter import BancFlutter  # noqa: E402
from environnement_flutter import executable_flutter  # noqa: E402

DEPOT = "app/lib/ui/screens/barcode_screen.dart"
TESTS = "test/ui/affichage_des_apercus_test.dart"

# A mettre a jour en meme temps que le fichier de tests, jamais pour faire
# passer le banc.
TESTS_ATTENDUS = 1

# --- ancres : au niveau octet, telles que `dart format` les ecrit ---

AVEC_LA_LIGNE = (
    b"                    'g de glucides',\n"
    b"                    apercu.reference,\n"
    b"                    if (ligneComparable(apercu) case final ligne?) ligne,\n"
)
SANS_LA_LIGNE = (
    b"                    'g de glucides',\n"
    b"                    apercu.reference,\n"
)

COMMENTAIRE = b"                  // sous le chiffre des 100 g.\n"
COMMENTAIRE_REFORMULE = b"                  // sous le chiffre des cent grammes.\n"

# --- ecran factice, cree puis retire par le banc ------------------------------
#
# Il n'est importe par personne, donc jamais compile : ce que le controle lit,
# c'est du texte. Le nom commence par deux soulignes pour qu'aucun outil ne le
# prenne pour un fichier du depot.

ECRAN_FACTICE = "app/lib/ui/screens/__ecran_factice_du_banc.dart"
CONTENU_FACTICE = (
    b"// Fichier factice, cree puis retire par le banc de falsification :\n"
    b"// un ecran qui recoit un apercu et recompose son texte lui-meme.\n"
    b"final apercu = apercuDePortion(food, portion);\n"
)

# --- nom du test qui doit tomber ----------------------------------------------

T_POINT_UNIQUE = "passe par le point unique"


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
        print(f"le controle ne tourne pas : {erreur}", file=sys.stderr)
        return 2

    print(
        f"etat initial : code {initial.code}, {initial.executes} test(s) execute(s), "
        f"{len(initial.echecs)} en echec"
    )
    if initial.code != 0:
        print(initial.sortie[-3000:], file=sys.stderr)
        print(initial.erreur[-2000:], file=sys.stderr)
        print("le controle echoue deja avant toute mutation.", file=sys.stderr)
        return 2

    def ecran_qui_recompose() -> None:
        banc.suivre(DEPOT).muter(AVEC_LA_LIGNE, SANS_LA_LIGNE)

    def ecran_neuf_qui_recompose() -> None:
        banc.creer(ECRAN_FACTICE, CONTENU_FACTICE)

    def commentaire_reformule() -> None:
        banc.suivre(DEPOT).muter(COMMENTAIRE, COMMENTAIRE_REFORMULE)

    banc.cas(
        "l'ecran du code-barres recompose son texte",
        T_POINT_UNIQUE,
        ecran_qui_recompose,
    )
    banc.cas(
        "un ecran neuf recompose son texte, sans toucher a aucune liste",
        T_POINT_UNIQUE,
        ecran_neuf_qui_recompose,
    )
    banc.cas("commentaire reformule", T_POINT_UNIQUE, commentaire_reformule, attendu=False)

    code = banc.tableau()

    try:
        final = banc.executer()
    except MesureImpossible as erreur:
        print(f"\nle controle ne tourne plus : {erreur}", file=sys.stderr)
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
        "vert — le controle tombe sur l'ecran qui recompose, sur un ecran neuf "
        "qu'il n'a jamais vu, et pas sur une reformulation."
    )
    return 0


if __name__ == "__main__":
    sys.exit(principal())
