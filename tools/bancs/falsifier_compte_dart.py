#!/usr/bin/env python3
"""Falsifie le compte : ce qui est range, ce qui est efface, et dans quel ordre.

Pourquoi ce banc existe
-----------------------
`CompteNotifier` est le seul endroit du projet qui decide **ce qui reste sur
l'appareil** apres une connexion. Rien d'autre ne l'appelle encore : la section
Compte est la premiere a s'en servir, et elle est eprouvee a part. Ce fichier-la
ne tombe donc que si on l'eprouve lui.

Trois regles y sont tenues, et aucune n'est visible a la lecture
----------------------------------------------------------------
  - **rien n'est ecrit avant que le serveur ait repondu.** Une session de
    secours serait pire qu'aucune session : elle ferait croire a une connexion
    qui n'existe pas, et l'erreur ne se verrait qu'a la premiere requete de
    donnees, loin d'ici ;
  - **le trousseau d'abord, l'etat ensuite**, a la deconnexion. L'ordre inverse
    laisserait, si l'effacement echouait, une application qui se dit deconnectee
    alors que le redemarrage suivant lui donne tort ;
  - **la session est relue au demarrage**, pas seulement gardee en memoire. Sans
    cette relecture, l'utilisateur devrait se reconnecter a chaque lancement —
    et rien ne le dirait, puisque le mot de passe, lui, n'est jamais conserve.

Ce que ce banc ne peut pas mesurer
----------------------------------
Que le vrai trousseau se comporte comme le faux, ni que le serveur accepte la
requete. L'un demande un appareil, l'autre a ete mesure une fois contre le vrai
projet : des identifiants invalides y rendent `400` avec `error_code`, pas
`401`. Ce sont ces reponses-la que les tests simulent.

Usage : python3 tools/bancs/falsifier_compte_dart.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, MesureImpossible  # noqa: E402
from banc_flutter import BancFlutter  # noqa: E402
from environnement_flutter import executable_flutter  # noqa: E402

PROVIDERS = "app/lib/state/providers.dart"
TESTS = "test/state/compte_test.dart"

# A mettre a jour en meme temps que le fichier de tests, jamais pour faire
# passer le banc.
TESTS_ATTENDUS = 8

# --- ancres : au niveau octet, telles que `dart format` les ecrit ---

# 1 et 2. La connexion : ce qui est ecrit, et ce qui suit.
ECRITURE_ET_ETAT = (
    b"    await ref.read(secureStoreProvider).ecrireSession(session);\n"
    b"    state = AsyncData(session);\n"
)
ETAT_SEUL = b"    state = AsyncData(session);\n"
ECRITURE_SEULE = b"    await ref.read(secureStoreProvider).ecrireSession(session);\n"

# 3 et 4. La deconnexion, et l'ordre de ses deux gestes.
DECONNEXION_ORDONNEE = (
    b"  Future<void> deconnecter() async {\n"
    b"    await ref.read(secureStoreProvider).effacerSession();\n"
    b"    state = const AsyncData(null);\n"
    b"  }\n"
)
DECONNEXION_INVERSEE = (
    b"  Future<void> deconnecter() async {\n"
    b"    state = const AsyncData(null);\n"
    b"    await ref.read(secureStoreProvider).effacerSession();\n"
    b"  }\n"
)
EFFACEMENT = b"    await ref.read(secureStoreProvider).effacerSession();\n"

# 5. La relecture au demarrage.
RELECTURE = b"  Future<Session?> build() => ref.watch(secureStoreProvider).lireSession();\n"
RELECTURE_INERTE = b"  Future<Session?> build() async => null;\n"

# 6. La garde du client, quand la compilation ne porte pas de projet.
GARDE_PROJET = b"  if (!ref.watch(projetConfigureProvider)) {\n"
GARDE_ABSENTE = b"  if (false) {\n"

# --- temoin negatif : une reformulation legitime ---

COMMENTAIRE = (
    b"/// connexion ne se range pas ici : c'est l'ecran qui le montre, le temps d'une\n"
)
COMMENTAIRE_REFORMULE = (
    b"/// connexion ne se range pas ici : c'est l'ecran qui le montre, pendant une\n"
)

# --- noms des tests qui doivent tomber -----------------------------------------
#
# Les marqueurs evitent l'apostrophe **et son echappement**. Le nom compare par
# le banc est celui du rapport JSON, donc la chaine **decodee** : dans le source
# du test, l'apostrophe s'ecrit `\'`, et un marqueur qui la traverserait ne
# correspondrait ni au source ni au nom decode.

T_ECRITURE = "range la session dans le trousseau"
T_DECONNEXION = "deconnexion efface la session"
T_EFFACEMENT_RATE = "effacement rate laisse la session"
T_RELECTURE = "session rangee est relue"
T_CONFIG = "client suit la configuration"


def principal() -> int:
    flutter = executable_flutter()
    if flutter is None:
        print(
            "flutter introuvable : ni dans le SDK local, ni dans le PATH.",
            file=sys.stderr,
        )
        return 2

    banc = BancFlutter(RACINE / PROVIDERS, flutter, TESTS, TESTS_ATTENDUS)

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

    def cas(libelle: str, marqueur: str, ancien: bytes, nouveau: bytes) -> None:
        banc.cas(
            libelle,
            marqueur,
            lambda: banc.suivre(PROVIDERS).muter(ancien, nouveau),
        )

    # --- la connexion : ce qui reste sur l'appareil ---
    cas(
        "la session n'est plus rangee dans le trousseau",
        T_ECRITURE,
        ECRITURE_ET_ETAT,
        ETAT_SEUL,
    )
    cas(
        "l'etat n'est plus mis a jour apres une connexion",
        T_ECRITURE,
        ECRITURE_ET_ETAT,
        ECRITURE_SEULE,
    )

    # --- la deconnexion, et l'ordre de ses deux gestes ---
    cas(
        "la deconnexion efface l'etat avant le trousseau",
        T_EFFACEMENT_RATE,
        DECONNEXION_ORDONNEE,
        DECONNEXION_INVERSEE,
    )
    cas(
        "la deconnexion n'efface plus le trousseau",
        T_DECONNEXION,
        EFFACEMENT,
        b"",
    )

    # --- le demarrage, et la garde de compilation ---
    cas(
        "la session rangee n'est plus relue au demarrage",
        T_RELECTURE,
        RELECTURE,
        RELECTURE_INERTE,
    )
    cas(
        "un exemplaire sans projet construit quand meme un client",
        T_CONFIG,
        GARDE_PROJET,
        GARDE_ABSENTE,
    )

    # --- temoin negatif ---
    banc.cas(
        "commentaire reformule",
        T_RELECTURE,
        lambda: banc.suivre(PROVIDERS).muter(COMMENTAIRE, COMMENTAIRE_REFORMULE),
        attendu=False,
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
        "vert — le compte tombe sur chacune de ses six fautes, et pas sur une "
        "reformulation."
    )
    return 0


if __name__ == "__main__":
    sys.exit(principal())
