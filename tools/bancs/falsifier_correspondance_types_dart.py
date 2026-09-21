#!/usr/bin/env python3
"""Falsifie la confrontation des types declares aux migrations reelles.

Pourquoi ce banc existe
-----------------------
`tools/check_migration_serveur.py` tient l'accord des **noms**. Il ne dit rien
des **types**, et c'est la que se cache une boucle silencieuse : le serveur
porte `eaten_at` en `timestamptz` et `is_estimate` en `boolean`, le local les
porte en entier. Sans conversion, les deux cotes ne decrivent jamais la meme
chose — l'arbitrage tranche toujours dans le meme sens, chaque passage reecrit
la meme ligne, et rien ne le signale.

`app/test/data/correspondance_types_test.dart` confronte donc les deux
declarations aux migrations, dans les deux sens. Ce banc verifie qu'il tombe
vraiment.

Le cas qui compte le plus
-------------------------
Le troisieme cas mute la **migration**, pas la declaration. Sans lui, on ne
saurait pas si le test lit reellement les fichiers `.sql` : un test qui compare
une declaration a elle-meme tomberait sur les deux premiers cas et passerait
partout ailleurs, en ne mesurant rien.

Le quatrieme cas mutile la lecture elle-meme — six `create table if not exists`
redeviennent `create table`. Le lecteur ne trouve plus rien, et le garde-fou
« les migrations ont bien ete lues » doit le dire. Sans ce cas, un lecteur
aveugle rendrait tous les autres tests verts.

Usage : python3 tools/bancs/falsifier_correspondance_types_dart.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, MesureImpossible  # noqa: E402
from banc_flutter import BancFlutter  # noqa: E402
from environnement_flutter import executable_flutter  # noqa: E402

DECLARATION = "app/lib/data/distant/correspondance_distant.dart"
MIGRATION = "backend/supabase/migrations/0001_init.sql"
TESTS = "test/data/correspondance_types_test.dart"

# A mettre a jour en meme temps que le fichier de tests, jamais pour faire
# passer le banc.
TESTS_ATTENDUS = 6

# --- ancres : au niveau octet, telles que `dart format` les ecrit ---
#
# Aucune ancre ne porte d'accent : un litteral d'octets ne peut pas en contenir.
# Les lignes visees en portent, elles : c'est pourquoi les ancres s'arretent
# avant, et pourquoi deux d'entre elles sont des prefixes de ligne.

DATES_MEALS = b"  'meals': {'eaten_at', 'created_at'},\n"
DATES_MEALS_SANS_EATEN_AT = b"  'meals': {'created_at'},\n"
DATES_MEALS_AVEC_NAME = b"  'meals': {'eaten_at', 'created_at', 'name'},\n"

BOOLEENS = b"  'meals': {'is_estimate'},\n  'meal_items': {'is_estimate'},\n"
BOOLEENS_SANS_MEAL_ITEMS = b"  'meals': {'is_estimate'},\n"
BOOLEENS_AVEC_NAME = b"  'meals': {'is_estimate', 'name'},\n"

TYPE_SERVEUR_EATEN_AT = b"eaten_at timestamptz"
TYPE_SERVEUR_EATEN_AT_TEXTE = b"eaten_at text"

TABLES_CREEES = b"create table if not exists"
TABLES_SANS_GARDE = b"create table"

COMMENTAIRE = b"-- Repas enregistres.\n"
COMMENTAIRE_REFORMULE = b"-- Les repas que l'utilisateur a enregistres.\n"

# --- noms des tests qui doivent tomber -----------------------------------------

T_DATE_OUBLIEE = "aucune colonne datee du serveur n'est oubliee"
T_BOOLEEN_OUBLIE = "aucune colonne booleenne du serveur n'est oubliee"
T_DATE_A_TORT = "chaque colonne declaree comme datee est un timestamptz"
T_BOOLEEN_A_TORT = "chaque colonne declaree comme booleenne est un boolean"
T_LECTEUR = "les migrations ont bien ete lues"


def principal() -> int:
    flutter = executable_flutter()
    if flutter is None:
        print(
            "flutter introuvable : ni dans le SDK local, ni dans le PATH.",
            file=sys.stderr,
        )
        return 2

    banc = BancFlutter(RACINE / DECLARATION, flutter, TESTS, TESTS_ATTENDUS)

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

    def date_oubliee() -> None:
        # `eaten_at` sort de la declaration. Le serveur continue de le porter en
        # `timestamptz` : rien ne le declare plus, et la synchronisation ne
        # convergerait jamais.
        banc.suivre(DECLARATION).muter(DATES_MEALS, DATES_MEALS_SANS_EATEN_AT)

    def booleen_oublie() -> None:
        # `meal_items.is_estimate` sort de la declaration. Il est arrive par un
        # `alter table` de `0002`, pas par un `create table` : le lecteur doit
        # le voir quand meme.
        banc.suivre(DECLARATION).muter(BOOLEENS, BOOLEENS_SANS_MEAL_ITEMS)

    def date_declaree_a_tort() -> None:
        # `meals.name` est un `text`, declare date. La declaration est fausse,
        # et c'est le sens « rien de declare qui ne soit du bon type ».
        banc.suivre(DECLARATION).muter(DATES_MEALS, DATES_MEALS_AVEC_NAME)

    def booleen_declare_a_tort() -> None:
        # Meme faute, sur l'autre declaration.
        banc.suivre(DECLARATION).muter(BOOLEENS, BOOLEENS_AVEC_NAME)

    def serveur_change_de_type() -> None:
        # La **migration** change, la declaration ne bouge pas. Ce cas est le
        # seul qui prouve que le test lit reellement les `.sql` : sans lui, un
        # test qui se comparerait a lui-meme serait vert partout.
        banc.suivre(MIGRATION).muter(TYPE_SERVEUR_EATEN_AT, TYPE_SERVEUR_EATEN_AT_TEXTE)

    def lecteur_aveugle() -> None:
        # La lecture ne trouve plus aucune table. Le garde-fou doit parler —
        # sans quoi un lecteur aveugle rendrait tous les autres tests verts.
        banc.suivre(MIGRATION).muter(TABLES_CREEES, TABLES_SANS_GARDE)

    def commentaire_reformule() -> None:
        # Temoin negatif : une reformulation legitime ne doit rien faire tomber.
        banc.suivre(MIGRATION).muter(COMMENTAIRE, COMMENTAIRE_REFORMULE)

    banc.cas("date oubliee dans la declaration", T_DATE_OUBLIEE, date_oubliee)
    banc.cas("booleen oublie dans la declaration", T_BOOLEEN_OUBLIE, booleen_oublie)
    banc.cas("colonne declaree datee a tort", T_DATE_A_TORT, date_declaree_a_tort)
    banc.cas("colonne declaree booleenne a tort", T_BOOLEEN_A_TORT, booleen_declare_a_tort)
    banc.cas("le serveur change de type", T_DATE_A_TORT, serveur_change_de_type)
    banc.cas("le lecteur des migrations devient aveugle", T_LECTEUR, lecteur_aveugle)
    banc.cas("commentaire reformule", T_DATE_A_TORT, commentaire_reformule, attendu=False)

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
        "vert — la declaration et les migrations se confrontent dans les deux "
        "sens, et une reformulation ne les fait pas tomber."
    )
    return 0


if __name__ == "__main__":
    sys.exit(principal())
