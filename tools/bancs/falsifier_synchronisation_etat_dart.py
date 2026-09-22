#!/usr/bin/env python3
"""Falsifie le passage de synchronisation : de quel compte il part, et avec quel jeton.

Ce que ce banc mesure
---------------------
`test/state/synchronisation_test.dart` regarde **l'en-tete reellement envoye**,
et ce banc fabrique les fautes qui devraient le faire tomber. Une faute d'ordre
ne se voit pas a la relecture : les deux ecritures sont justes prises isolement,
et c'est leur succession qui decide. Seule une mesure peut les separer.

Les cinq fautes
---------------
  1. **le service est lu avant le renouvellement.** Le transport est bati a
     partir de la session rangee ; lu trop tot, il part avec le jeton perime, et
     **chaque table** est refusee. La faute la plus discrete du lot : rien n'est
     faux, l'ordre seul est change ;
  2. **la session renouvelee n'est pas publiee.** Meme consequence, autre cause :
     le renouvellement reussit, mais rien ne le fait connaitre au transport. Le
     jeton neuf est range et n'est jamais envoye ;
  3. **un compte absent n'est plus refuse comme une session.** L'utilisateur lit
     « une erreur est survenue » au lieu de « reconnectez-vous » — le seul
     conseil utile a ce moment-la ;
  4. **le rapport du passage est jete.** Le passage a bien lieu, et l'ecran ne
     peut rien en dire : « aucun passage n'a encore eu lieu » s'affiche apres un
     passage. Une absence de mesure presentee comme un resultat ;
  5. **la garde du transport sans compte est retiree.** Un `!` a la place du
     refus : le fournisseur tombe sur un `TypeError`, qui ne dit rien de la
     cause et n'est pas un `StateError`.

Ce que ce banc ne falsifie pas
------------------------------
  - **le contenu du rapport** (lignes poussees, appliquees, identiques). Il
    appartient au service, et `falsifier_synchronisation_service_dart.py` le
    couvre table par table. Le mesurer ici une seconde fois ferait doublon ;
  - **l'ecran.** Les tests d'interface de `compte_section_test.dart` n'ont pas
    de banc, comme les autres ecrans du projet : ce qui est falsifie ici est la
    regle, pas son affichage.

Usage : python3 tools/bancs/falsifier_synchronisation_etat_dart.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, MesureImpossible  # noqa: E402
from banc_flutter import BancFlutter  # noqa: E402
from environnement_flutter import executable_flutter  # noqa: E402

PROVIDERS = "app/lib/state/providers.dart"
TESTS = "test/state/synchronisation_test.dart"

# A mettre a jour en meme temps que le fichier de tests, jamais pour faire
# passer le banc.
TESTS_ATTENDUS = 6

# --- ancres : au niveau octet, telles que `dart format` les ecrit ---

# 1. L'ordre : le renouvellement precede la lecture du service.
ORDRE_TENU = (
    b"      await _sessionUtilisable();\n"
    b"      state = AsyncData(\n"
    b"        await ref.read(serviceSynchronisationProvider).synchroniser(),\n"
    b"      );\n"
)
ORDRE_INVERSE = (
    b"      final service = ref.read(serviceSynchronisationProvider);\n"
    b"      await _sessionUtilisable();\n"
    b"      state = AsyncData(await service.synchroniser());\n"
)

# 2. La session renouvelee est publiee, et **avant** d'etre rendue.
PUBLICATION = (
    b"    // Rangee avant d'etre publiee : meme ordre que la connexion, meme raison.\n"
    b"    await ref.read(compteProvider.notifier).remplacer(neuve);\n"
)

# 3. Le refus d'un compte absent est celui d'une session.
REFUS_SANS_COMPTE = b"    if (session == null) throw const SessionRefuseeFailure();\n"
REFUS_AUTRE = b"    if (session == null) throw StateError('sans compte');\n"

# 4. Le rapport du passage est retenu, et non jete.
RAPPORT_RETENU = (
    b"      state = AsyncData(\n"
    b"        await ref.read(serviceSynchronisationProvider).synchroniser(),\n"
    b"      );\n"
)
RAPPORT_JETE = (
    b"      await ref.read(serviceSynchronisationProvider).synchroniser();\n"
    b"      state = const AsyncData(null);\n"
)

# 5. La garde du transport, quand aucun compte n'est connecte.
GARDE_SANS_COMPTE = (
    b"  final session = ref.watch(compteProvider).value;\n"
    b"  if (session == null) {\n"
    b"    throw StateError(\n"
    b"      'Aucun compte connecte : la synchronisation demande une session.',\n"
    b"    );\n"
    b"  }\n"
)
GARDE_SANS_COMPTE_ABSENTE = b"  final session = ref.watch(compteProvider).value!;\n"

# --- temoin negatif : une reformulation legitime ---

COMMENTAIRE = (
    b"    // Rangee avant d'etre publiee : meme ordre que la connexion, meme raison.\n"
)
COMMENTAIRE_REFORMULE = (
    b"    // Rangee avant d'etre publiee : meme ordre que la connexion, pour la meme raison.\n"
)

# --- noms des tests qui doivent tomber -----------------------------------------
#
# Le marqueur est un fragment du nom **rapporte**, donc decode : une apostrophe
# s'y ecrit telle quelle, jamais avec l'echappement Dart du source. Un marqueur
# qui ne designe aucun test est refuse par `BancFlutter.cas`, au lieu de se lire
# « non detecte ».

T_SANS_COMPTE = "sans compte, le passage est refuse"
T_RENOUVELE = "un jeton perime est renouvele"
T_REFUS = "un renouvellement refuse laisse la session"
T_RAPPORT = "rapport d'un passage est conserve"
T_CONFIG = "le transport refuse sans projet"


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

    def sans(libelle: str, marqueur: str, ancien: bytes) -> None:
        cas(libelle, marqueur, ancien, b"")

    # --- l'ordre, et la session ---
    cas(
        "le service est lu avant le renouvellement",
        T_RENOUVELE,
        ORDRE_TENU,
        ORDRE_INVERSE,
    )
    sans(
        "la session renouvelee n'est pas publiee",
        T_RENOUVELE,
        PUBLICATION,
    )

    # --- les refus ---
    cas(
        "un compte absent n'est plus une session refusee",
        T_SANS_COMPTE,
        REFUS_SANS_COMPTE,
        REFUS_AUTRE,
    )
    cas(
        "la garde du transport devient un `!`",
        T_CONFIG,
        GARDE_SANS_COMPTE,
        GARDE_SANS_COMPTE_ABSENTE,
    )

    # --- le rapport ---
    cas(
        "le rapport du passage est jete",
        T_RAPPORT,
        RAPPORT_RETENU,
        RAPPORT_JETE,
    )

    # --- temoin negatif ---
    banc.cas(
        "commentaire reformule",
        T_REFUS,
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
        "vert — le passage tombe sur chacune de ses cinq fautes, et pas sur une "
        "reformulation."
    )
    return 0


if __name__ == "__main__":
    sys.exit(principal())
