#!/usr/bin/env python3
"""Falsifie la regle d'arbitrage entre deux versions d'une meme ligne.

La regle d'arbitrage a une propriete centrale : **les deux appareils doivent
rendre le meme verdict**. Deux appareils qui se croient chacun vainqueur ne
convergent jamais — ils s'echangent leurs versions a chaque synchronisation.

Cette propriete n'est pas visible en lisant la regle, et une regle fausse peut
passer tous les autres cas. Le premier cas de ce banc est donc celui qui
remplace le departage par « en cas d'egalite, je garde ma version » : c'est
l'ecriture la plus naturelle, celle qu'on ecrirait sans y penser, et elle est
fausse. Si ce banc ne la detectait pas, le reste ne prouverait rien.

Usage : python3 tools/bancs/falsifier_arbitrage_dart.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, MesureImpossible  # noqa: E402
from banc_flutter import BancFlutter  # noqa: E402
from environnement_flutter import executable_flutter  # noqa: E402

REGLES = "app/lib/models/arbitrage.dart"
TESTS = "test/models/arbitrage_test.dart"

# A mettre a jour en meme temps que le fichier de tests, jamais pour faire
# passer le banc.
TESTS_ATTENDUS = 14

# --- ancres : au niveau octet, telles que `dart format` les ecrit ---

DEPARTAGE_PAR_EMPREINTE = (
    b"  final ordre = distante.empreinte.compareTo(locale.empreinte);\n"
    b"  if (ordre > 0) return VerdictArbitrage.prendreDistante;\n"
    b"  if (ordre < 0) return VerdictArbitrage.garderLocale;\n"
)
DEPARTAGE_PAR_LE_COTE_LOCAL = b"  return VerdictArbitrage.garderLocale;\n"

SUPPRESSION_GAGNE = (
    b"  if (distante.estSupprimee != locale.estSupprimee) {\n"
    b"    return distante.estSupprimee\n"
    b"        ? VerdictArbitrage.prendreDistante\n"
    b"        : VerdictArbitrage.garderLocale;\n"
    b"  }\n"
)

COMPARAISON_DATES = (
    b"  if (comparaison > 0) return VerdictArbitrage.prendreDistante;\n"
    b"  if (comparaison < 0) return VerdictArbitrage.garderLocale;\n"
)
COMPARAISON_INVERSEE = (
    b"  if (comparaison < 0) return VerdictArbitrage.prendreDistante;\n"
    b"  if (comparaison > 0) return VerdictArbitrage.garderLocale;\n"
)

DEBUT_COMPARAISON = (
    b"int _comparerDates(int gauche, int droite) {\n"
    b"  if (gauche > droite + _aucuneTolerance) return 1;\n"
)
DATE_INCONNUE_PLUS_RECENTE = (
    b"int _comparerDates(int gauche, int droite) {\n"
    b"  if (gauche == 0 && droite != 0) return 1;\n"
    b"  if (droite == 0 && gauche != 0) return -1;\n"
    b"  if (gauche > droite + _aucuneTolerance) return 1;\n"
)

COMMENTAIRE = (
    b"  // 1. La plus recente gagne. Les dates inconnues (zero) perdent ici, sans cas\n"
)
COMMENTAIRE_REFORMULE = (
    b"  // 1. La plus recente gagne (les dates inconnues perdent ici, sans cas\n"
)

# --- noms des tests qui doivent tomber -----------------------------------------

T_SYMETRIE = "le verdict est le meme des deux cotes, pour chaque paire"
T_SUPPRESSION = "la suppression distante l'emporte sur une vivante"
T_RECENTE = "la distante plus recente l'emporte"
T_DATE_INCONNUE = "perd contre une date connue"


def principal() -> int:
    flutter = executable_flutter()
    if flutter is None:
        print("flutter introuvable : ni dans le SDK local, ni dans le PATH.", file=sys.stderr)
        return 2

    banc = BancFlutter(RACINE / REGLES, flutter, TESTS, TESTS_ATTENDUS)

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

    def egalite_par_le_cote_local() -> None:
        # L'ecriture la plus naturelle, et la plus fausse : a date egale, chacun
        # garde sa version. Les deux appareils divergent pour toujours.
        banc.suivre(REGLES).muter(DEPARTAGE_PAR_EMPREINTE, DEPARTAGE_PAR_LE_COTE_LOCAL)

    def suppression_perdante() -> None:
        # La regle 2 disparait : a date egale, une suppression ne l'emporte plus.
        # Une ligne supprimee peut alors revenir, ce que la pierre tombale
        # existe precisement pour empecher.
        banc.suivre(REGLES).muter(SUPPRESSION_GAGNE, b"")

    def dates_inversees() -> None:
        # La version la plus ancienne gagne : chaque synchronisation ramene le
        # passe, et l'application ne garde jamais une modification.
        banc.suivre(REGLES).muter(COMPARAISON_DATES, COMPARAISON_INVERSEE)

    def date_inconnue_tenue_pour_recente() -> None:
        # Une date inconnue (zero) est prise pour la plus recente. Or c'est ce
        # que porte une ligne relue d'une sauvegarde ancienne : elle ecraserait
        # toutes les modifications reelles.
        banc.suivre(REGLES).muter(DEBUT_COMPARAISON, DATE_INCONNUE_PLUS_RECENTE)

    def commentaire_reformule() -> None:
        # Temoin negatif : une reformulation legitime ne doit rien faire tomber.
        banc.suivre(REGLES).muter(COMMENTAIRE, COMMENTAIRE_REFORMULE)

    banc.cas("egalite tranchee par le cote local", T_SYMETRIE, egalite_par_le_cote_local)
    banc.cas("suppression perdante a date egale", T_SUPPRESSION, suppression_perdante)
    banc.cas("comparaison des dates inversee", T_RECENTE, dates_inversees)
    banc.cas(
        "date inconnue tenue pour la plus recente",
        T_DATE_INCONNUE,
        date_inconnue_tenue_pour_recente,
    )
    banc.cas("commentaire reformule", T_SYMETRIE, commentaire_reformule, attendu=False)

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

    print("vert — la regle tombe sur chacune de ses quatre fautes, et pas sur une reformulation.")
    return 0


if __name__ == "__main__":
    sys.exit(principal())
