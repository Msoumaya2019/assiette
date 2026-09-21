#!/usr/bin/env python3
"""Falsifie la lecture locale des lignes, pour la synchronisation.

Une empreinte est aveugle a ce qu'on ne lui donne pas. Si le contenu d'un repas
omettait `notes`, alors deux repas differant **par leurs seules notes** seraient
declares identiques a date egale — et la modification cesserait de circuler,
sans erreur et sans trace.

Le fichier ne recopie donc pas la liste des colonnes : il les lit dans le schema
(`PRAGMA table_info`). Le premier cas de ce banc verifie que ce choix porte
quelque chose — il **oublie une colonne** et exige que le controle tombe. C'est
le cas qui compte : sans lui, on ne saurait pas si le controle par colonne
regarde vraiment chaque colonne.

Deuxieme cas, de la meme famille : une table ajoutee plus tard avec une date et
une pierre tombale, mais non declaree. Le controle qui ferme l'ensemble doit
tomber — sinon une donnee entiere ne serait jamais synchronisee.

Usage : python3 tools/bancs/falsifier_synchronisation_locale_dart.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, MesureImpossible  # noqa: E402
from banc_flutter import BancFlutter  # noqa: E402
from environnement_flutter import executable_flutter  # noqa: E402

LECTURE = "app/lib/data/local/synchronisation_locale.dart"
TESTS = "test/data/synchronisation_locale_test.dart"

# A mettre a jour en meme temps que le fichier de tests, jamais pour faire
# passer le banc.
TESTS_ATTENDUS = 21

# --- ancres : au niveau octet, telles que `dart format` les ecrit ---

EXCLUSIONS = (
    b"    if (colonne == colonneCle) continue;\n"
    b"    if (colonnesDeService.contains(colonne)) continue;\n"
    b"    contenu[colonne] = ligne[colonne];\n"
)
COLONNE_OUBLIEE = (
    b"    if (colonne == colonneCle) continue;\n"
    b"    if (colonnesDeService.contains(colonne)) continue;\n"
    b"    if (colonne == 'notes') continue;\n"
    b"    contenu[colonne] = ligne[colonne];\n"
)

SERVICE_EXCLU = b"    if (colonnesDeService.contains(colonne)) continue;\n"

LECTURE_DES_ENFANTS = (
    b"    if (enfant != null) {\n"
    b"      contenu[cleDesEnfants] = await _lireEnfants(\n"
    b"        db,\n"
    b"        enfant,\n"
    b"        ligne[table.colonneCle],\n"
    b"      );\n"
    b"    }\n"
)

LIEN_EXCLU = (
    b"    for (final ligne in lignes) contenuDe(colonnes, ligne, enfant.colonneLien),\n"
)
LIEN_DANS_LE_CONTENU = b"    for (final ligne in lignes) contenuDe(colonnes, ligne, ''),\n"

TABLE_DECLAREE = b"  TableSynchronisable(nom: 'mesures', colonneCle: 'id'),\n"

DATE_ABSENTE = b"        updatedAt: (ligne['updated_at'] as int?) ?? 0,\n"
DATE_ABSENTE_TENUE_POUR_RECENTE = (
    b"        updatedAt: (ligne['updated_at'] as int?) ?? 4102444800000,\n"
)

COMMENTAIRE = (
    b"/// Le contenu d'une ligne : tout sauf la cle et les colonnes de service.\n"
)
COMMENTAIRE_REFORMULE = (
    b"/// Le contenu d'une ligne, prive de sa cle et des colonnes de service.\n"
)

# --- noms des tests qui doivent tomber -----------------------------------------

T_COLONNE = "changer une seule colonne change l'empreinte, pour chaque colonne"
T_SERVICE = "les colonnes de service ne sont pas dans le contenu"
T_ENFANTS = "le contenu d'un repas contient ses aliments"
T_LIEN = "la colonne de lien n'est pas repetee dans l'aliment"
T_FERME = "aucune table a pierre tombale n'est oubliee"
T_DATE = "une date absente vaut zero, jamais 1970"


def principal() -> int:
    flutter = executable_flutter()
    if flutter is None:
        print(
            "flutter introuvable : ni dans le SDK local, ni dans le PATH.",
            file=sys.stderr,
        )
        return 2

    banc = BancFlutter(RACINE / LECTURE, flutter, TESTS, TESTS_ATTENDUS)

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

    def colonne_oubliee() -> None:
        # Le defaut central : une colonne n'entre pas dans le contenu. Une
        # modification de cette colonne seule devient invisible a la
        # synchronisation, sans erreur.
        banc.suivre(LECTURE).muter(EXCLUSIONS, COLONNE_OUBLIEE)

    def service_dans_le_contenu() -> None:
        # `updated_at` et `deleted_at` reviennent dans le contenu. Elles y sont
        # redondantes : la date est deja comparee, la suppression deja tranchee.
        banc.suivre(LECTURE).muter(SERVICE_EXCLU, b"")

    def enfants_non_lus() -> None:
        # Les aliments d'un repas ne sont plus lus : le contenu d'un repas
        # devient aveugle a tout changement d'aliment a date egale.
        banc.suivre(LECTURE).muter(LECTURE_DES_ENFANTS, b"")

    def lien_dans_le_contenu() -> None:
        # La colonne de lien reste dans le contenu de l'aliment. Elle est
        # derivee du parent : la garder ferait dependre l'empreinte d'une
        # valeur qui n'appartient pas a la ligne.
        banc.suivre(LECTURE).muter(LIEN_EXCLU, LIEN_DANS_LE_CONTENU)

    def table_non_declaree() -> None:
        # Une table a pierre tombale disparait de la liste. Le controle qui
        # ferme l'ensemble doit le voir — sinon une donnee entiere ne serait
        # jamais synchronisee.
        banc.suivre(LECTURE).muter(TABLE_DECLAREE, b"")

    def date_absente_tenue_pour_recente() -> None:
        # Une date absente est lue comme une date tres lointaine. Or c'est ce
        # que porte une ligne relue d'une sauvegarde ancienne : elle ecraserait
        # toutes les modifications reelles.
        banc.suivre(LECTURE).muter(DATE_ABSENTE, DATE_ABSENTE_TENUE_POUR_RECENTE)

    def commentaire_reformule() -> None:
        # Temoin negatif : une reformulation legitime ne doit rien faire tomber.
        banc.suivre(LECTURE).muter(COMMENTAIRE, COMMENTAIRE_REFORMULE)

    banc.cas("colonne oubliee dans le contenu", T_COLONNE, colonne_oubliee)
    banc.cas("colonnes de service dans le contenu", T_SERVICE, service_dans_le_contenu)
    banc.cas("aliments non lus", T_ENFANTS, enfants_non_lus)
    banc.cas("colonne de lien dans le contenu", T_LIEN, lien_dans_le_contenu)
    banc.cas("table a pierre tombale non declaree", T_FERME, table_non_declaree)
    banc.cas(
        "date absente tenue pour la plus recente",
        T_DATE,
        date_absente_tenue_pour_recente,
    )
    banc.cas("commentaire reformule", T_COLONNE, commentaire_reformule, attendu=False)

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
        "vert — la lecture tombe sur chacune de ses six fautes, et pas sur une "
        "reformulation."
    )
    return 0


if __name__ == "__main__":
    sys.exit(principal())
