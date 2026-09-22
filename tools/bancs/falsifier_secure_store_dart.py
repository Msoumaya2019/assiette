#!/usr/bin/env python3
"""Falsifie le stockage de la session dans le trousseau.

Pourquoi ce banc existe
-----------------------
`secure_store.dart` est le **seul** fichier du projet qui touche au trousseau du
systeme, et il porte maintenant deux choses au lieu d'une : la cle d'analyse du
fournisseur, et la session du compte. Deux valeurs dans un meme magasin, c'est
une occasion de les confondre — et la confusion serait silencieuse, parce que
les deux s'ecrivent et se relisent de la meme facon.

Ce que ce banc mesure, et comment
---------------------------------
Le trousseau ne s'ouvre pas dans un test. `SecureStore` prend donc son stockage
en parametre, et les tests lui donnent un faux en memoire : c'est le **vrai**
chemin de code qui s'execute — lecture, ecriture, effacement, et relecture d'un
contenu abime.

Deux regles ont ete ecrites puis retirees, et ce banc dit pourquoi
------------------------------------------------------------------
  - **le controle d'ecriture vide** avant decodage. `jsonDecode` refuse deja le
    vide et les espaces : une valeur blanche suit exactement le meme chemin avec
    ou sans le controle. Aucun test ne pouvait distinguer les deux ;
  - dans `client_authentification.dart`, **le controle du type de contenu** d'une
    reponse d'erreur. Meme raison, meme remede.

Une regle qu'aucune mesure ne separe est un passif : elle coute une branche a
relire et fait croire a une protection.

Un cas pour plusieurs marqueurs
-------------------------------
La mutation des quatre gardes du decodeur est **une** faute, et elle fait tomber
quatre tests : le jeton de rafraichissement absent, le jeton d'acces vide,
l'echeance qui n'est pas un entier, le compte absent. Le banc en mesure deux —
un champ **absent** et un champ de **mauvais type**, qui sont deux chemins
distincts — et ne rejoue pas quatre fois la meme faute pour le plaisir de
compter.

L'adresse du compte, et pourquoi elle se mesure ici
---------------------------------------------------
`Session` porte desormais l'adresse du compte, et deux fautes la menacent dans
ce fichier precisement : ne plus l'**ecrire** dans le trousseau — elle
disparaitrait au redemarrage, et l'ecran ne saurait plus de quel compte il
s'agit, au pire moment pour le comprendre —, et la **refuser** quand son type
est inattendu alors qu'elle est facultative, ce qui emporterait une session par
ailleurs intacte pour une simple etiquette.

Ce qu'il ne peut pas verifier
-----------------------------
Que le vrai trousseau — Keychain sur iOS, Keystore sur Android — se comporte
comme ce faux. Cela demande un appareil, et cela reste a faire.

Usage : python3 tools/bancs/falsifier_secure_store_dart.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, MesureImpossible  # noqa: E402
from banc_flutter import BancFlutter  # noqa: E402
from environnement_flutter import executable_flutter  # noqa: E402

STORE = "app/lib/services/secure_store.dart"
SESSION = "app/lib/models/session.dart"
TESTS = "test/services/secure_store_test.dart"

# A mettre a jour en meme temps que le fichier de tests, jamais pour faire
# passer le banc.
TESTS_ATTENDUS = 15

# --- ancres : au niveau octet, telles que `dart format` les ecrit ---

# 1. La cle de la session, qui ne doit pas etre celle de l'analyse.
CLE_SESSION = b"  static const String _sessionKey = 'session';\n"
CLE_CONFONDUE = b"  static const String _sessionKey = 'provider_api_key';\n"

# 2. Le decodage, et ce qu'il fait d'un contenu abime.
DECODAGE_PROTEGE = (
    b"    try {\n"
    b"      return Session.depuisJson(jsonDecode(brut));\n"
    b"    } on FormatException {\n"
    b"      return null;\n"
    b"    }\n"
)
DECODAGE_NU = b"    return Session.depuisJson(jsonDecode(brut));\n"

# 3. La session rangee en une seule ecriture, et encodee.
#
# L'ancre porte la **declaration** entiere, et non la seule expression : une
# mutation qui veut ecrire deux fois doit passer par un corps de bloc, et
# remplacer la seule expression laisserait la seconde ecriture au niveau du
# fichier — ce qui ne compile pas. Mesure faite : le banc a refuse de conclure en
# citant « Non-optional parameters can't have a default value », ce qui etait
# l'erreur d'analyse, pas la faute cherchee.
ECRITURE_ENCODEE = (
    b"  Future<void> ecrireSession(Session session) =>\n"
    b"      _storage.write(key: _sessionKey, value: jsonEncode(session.versJson()));\n"
)
ECRITURE_NON_ENCODEE = (
    b"  Future<void> ecrireSession(Session session) =>\n"
    b"      _storage.write(key: _sessionKey, value: session.versJson().toString());\n"
)
ECRITURE_EN_DEUX_TEMPS = (
    b"  Future<void> ecrireSession(Session session) async {\n"
    b"    await _storage.write(key: _sessionKey, value: session.utilisateur);\n"
    b"    await _storage.write(\n"
    b"      key: _sessionKey,\n"
    b"      value: jsonEncode(session.versJson()),\n"
    b"    );\n"
    b"  }\n"
)

# 4. L'effacement d'une session.
EFFACEMENT = b"  Future<void> effacerSession() => _storage.delete(key: _sessionKey);\n"
EFFACEMENT_INERTE = b"  Future<void> effacerSession() => Future<void>.value();\n"

# 5. L'effacement de tout, qui doit emporter la session comme le reste.
WIPE_TOTAL = b"  Future<void> wipe() => _storage.deleteAll();\n"
WIPE_PARTIEL = b"  Future<void> wipe() => _storage.delete(key: _providerKeyKey);\n"

# 6. Les quatre champs exiges par le decodeur, dans `session.dart`.
CHAMPS_EXIGES = (
    b"    if (acces is! String || acces.isEmpty) return null;\n"
    b"    if (rafraichissement is! String || rafraichissement.isEmpty) return null;\n"
    b"    if (expireLe is! int) return null;\n"
    b"    if (utilisateur is! String || utilisateur.isEmpty) return null;\n"
    b"\n"
    b"    return Session(\n"
    b"      jetonAcces: acces,\n"
    b"      jetonRafraichissement: rafraichissement,\n"
    b"      expireLe: expireLe,\n"
    b"      utilisateur: utilisateur,\n"
    b"      adresse: adresseBrute is String ? adresseBrute : null,\n"
    b"    );\n"
)
CHAMPS_SECOURUS = (
    b"    final accesSain = acces is String && acces.isNotEmpty ? acces : '';\n"
    b"    final rafraichissementSain =\n"
    b"        rafraichissement is String && rafraichissement.isNotEmpty\n"
    b"        ? rafraichissement\n"
    b"        : '';\n"
    b"    final echeanceSaine = expireLe is int ? expireLe : 0;\n"
    b"    final utilisateurSain = utilisateur is String && utilisateur.isNotEmpty\n"
    b"        ? utilisateur\n"
    b"        : '';\n"
    b"\n"
    b"    return Session(\n"
    b"      jetonAcces: accesSain,\n"
    b"      jetonRafraichissement: rafraichissementSain,\n"
    b"      expireLe: echeanceSaine,\n"
    b"      utilisateur: utilisateurSain,\n"
    b"      adresse: adresseBrute is String ? adresseBrute : null,\n"
    b"    );\n"
)

# 7. L'adresse du compte, ecrite puis relue.
#
# Le titre du test de relecture dit « a l'identique » : il porte donc sur
# **tous** les champs. Sans cette ancre, retirer l'adresse de l'ecriture ne
# ferait tomber aucun test — la session resterait valide, et l'ecran perdrait
# seulement de savoir de quel compte il s'agit, apres un redemarrage.
VERS_JSON_COMPLET = (
    b"    'utilisateur': utilisateur,\n"
    b"    'adresse': adresse,\n"
    b"  };\n"
)
VERS_JSON_SANS_ADRESSE = (
    b"    'utilisateur': utilisateur,\n"
    b"  };\n"
)

# 8. L'adresse facultative : un type inattendu la rend absente, sans plus.
ADRESSE_DEGRADEE = b"      adresse: adresseBrute is String ? adresseBrute : null,\n"
ADRESSE_EXIGEE = b"      adresse: adresseBrute as String,\n"

# --- temoin negatif : une reformulation legitime ---

COMMENTAIRE = (
    b"  /// Le jeton de rafraichissement est la raison d'etre de ce stockage : c'est\n"
)
COMMENTAIRE_REFORMULE = (
    b"  /// Le jeton de rafraichissement est la raison d'etre de ce stockage, c'est\n"
)

# --- noms des tests qui doivent tomber -----------------------------------------
#
# Les marqueurs evitent l'apostrophe **et son echappement**. Le nom compare par
# le banc est celui du rapport JSON, donc la chaine **decodee** : dans le source
# du test, l'apostrophe s'ecrit `\'`, et un marqueur qui la traverserait ne
# correspondrait ni au source ni au nom decode. Mesure faite sur deux bancs
# precedents : des marqueurs ecrits avec leur apostrophe ne correspondaient a
# **rien**.

T_MELANGE = "ne se melangent pas"
T_UNE_ECRITURE = "part en une seule ecriture"
T_RELECTURE = "se relit a l"
T_EFFACEMENT = "effacement retire"
T_WIPE = "wipe efface aussi"
T_ILLISIBLE = "pas du JSON se lit"
T_SANS_RAFRAICHISSEMENT = "sans jeton de rafraichissement est refusee"
T_ACCES_VIDE = "est vide est refusee"
T_ADRESSE_INATTENDUE = "type inattendu ne fait pas tomber"


def principal() -> int:
    flutter = executable_flutter()
    if flutter is None:
        print(
            "flutter introuvable : ni dans le SDK local, ni dans le PATH.",
            file=sys.stderr,
        )
        return 2

    banc = BancFlutter(RACINE / STORE, flutter, TESTS, TESTS_ATTENDUS)

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
            lambda: banc.suivre(STORE).muter(ancien, nouveau),
        )

    def cas_session(
        libelle: str, marqueur: str, ancien: bytes, nouveau: bytes
    ) -> None:
        banc.cas(
            libelle,
            marqueur,
            lambda: banc.suivre(SESSION).muter(ancien, nouveau),
        )

    # --- le magasin, ou deux valeurs cohabitent ---
    cas(
        "la session est rangee sous la cle de l'analyse",
        T_MELANGE,
        CLE_SESSION,
        CLE_CONFONDUE,
    )

    # --- la relecture ---
    cas(
        "la session n'est plus encodee",
        T_RELECTURE,
        ECRITURE_ENCODEE,
        ECRITURE_NON_ENCODEE,
    )
    cas(
        "la session part en deux ecritures",
        T_UNE_ECRITURE,
        ECRITURE_ENCODEE,
        ECRITURE_EN_DEUX_TEMPS,
    )
    cas(
        "un contenu abime fait tomber la lecture",
        T_ILLISIBLE,
        DECODAGE_PROTEGE,
        DECODAGE_NU,
    )

    # --- l'effacement ---
    cas(
        "l'effacement ne fait plus rien",
        T_EFFACEMENT,
        EFFACEMENT,
        EFFACEMENT_INERTE,
    )
    cas("wipe n'efface plus tout", T_WIPE, WIPE_TOTAL, WIPE_PARTIEL)

    # --- le decodeur, et ses quatre gardes ---
    cas_session(
        "un jeton de rafraichissement absent n'est plus exige",
        T_SANS_RAFRAICHISSEMENT,
        CHAMPS_EXIGES,
        CHAMPS_SECOURUS,
    )
    cas_session(
        "un jeton d'acces vide n'est plus refuse",
        T_ACCES_VIDE,
        CHAMPS_EXIGES,
        CHAMPS_SECOURUS,
    )

    # --- l'adresse du compte ---
    cas_session(
        "l'adresse n'est plus ecrite dans le trousseau",
        T_RELECTURE,
        VERS_JSON_COMPLET,
        VERS_JSON_SANS_ADRESSE,
    )
    cas_session(
        "une adresse d'un type inattendu fait tomber la session",
        T_ADRESSE_INATTENDUE,
        ADRESSE_DEGRADEE,
        ADRESSE_EXIGEE,
    )

    # --- temoin negatif ---
    banc.cas(
        "commentaire reformule",
        T_MELANGE,
        lambda: banc.suivre(STORE).muter(COMMENTAIRE, COMMENTAIRE_REFORMULE),
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
        "vert — le trousseau tombe sur chacune de ses dix fautes, et pas sur une "
        "reformulation."
    )
    return 0


if __name__ == "__main__":
    sys.exit(principal())
