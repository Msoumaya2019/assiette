#!/usr/bin/env python3
"""Falsifie le client d'authentification.

Pourquoi ce banc existe
-----------------------
`client_authentification.dart` est le seul endroit du projet qui parle au serveur
d'authentification. Rien d'autre ne l'appelle : le transport recoit un jeton deja
obtenu, et le service de synchronisation ne connait ni jeton ni session. Ce
fichier-la ne tombe donc que si on l'eprouve lui.

Ce que la specification a fait ecrire, puis retirer
---------------------------------------------------
`openapi.yaml` de `supabase/auth` avertit : « Not all HTTP 5XX errors are
generated from Auth, and they may serve non-JSON content. Make sure you inspect
the `Content-Type` header before parsing as JSON. »

Un controle explicite du type de contenu a donc ete ecrit. Il a ete **retire**,
et ce banc dit pourquoi : la lecture du corps ne leve jamais, donc le resultat
etait **identique** avec et sans ce controle. Aucun test ne pouvait les
distinguer, et une regle qu'aucune mesure ne separe est un passif — elle coute
une branche a relire et fait croire a une protection.

L'avertissement est satisfait autrement, et plus surement : `_corps` rend `null`
sur ce qu'elle ne sait pas lire, la reponse tombe dans l'echelle des codes, et
une panne serveur reste une panne serveur — reessayable. Le cas 13 le mesure.

Ce que ce banc refuse de falsifier, et pourquoi
-----------------------------------------------
  - **la lecture d'un en-tete de reponse.** Ce client n'en lit aucun. Le
    transport a souffert de la casse de `Date` ; la lecon ne se transpose pas la
    ou il n'y a rien a lire, et un cas qui la rejouerait eprouverait une regle
    qui n'existe pas.
  - **l'ordre du statut `429` avant le corps.** Le deplacer change quel message
    sort, pas si le refus est reconnu : les deux chemins rendent une
    `RateLimitFailure`. Un cas qui ne deplace pas le verdict n'a rien a faire
    ici. Ce qui est falsifie, c'est le **retrait** du controle, qui lui se voit.

Usage : python3 tools/bancs/falsifier_client_authentification_dart.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, MesureImpossible  # noqa: E402
from banc_flutter import BancFlutter  # noqa: E402
from environnement_flutter import executable_flutter  # noqa: E402

CLIENT = "app/lib/services/client_authentification.dart"
SESSION = "app/lib/models/session.dart"
TESTS = "test/services/client_authentification_test.dart"

# A mettre a jour en meme temps que le fichier de tests, jamais pour faire
# passer le banc.
TESTS_ATTENDUS = 26

# --- ancres : au niveau octet, telles que `dart format` les ecrit ---

# 1. La cle publique, exigee sur chaque point d'entree du serveur.
CLE_PUBLIQUE = b"    'apikey': clePublique,\n"

# 2. L'adresse nettoyee, et le mot de passe qui ne l'est pas.
ADRESSE_NETTOYEE = b"    'email': email.trim(),\n"
ADRESSE_BRUTE = b"    'email': email,\n"
MOT_DE_PASSE_INTACT = b"    'password': motDePasse,\n"
MOT_DE_PASSE_ROGNE = b"    'password': motDePasse.trim(),\n"

# 3. Le type de subvention, qui distingue les deux operations.
GRANT_TYPE_TRANSMIS = b"    ).replace(queryParameters: {'grant_type': type});\n"
GRANT_TYPE_FIGE = (
    b"    ).replace(queryParameters: {'grant_type': 'password'});\n"
)

# 4. L'identifiant du compte, extrait de l'objet `user`.
IDENTIFIANT_EXTRAIT = (
    b"    final identifiant = utilisateur is Map ? utilisateur['id'] : null;\n"
)
IDENTIFIANT_CONFONDU = (
    b"    final identifiant = utilisateur is Map\n"
    b"        ? utilisateur.toString()\n"
    b"        : null;\n"
)
COMPTE_PAR_DEFAUT = (
    b"    final identifiant = utilisateur is Map\n"
    b"        ? utilisateur['id']\n"
    b"        : 'compte-par-defaut';\n"
)

# 5. Les deux unites d'expiration.
EXPIRES_AT_CONVERTI = b"    if (absolu is num) return absolu.toInt() * 1000;\n"
EXPIRES_AT_BRUT = b"    if (absolu is num) return absolu.toInt();\n"
EXPIRES_IN_CONVERTI = (
    b"      return DateTime.now().millisecondsSinceEpoch + relatif.toInt() * 1000;\n"
)
EXPIRES_IN_BRUT = b"      return relatif.toInt();\n"

# 6. Les deux refus que l'interface ne doit pas confondre.
IDENTIFIANTS_REFUSES = b"        return const IdentifiantsRefusesFailure();\n"
IDENTIFIANTS_CONFONDUS = b"        return const SessionRefuseeFailure();\n"
CONFIRMATION_DITE = b"        return const AdresseNonConfirmeeFailure();\n"

# 7. La limite de debit annoncee en `400` : c'est `error_code` qui decide.
LIMITE_400_RECONNUE = b"      case 'over_request_rate_limit':\n"
LIMITE_400_IGNOREE = b"      case 'over_request_rate_limit_':\n"

# 8. Le statut, regarde avant le corps.
STATUT_429_REGARDE = b"    if (reponse.statusCode == 429) throw const RateLimitFailure();\n"

# 9. Le meme `401` lu differemment selon l'operation.
RAFRAICHISSEMENT_DISTINGUE = (
    b"      if (type == _grantRafraichissement) return const SessionRefuseeFailure();\n"
)

# 10. Une panne serveur, reessayable.
PANNE_REESSAYABLE = (
    b"        hint: 'Reessayez dans quelques instants.',\n"
    b"        isRetryable: true,\n"
)
PANNE_DEFINITIVE = (
    b"        hint: 'Reessayez dans quelques instants.',\n"
    b"        isRetryable: false,\n"
)

# 11. Les trois champs exiges ensemble.
CHAMPS_EXIGES = (
    b"    if (acces is! String || acces.isEmpty) {\n"
    b"      throw const InvalidResponseFailure();\n"
    b"    }\n"
    b"    if (rafraichissement is! String || rafraichissement.isEmpty) {\n"
    b"      throw const InvalidResponseFailure();\n"
    b"    }\n"
    b"    if (identifiant is! String || identifiant.isEmpty) {\n"
    b"      throw const InvalidResponseFailure();\n"
    b"    }\n"
    b"\n"
    b"    return Session(\n"
    b"      jetonAcces: acces,\n"
    b"      jetonRafraichissement: rafraichissement,\n"
    b"      expireLe: _expiration(corps),\n"
    b"      utilisateur: identifiant,\n"
    b"    );\n"
)
CHAMPS_SECOURUS = (
    b"    final accesSain = acces is String && acces.isNotEmpty ? acces : '';\n"
    b"    final rafraichissementSain =\n"
    b"        rafraichissement is String && rafraichissement.isNotEmpty\n"
    b"        ? rafraichissement\n"
    b"        : '';\n"
    b"    final identifiantSain = identifiant is String && identifiant.isNotEmpty\n"
    b"        ? identifiant\n"
    b"        : '';\n"
    b"\n"
    b"    return Session(\n"
    b"      jetonAcces: accesSain,\n"
    b"      jetonRafraichissement: rafraichissementSain,\n"
    b"      expireLe: _expiration(corps),\n"
    b"      utilisateur: identifiantSain,\n"
    b"    );\n"
)

# 12. Le corps illisible, qui ne doit pas devenir une session.
CORPS_ILLISIBLE_REFUSE = (
    b"    } on FormatException {\n      return null;\n    }\n"
)
CORPS_ILLISIBLE_SECOURU = (
    b"    } on FormatException {\n"
    b"      return const {\n"
    b"        'access_token': 'x',\n"
    b"        'refresh_token': 'y',\n"
    b"        'user': {'id': 'z'},\n"
    b"      };\n"
    b"    }\n"
)

# 13. Les trois pannes de transport, chacune sur sa branche.
COUPURE_TRADUITE = (
    b"    } on http.ClientException {\n      throw const NetworkFailure();\n"
)
DELAI_BORNE = b"      return await requete().timeout(delai);\n"
DELAI_SANS_BORNE = b"      return await requete();\n"
CLIENT_INJECTE_EPARGNE = b"    if (!_clientFourni) _client.close();\n"
CLIENT_INJECTE_FERME = b"    _client.close();\n"

# 14. La session elle-meme, dans son propre fichier.
EXPIRATION_INCONNUE_NEUTRE = b"    if (expireLe == 0) return false;\n"
EXPIRATION_INCONNUE_RENOUVELEE = b"    if (expireLe == 0) return true;\n"
MARGE_APPLIQUEE = b"    return maintenant + marge.inMilliseconds >= expireLe;\n"
MARGE_DISPARUE = b"    return maintenant >= expireLe;\n"

# --- temoin negatif : une reformulation legitime ---

COMMENTAIRE = (
    b"    // Le statut est regarde **avant** le corps : un `429` peut venir d'un\n"
    b"    // intermediaire et ne rien porter d'exploitable, alors que le refus, lui,\n"
    b"    // est certain.\n"
)
COMMENTAIRE_REFORMULE = (
    b"    // Le statut est regarde **avant** le corps : un `429` peut venir d'un\n"
    b"    // intermediaire sans rien d'exploitable, alors que le refus, lui, est\n"
    b"    // certain.\n"
)

# --- noms des tests qui doivent tomber -----------------------------------------
#
# Les marqueurs evitent l'apostrophe **et son echappement**. Le nom compare par
# le banc est celui du rapport JSON, donc la chaine **decodee** : dans le source
# du test, l'apostrophe s'ecrit `\'`, et un marqueur qui la traverserait ne
# correspondrait ni au source ni au nom decode. Mesure faite sur le banc du
# transport : cinq marqueurs ecrits avec leur apostrophe ne correspondaient a
# **rien**.

T_CLE = "cle publique accompagne"
T_ADRESSE = "adresse est nettoyee"
T_GRANT = "requete porte son grant_type"
T_SESSION = "une session revient complete"
T_EXPIRES_AT = "expires_at est lu en secondes"
T_EXPIRES_IN = "expires_in sert de repli"
T_IDENTIFIANTS = "identifiants invalides ne sont pas"
T_CONFIRMATION = "adresse non confirmee est dite"
T_LIMITE_400 = "limite de debit annoncee"
T_429 = "429 reste une limite"
T_401_RAFRAICHISSEMENT = "401 sur un rafraichissement"
T_PANNE = "panne en HTML reste"
T_SANS_JETON = "une reponse sans jeton d"
T_SANS_COMPTE = "une session sans compte"
T_CORPS_ILLISIBLE = "corps illisible en 200"
T_COUPURE = "coupure reseau est traduite"
T_CONNEXION_ROMPUE = "connexion rompue est traduite"
T_DELAI = "delai depasse est traduit"
T_CLIENT = "client injecte n"
T_EXPIRATION = "expiration inconnue ne declenche"
T_MARGE = "marge fait expirer"


def principal() -> int:
    flutter = executable_flutter()
    if flutter is None:
        print(
            "flutter introuvable : ni dans le SDK local, ni dans le PATH.",
            file=sys.stderr,
        )
        return 2

    banc = BancFlutter(RACINE / CLIENT, flutter, TESTS, TESTS_ATTENDUS)

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
            lambda: banc.suivre(CLIENT).muter(ancien, nouveau),
        )

    def cas_session(
        libelle: str, marqueur: str, ancien: bytes, nouveau: bytes
    ) -> None:
        banc.cas(
            libelle,
            marqueur,
            lambda: banc.suivre(SESSION).muter(ancien, nouveau),
        )

    def sans(libelle: str, marqueur: str, ancien: bytes) -> None:
        cas(libelle, marqueur, ancien, b"")

    # --- la requete de connexion ---
    sans("la cle publique n'est plus transmise", T_CLE, CLE_PUBLIQUE)
    cas("l'adresse n'est plus nettoyee", T_ADRESSE, ADRESSE_NETTOYEE, ADRESSE_BRUTE)
    cas(
        "le mot de passe est rogne",
        T_ADRESSE,
        MOT_DE_PASSE_INTACT,
        MOT_DE_PASSE_ROGNE,
    )

    # --- la session rendue ---
    cas(
        "le type de subvention est fige sur le mot de passe",
        T_GRANT,
        GRANT_TYPE_TRANSMIS,
        GRANT_TYPE_FIGE,
    )
    cas(
        "l'identifiant du compte n'est plus extrait",
        T_SESSION,
        IDENTIFIANT_EXTRAIT,
        IDENTIFIANT_CONFONDU,
    )
    cas(
        "expires_at n'est plus converti en millisecondes",
        T_EXPIRES_AT,
        EXPIRES_AT_CONVERTI,
        EXPIRES_AT_BRUT,
    )
    cas(
        "expires_in n'est plus converti en millisecondes",
        T_EXPIRES_IN,
        EXPIRES_IN_CONVERTI,
        EXPIRES_IN_BRUT,
    )

    # --- les refus ---
    cas(
        "des identifiants refuses redeviennent une session refusee",
        T_IDENTIFIANTS,
        IDENTIFIANTS_REFUSES,
        IDENTIFIANTS_CONFONDUS,
    )
    cas(
        "une adresse non confirmee est confondue avec un refus d'identifiants",
        T_CONFIRMATION,
        CONFIRMATION_DITE,
        IDENTIFIANTS_REFUSES,
    )
    cas(
        "une limite de debit annoncee en 400 n'est plus reconnue",
        T_LIMITE_400,
        LIMITE_400_RECONNUE,
        LIMITE_400_IGNOREE,
    )
    sans("le statut 429 n'est plus regarde", T_429, STATUT_429_REGARDE)
    sans(
        "un 401 sur un rafraichissement n'est plus distingue",
        T_401_RAFRAICHISSEMENT,
        RAFRAICHISSEMENT_DISTINGUE,
    )

    # --- les reponses illisibles ---
    cas(
        "une panne serveur n'est plus reessayable",
        T_PANNE,
        PANNE_REESSAYABLE,
        PANNE_DEFINITIVE,
    )
    cas(
        "les trois champs de la session ne sont plus exiges",
        T_SANS_JETON,
        CHAMPS_EXIGES,
        CHAMPS_SECOURUS,
    )
    cas(
        "un compte absent recoit un identifiant de secours",
        T_SANS_COMPTE,
        IDENTIFIANT_EXTRAIT,
        COMPTE_PAR_DEFAUT,
    )
    cas(
        "un corps illisible devient une session de secours",
        T_CORPS_ILLISIBLE,
        CORPS_ILLISIBLE_REFUSE,
        CORPS_ILLISIBLE_SECOURU,
    )

    # --- le transport ---
    sans("la connexion rompue n'est plus traduite", T_CONNEXION_ROMPUE, COUPURE_TRADUITE)
    cas("le delai n'est plus borne", T_DELAI, DELAI_BORNE, DELAI_SANS_BORNE)
    cas(
        "le client injecte est ferme",
        T_CLIENT,
        CLIENT_INJECTE_EPARGNE,
        CLIENT_INJECTE_FERME,
    )

    # --- la session ---
    cas_session(
        "une expiration inconnue declenche un renouvellement",
        T_EXPIRATION,
        EXPIRATION_INCONNUE_NEUTRE,
        EXPIRATION_INCONNUE_RENOUVELEE,
    )
    cas_session(
        "la marge d'expiration disparait",
        T_MARGE,
        MARGE_APPLIQUEE,
        MARGE_DISPARUE,
    )

    # --- temoin negatif ---
    banc.cas(
        "commentaire reformule",
        T_429,
        lambda: banc.suivre(CLIENT).muter(COMMENTAIRE, COMMENTAIRE_REFORMULE),
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
        "vert — le client tombe sur chacune de ses vingt et une fautes, et pas "
        "sur une reformulation."
    )
    return 0


if __name__ == "__main__":
    sys.exit(principal())
