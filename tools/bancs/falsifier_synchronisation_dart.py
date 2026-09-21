#!/usr/bin/env python3
"""Falsifie la planification d'une synchronisation.

La regle d'arbitrage decide pour **une** ligne ; ce fichier decide pour un
**ensemble**. Le planificateur ajoute donc trois questions qui n'existent pas a
l'echelle d'une ligne, et chacune peut se tromper en silence :

  - une ligne presente **d'un seul cote** n'est pas un arbitrage, c'est une
    insertion. L'oublier fait disparaitre une donnee a jamais, sans erreur ;
  - l'**ordre** du plan ne doit pas dependre de l'ordre des lectures SQL ;
  - une **cle en double** rendrait la ligne gagnante dependante de celle qui a
    ete lue en dernier.

Le cas le plus instructif est celui qui remplace l'empreinte de contenu par la
**cle** de la ligne : c'est l'ecriture naturelle — la cle est la, elle est
stable, elle a l'air de convenir — et elle declare « identiques » deux contenus
qui different des que les dates sont egales. Deux appareils cessent alors de se
transmettre leurs modifications, et rien ne le signale.

Usage : python3 tools/bancs/falsifier_synchronisation_dart.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, MesureImpossible  # noqa: E402
from banc_flutter import BancFlutter  # noqa: E402
from environnement_flutter import executable_flutter  # noqa: E402

PLAN = "app/lib/models/synchronisation.dart"
TESTS = "test/models/synchronisation_test.dart"

# A mettre a jour en meme temps que le fichier de tests, jamais pour faire
# passer le banc.
TESTS_ATTENDUS = 24

# --- ancres : au niveau octet, telles que `dart format` les ecrit ---

LIGNE_LOCALE_SEULE = (
    b"  for (final locale in locales) {\n"
    b"    if (!clesDistantes.contains(locale.cle)) aPousser.add(locale);\n"
    b"  }\n"
)
LIGNE_LOCALE_IGNOREE = b""

LIGNE_DISTANTE_SEULE = (
    b"    if (locale == null) {\n"
    b"      aAppliquer.add(distante);\n"
    b"      continue;\n"
    b"    }\n"
)
LIGNE_DISTANTE_IGNOREE = b"    if (locale == null) {\n      continue;\n    }\n"

TRI_DU_PLAN = (
    b"    aPousser: aPousser..sort(_parCle),\n"
    b"    aAppliquer: aAppliquer..sort(_parCle),\n"
    b"    identiques: identiques..sort(),\n"
)
PLAN_NON_TRIE = (
    b"    aPousser: aPousser,\n"
    b"    aAppliquer: aAppliquer,\n"
    b"    identiques: identiques,\n"
)

COTES = b"    switch (arbitrer(locale: locale.version, distante: distante.version)) {\n"
COTES_INVERSES = (
    b"    switch (arbitrer(locale: distante.version, distante: locale.version)) {\n"
)

EMPREINTE_DU_CONTENU = b"         empreinte: empreinteDeContenu(contenu),\n"
EMPREINTE_DE_LA_CLE = b"         empreinte: cle,\n"

CONTROLE_CLE_DOUBLE = (
    b"    if (index.containsKey(ligne.cle)) {\n"
    b"      throw ArgumentError(\n"
    b"        'Cle $cote en double : \xc2\xab ${ligne.cle} \xc2\xbb. Deux lignes de meme cle '\n"
    b"        'rendraient le plan dependant de l\\'ordre de la liste, donc la ligne '\n"
    b"        'gagnante dependrait de celle qui a ete lue en dernier.',\n"
    b"      );\n"
    b"    }\n"
)

COMMENTAIRE = b"/// Compare deux etats et rend ce qu'il faut faire pour les accorder.\n"
COMMENTAIRE_REFORMULE = b"/// Compare deux etats et rend le travail qui les accorde.\n"

# --- noms des tests qui doivent tomber -----------------------------------------

T_SYMETRIE_PLAN = "le plan est le meme, en miroir, pour chaque paire"
T_LOCALE_SEULE = "une ligne locale que la distante ignore est a pousser"
T_DISTANTE_SEULE = "une ligne distante inconnue localement est a appliquer"
T_TRI = "les listes du plan sont triees par cle"
T_DISTANTE_RECENTE = "la version distante plus recente est appliquee"
T_EMPREINTE = "l'empreinte tranche au lieu de declarer identique"
T_CLE_DOUBLE = "deux lignes locales de meme cle font lever"


def principal() -> int:
    flutter = executable_flutter()
    if flutter is None:
        print(
            "flutter introuvable : ni dans le SDK local, ni dans le PATH.",
            file=sys.stderr,
        )
        return 2

    banc = BancFlutter(RACINE / PLAN, flutter, TESTS, TESTS_ATTENDUS)

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

    def ligne_locale_seule_oubliee() -> None:
        # Une ligne que le serveur ne connait pas n'est plus poussee. Elle
        # n'existe alors que sur cet appareil, pour toujours.
        banc.suivre(PLAN).muter(LIGNE_LOCALE_SEULE, LIGNE_LOCALE_IGNOREE)

    def ligne_distante_seule_oubliee() -> None:
        # Une ligne que cet appareil ne connait pas n'est plus ecrite. La
        # donnee reste sur le serveur et n'arrive jamais.
        banc.suivre(PLAN).muter(LIGNE_DISTANTE_SEULE, LIGNE_DISTANTE_IGNOREE)

    def plan_non_trie() -> None:
        # Le plan suit l'ordre des listes fournies, donc l'ordre des lectures
        # SQL, qui n'est garanti par rien.
        banc.suivre(PLAN).muter(TRI_DU_PLAN, PLAN_NON_TRIE)

    def cotes_inverses() -> None:
        # Les deux versions sont presentees a l'envers : chaque verdict
        # s'inverse, et l'appareil ecrit systematiquement la version perdante.
        banc.suivre(PLAN).muter(COTES, COTES_INVERSES)

    def empreinte_prise_sur_la_cle() -> None:
        # L'erreur la plus seduisante : la cle est stable et disponible, donc
        # elle « suffit ». Deux contenus differents a date egale sont alors
        # declares identiques, et les modifications cessent de circuler.
        banc.suivre(PLAN).muter(EMPREINTE_DU_CONTENU, EMPREINTE_DE_LA_CLE)

    def cle_double_acceptee() -> None:
        # La derniere ligne lue gagne : le plan depend de l'ordre des lectures.
        banc.suivre(PLAN).muter(CONTROLE_CLE_DOUBLE, b"")

    def commentaire_reformule() -> None:
        # Temoin negatif : une reformulation legitime ne doit rien faire tomber.
        banc.suivre(PLAN).muter(COMMENTAIRE, COMMENTAIRE_REFORMULE)

    banc.cas("ligne locale seule oubliee", T_LOCALE_SEULE, ligne_locale_seule_oubliee)
    banc.cas(
        "ligne distante seule oubliee", T_DISTANTE_SEULE, ligne_distante_seule_oubliee
    )
    banc.cas("plan non trie", T_TRI, plan_non_trie)
    banc.cas("cotes inverses dans l'arbitrage", T_DISTANTE_RECENTE, cotes_inverses)
    banc.cas(
        "empreinte prise sur la cle", T_EMPREINTE, empreinte_prise_sur_la_cle
    )
    banc.cas("cle en double acceptee", T_CLE_DOUBLE, cle_double_acceptee)
    banc.cas(
        "commentaire reformule", T_SYMETRIE_PLAN, commentaire_reformule, attendu=False
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
        "vert — le plan tombe sur chacune de ses six fautes, et pas sur une "
        "reformulation."
    )
    return 0


if __name__ == "__main__":
    sys.exit(principal())
