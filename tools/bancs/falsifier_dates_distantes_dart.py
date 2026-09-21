#!/usr/bin/env python3
"""Falsifie la conversion des horodatages entre le local et le serveur.

Pourquoi ce banc existe
-----------------------
Le local compte en millisecondes entieres, le serveur porte des `timestamptz`.
Deux erreurs de conversion ne se voient pas : elles font diverger les
empreintes, donc l'arbitrage tranche toujours dans le meme sens, chaque passage
reecrit la meme ligne, et rien ne le signale — ni erreur, ni trace, ni fin.

`app/test/data/dates_distantes_test.dart` ferme ces pieges. Ce banc verifie
qu'il tombe vraiment sur chacun.

Ce que ce banc refuse de faire
------------------------------
Aucun cas ne repose sur le fuseau de la machine. Une mutation qui remplacerait
`toUtc()` par `toLocal()` serait detectee a Paris et **invisible** sur un
executeur en UTC : le banc serait vert en local et rouge en integration
continue. Les mutations retenues sont donc deterministes partout — la marque
`Z`, l'absence tenue pour 1970, les millisecondes tenues pour des secondes.

Usage : python3 tools/bancs/falsifier_dates_distantes_dart.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, MesureImpossible  # noqa: E402
from banc_flutter import BancFlutter  # noqa: E402
from environnement_flutter import executable_flutter  # noqa: E402

CONVERSION = "app/lib/data/distant/dates_distantes.dart"
TESTS = "test/data/dates_distantes_test.dart"

# A mettre a jour en meme temps que le fichier de tests, jamais pour faire
# passer le banc.
TESTS_ATTENDUS = 8

# --- ancres : au niveau octet, telles que `dart format` les ecrit ---
#
# Aucune ancre ne porte d'accent : un litteral d'octets ne peut pas en contenir.
# La ligne du `throw` sur une date illisible en porte («  ») : l'ancre s'arrete
# donc au prefixe ASCII de la ligne.

UTC = b"        isUtc: true,\n"
PAS_UTC = b"        isUtc: false,\n"

ABSENCE = b"millisecondes == null\n    ? null\n"
ABSENCE_TENUE_POUR_1970 = b"millisecondes == null\n    ? isoDepuisMillisecondes(0)\n"

CHAINE_VIDE = b"    if (valeur.isEmpty) return null;\n"

GARDE_DU_PARSING = b"    if (date == null) {\n"
GARDE_QUI_REND_NULL = b"    if (date == null) {\n      return null;\n"

TYPE_INATTENDU = (
    b"  throw FormatException('horodatage de type inattendu : "
    b"${valeur.runtimeType}');\n"
)
TYPE_INATTENDU_TENU_POUR_ABSENCE = b"  return null;\n"

MILLISECONDES = b"    return date.toUtc().millisecondsSinceEpoch;\n"
MILLISECONDES_TENUES_POUR_SECONDES = (
    b"    return date.toUtc().millisecondsSinceEpoch * 1000;\n"
)

COMMENTAIRE = b"/// Accepte ce que PostgREST rend : une chaine ISO-8601, un entier, ou"
COMMENTAIRE_REFORMULE = (
    b"/// Prend ce que PostgREST rend : une chaine ISO-8601, un entier, ou"
)

# --- noms des tests qui doivent tomber -----------------------------------------

T_UTC = "une date devient un ISO-8601 en UTC, marque d'un Z"
T_ABSENTE = "une date absente reste absente"
T_VIDE = "une absence reste une absence"
T_CASSEE = "une date cassee leve, elle ne devient pas une absence"
T_ISO = "un ISO-8601 redevient un entier en millisecondes"


def principal() -> int:
    flutter = executable_flutter()
    if flutter is None:
        print(
            "flutter introuvable : ni dans le SDK local, ni dans le PATH.",
            file=sys.stderr,
        )
        return 2

    banc = BancFlutter(RACINE / CONVERSION, flutter, TESTS, TESTS_ATTENDUS)

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

    def pas_utc() -> None:
        # La marque `Z` disparait. Le serveur lirait alors la date dans le
        # fuseau de sa session : deux appareils dans deux fuseaux dateraient
        # differemment la meme modification.
        banc.suivre(CONVERSION).muter(UTC, PAS_UTC)

    def absence_tenue_pour_1970() -> None:
        # Une date absente devient 1970. Une pierre tombale nulle et une date
        # nulle sont deux choses differentes : les confondre ferait d'une ligne
        # jamais supprimee une ligne supprimee en 1970, donc gagnante partout.
        banc.suivre(CONVERSION).muter(ABSENCE, ABSENCE_TENUE_POUR_1970)

    def chaine_vide_non_reconnue() -> None:
        # PostgREST rend une chaine vide pour une colonne nulle. Sans cette
        # reconnaissance, elle passe pour une date cassee — et leve.
        banc.suivre(CONVERSION).muter(CHAINE_VIDE, b"")

    def date_cassee_rendue_nulle() -> None:
        # Une date illisible devient une absence, au lieu de lever. C'est le
        # pire des deux : « date inconnue » est une valeur, et une valeur fausse
        # qui se propage ne se signale jamais.
        banc.suivre(CONVERSION).muter(GARDE_DU_PARSING, GARDE_QUI_REND_NULL)

    def type_inattendu_rendu_nul() -> None:
        # Meme faute, par l'autre sortie : un type inattendu — un flottant, un
        # booleen — devient une absence au lieu de lever.
        banc.suivre(CONVERSION).muter(
            TYPE_INATTENDU, TYPE_INATTENDU_TENU_POUR_ABSENCE
        )

    def millisecondes_tenues_pour_des_secondes() -> None:
        # L'unite est confondue. Tout converge encore — les deux cotes sont
        # d'accord — mais les dates sont fausses d'un facteur mille, et rien ne
        # le signale.
        banc.suivre(CONVERSION).muter(
            MILLISECONDES, MILLISECONDES_TENUES_POUR_SECONDES
        )

    def commentaire_reformule() -> None:
        # Temoin negatif : une reformulation legitime ne doit rien faire tomber.
        banc.suivre(CONVERSION).muter(COMMENTAIRE, COMMENTAIRE_REFORMULE)

    banc.cas("la marque UTC disparait", T_UTC, pas_utc)
    banc.cas("une absence tenue pour 1970", T_ABSENTE, absence_tenue_pour_1970)
    banc.cas("la chaine vide non reconnue", T_VIDE, chaine_vide_non_reconnue)
    banc.cas("une date cassee rendue nulle", T_CASSEE, date_cassee_rendue_nulle)
    banc.cas("un type inattendu rendu nul", T_CASSEE, type_inattendu_rendu_nul)
    banc.cas(
        "les millisecondes tenues pour des secondes",
        T_ISO,
        millisecondes_tenues_pour_des_secondes,
    )
    banc.cas("commentaire reformule", T_CASSEE, commentaire_reformule, attendu=False)

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
        "vert — la conversion tombe sur chacune de ses six fautes, et pas sur "
        "une reformulation."
    )
    return 0


if __name__ == "__main__":
    sys.exit(principal())
