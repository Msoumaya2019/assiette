#!/usr/bin/env python3
"""Falsifie la retenue des colonnes propres a l'appareil.

Pourquoi ce banc existe
-----------------------
`meals.photo_path` porte un chemin absolu dans le dossier de documents du
telephone. Il existe des deux cotes du schema, donc rien ne signale qu'il ne
faut pas le transporter — et le transporter ne produit **aucune erreur** : le
chemin arrive, il est valide, l'image manque. Pire, `ecrireLigne` ecrit par
remplacement, donc la photo de l'appareil qui recoit serait effacee.

La decision se prend a deux endroits, et il faut les deux :

  - `correspondance_distant.dart` **nomme** la colonne retenue ;
  - `synchronisation_locale.dart` n'emet pas la colonne, et la relit a
    l'ecriture pour la remettre.

Ce banc falsifie les deux, separement. Le cas qui compte le plus est celui de
l'ecriture : sans lui, la photo disparaitrait a chaque synchronisation, et
**aucun test de `synchronisation_locale_test.dart` ne tomberait** — ces tests-la
comparent des empreintes, pas des fichiers.

Ce que ce banc refuse de faire
------------------------------
Il ne falsifie pas l'exclusion cote lecture dans
`falsifier_synchronisation_locale_dart.py`. Ce banc-la vise
`test/data/synchronisation_locale_test.dart`, dont les deux listes ont ete
retirees de `photo_path` **par decision** : sa couverture de cette exclusion est
nulle, et une mutation qui la retirerait ne ferait tomber aucun de ses tests.
Une mutation qui ne peut pas etre detectee n'a rien a faire dans un banc.

Usage : python3 tools/bancs/falsifier_colonnes_locales_dart.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, MesureImpossible  # noqa: E402
from banc_flutter import BancFlutter  # noqa: E402
from environnement_flutter import executable_flutter  # noqa: E402

DECLARATION = "app/lib/data/distant/correspondance_distant.dart"
LECTURE = "app/lib/data/local/synchronisation_locale.dart"
TESTS = "test/data/colonnes_locales_test.dart"

# A mettre a jour en meme temps que le fichier de tests, jamais pour faire
# passer le banc.
TESTS_ATTENDUS = 7

# --- ancres : au niveau octet, telles que `dart format` les ecrit ---

DECLARATION_COMPLETE = (
    b"const Map<String, Set<String>> colonnesLocalesSeules = {\n"
    b"  'meals': {'photo_path'},\n"
    b"};\n"
)
# La meme declaration, vide. `dart format` ecrit cette forme sur une ligne.
DECLARATION_VIDE = b"const Map<String, Set<String>> colonnesLocalesSeules = {};\n"
# La meme declaration, mais la colonne nommee n'existe nulle part : l'exclusion
# ne designe plus rien.
DECLARATION_FAUSSE = (
    b"const Map<String, Set<String>> colonnesLocalesSeules = {\n"
    b"  'meals': {'photo_chemin'},\n"
    b"};\n"
)

COMMENTAIRE_DECLARATION = b"/// Nommees en vocabulaire **local**. "
COMMENTAIRE_REFORMULE = b"/// Exprimees en vocabulaire **local**. "

LOCALES_SEULES_EXCLUES = b"    if (localesSeules.contains(colonne)) continue;\n"

# La lecture passe bien le nom de la table a `contenuDe` : c'est lui qui designe
# les colonnes retenues. Le remplacer par une chaine vide rend l'exclusion
# inoperante, et c'est le seul moyen de savoir que ce parametre sert.
TABLE_TRANSMISE = b"      table.colonneCle,\n      table: table.nom,\n"
TABLE_PERDUE = b"      table.colonneCle,\n      table: '',\n"

# Le bloc qui relit la valeur locale avant de la remettre.
PRESERVATION = (
    b"  final localesSeules = colonnesLocalesSeulesDe(table.nom);\n"
    b"  if (localesSeules.isNotEmpty) {\n"
    b"    final existante = await db.query(\n"
    b"      table.nom,\n"
    b"      columns: localesSeules.toList()..sort(),\n"
    b"      where: '${table.colonneCle} = ?',\n"
    b"      whereArgs: [ligne.cle],\n"
    b"      limit: 1,\n"
    b"    );\n"
    b"    if (existante.isNotEmpty) charge.addAll(existante.first);\n"
    b"  }\n"
    b"\n"
)

# La relecture vise **la** ligne que l'on ecrit. Sans le `where`, elle prend la
# premiere venue : un repas inconnu localement recevrait la photo d'un autre.
ECRITURE_CIBLEE = (
    b"      where: '${table.colonneCle} = ?',\n      whereArgs: [ligne.cle],\n"
)

# --- noms des tests qui doivent tomber -----------------------------------------

T_DECLARATION = "la photo d'un repas y figure"
T_CONTENU = "le contenu d'un repas ne porte pas le chemin de sa photo"
T_PRESERVE = "une ligne distante n'efface pas la photo locale"
T_INCONNU = "un repas inconnu localement arrive sans photo"


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

    def declaration_videe() -> None:
        # La colonne redevient transportable, sans que rien ne le dise : la
        # lecture l'emet, l'ecriture la remplace. La photo part chez l'autre
        # appareil, et celle de l'autre appareil est effacee.
        banc.suivre(DECLARATION).muter(DECLARATION_COMPLETE, DECLARATION_VIDE)

    def declaration_fausse() -> None:
        # L'exclusion designe une colonne qui n'existe nulle part. Elle a l'air
        # d'une decision et n'en est plus une : `photo_path` redevient ordinaire.
        banc.suivre(DECLARATION).muter(DECLARATION_COMPLETE, DECLARATION_FAUSSE)

    def contenu_non_filtre() -> None:
        # La troisieme exclusion disparait de `contenuDe`. C'est la mutation la
        # plus discrete : le contenu a toujours l'air complet.
        banc.suivre(LECTURE).muter(LOCALES_SEULES_EXCLUES, b"")

    def table_perdue() -> None:
        # La table n'est plus transmise : `colonnesLocalesSeulesDe('')` rend un
        # ensemble vide, et l'exclusion ne s'applique a personne.
        banc.suivre(LECTURE).muter(TABLE_TRANSMISE, TABLE_PERDUE)

    def ecriture_sans_preservation() -> None:
        # Le defaut central de l'ecriture : `insert ... replace` supprime la
        # ligne, et `photo_path` absent du contenu retombe a NULL.
        banc.suivre(LECTURE).muter(PRESERVATION, b"")

    def ecriture_sur_une_autre_ligne() -> None:
        # La valeur relue ne vient plus de la ligne ecrite. Un repas inconnu
        # localement heriterait de la photo du premier repas venu.
        banc.suivre(LECTURE).muter(ECRITURE_CIBLEE, b"")

    def commentaire_reformule() -> None:
        # Temoin negatif : une reformulation legitime ne doit rien faire tomber.
        banc.suivre(DECLARATION).muter(
            COMMENTAIRE_DECLARATION, COMMENTAIRE_REFORMULE
        )

    banc.cas("l'exclusion retiree de la declaration", T_DECLARATION, declaration_videe)
    banc.cas(
        "l'exclusion nomme une colonne inconnue", T_DECLARATION, declaration_fausse
    )
    banc.cas("la colonne remise dans le contenu", T_CONTENU, contenu_non_filtre)
    banc.cas("la table n'est plus transmise", T_CONTENU, table_perdue)
    banc.cas("l'ecriture ne preserve plus", T_PRESERVE, ecriture_sans_preservation)
    banc.cas(
        "l'ecriture relit une autre ligne", T_INCONNU, ecriture_sur_une_autre_ligne
    )
    banc.cas(
        "commentaire reformule", T_DECLARATION, commentaire_reformule, attendu=False
    )

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
        "vert — la retenue tombe sur chacune de ses six fautes, et pas sur une "
        "reformulation."
    )
    return 0


if __name__ == "__main__":
    sys.exit(principal())
