#!/usr/bin/env python3
"""Falsifie les tests du client proxy cote application (mode publication).

Le mode proxy n'avait aucun test : ni sur ce qu'il transmet, ni sur la facon
dont il traduit les refus du serveur. C'est pourtant le mode qui portera la cle
du fournisseur, cote serveur, une fois l'application publiee.

Ce banc retire chacun des garde-fous de ce client et verifie que les tests
tombent. Un garde-fou qui ne fait tomber personne ne protege rien.

Usage : python3 tools/bancs/falsifier_proxy_dart.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, MesureImpossible  # noqa: E402
from banc_flutter import BancFlutter  # noqa: E402
from environnement_flutter import executable_flutter  # noqa: E402

CLIENT = "app/lib/data/vision/proxy_provider.dart"
TESTS = "test/data/proxy_provider_test.dart"

# A mettre a jour en meme temps que le fichier de tests, jamais pour faire
# passer le banc.
TESTS_ATTENDUS = 16

# --- ancres : au niveau octet, sans fin de ligne sauf pour un retrait de ligne ---

GARDE_ENDPOINT = (
    b"    if (!isConfigured) {\n      throw const MissingCredentialFailure();\n    }\n"
)
NETTOYAGE_SLASH = b"endpoint.replaceAll(RegExp(r'/+$'), '')"
JETON = b"if (authToken != null) 'Authorization': 'Bearer $authToken',"
JETON_MORT = b"if (false) 'Authorization': 'Bearer $authToken',"
MESSAGE_413 = b"'Photo trop volumineuse',"
MESSAGE_413_AUTRE = b"'Photo refusee',"
DELAI_429 = b"retryAfterS: (map['retryAfterS'] as num?)?.toInt(),"
DELAI_429_PERDU = b"retryAfterS: null,"
SECONDE_IMAGE = (
    b"      if (request.hasSecondImage)\n"
    b"        'secondImageBase64': base64Encode(request.secondImage!),\n"
)

# --- noms des tests qui doivent tomber -------------------------------------------

T_ENDPOINT = "un point d'entree vide n'emet aucune requete"
T_SLASH = "un slash final dans le point d'entree ne double pas"
T_JETON = "aucune cle de fournisseur n'est transmise par l'application"
T_413 = "un 413 parle de la taille de la photo"
T_429 = "un 429 rapporte le delai d'attente demande"
T_SECONDE = "une seconde image ajoute ses deux champs"


def principal() -> int:
    flutter = executable_flutter()
    if flutter is None:
        print("flutter introuvable : ni dans le SDK local, ni dans le PATH.", file=sys.stderr)
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

    def garde_endpoint_retiree() -> None:
        # Sans cette garde, un point d'entree vide partirait quand meme en
        # requete, avec une URL invalide.
        banc.suivre(CLIENT).muter(GARDE_ENDPOINT, b"")

    def slash_non_nettoye() -> None:
        banc.suivre(CLIENT).muter(NETTOYAGE_SLASH, b"endpoint")

    def jeton_non_transmis() -> None:
        # Le jeton de session disparait de la requete : le serveur ne pourrait
        # plus rattacher l'analyse a un utilisateur.
        banc.suivre(CLIENT).muter(JETON, JETON_MORT)

    def message_413_perdu() -> None:
        banc.suivre(CLIENT).muter(MESSAGE_413, MESSAGE_413_AUTRE)

    def delai_429_perdu() -> None:
        banc.suivre(CLIENT).muter(DELAI_429, DELAI_429_PERDU)

    def seconde_image_non_transmise() -> None:
        # La seconde image est un des deux cliches du meme plat : la perdre
        # fausserait l'estimation sans que rien ne le signale.
        banc.suivre(CLIENT).muter(SECONDE_IMAGE, b"", occurrences=1)

    banc.cas("garde du point d'entree retiree", T_ENDPOINT, garde_endpoint_retiree)
    banc.cas("slash final non nettoye", T_SLASH, slash_non_nettoye)
    banc.cas("jeton de session non transmis", T_JETON, jeton_non_transmis)
    banc.cas("message du 413 perdu", T_413, message_413_perdu)
    banc.cas("delai du 429 perdu", T_429, delai_429_perdu)
    banc.cas("seconde image non transmise", T_SECONDE, seconde_image_non_transmise)

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

    print("vert — chaque garde-fou est detecte, et les tests repassent.")
    return 0


if __name__ == "__main__":
    sys.exit(principal())
