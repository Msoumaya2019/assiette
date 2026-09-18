#!/usr/bin/env python3
"""Falsifie `tools/check_adresses_du_depot.py`.

Le controle existe parce que l'application annoncait `axox934/assiette`, un
depot inexistant : lien d'assistance en 404, et identifiant Open Food Facts
incapable d'identifier l'auteur. Ce banc restaure ce defaut exact et verifie que
le controle tombe.

Usage : python3 tools/bancs/falsifier_adresses.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, Banc, empreinte_arbre  # noqa: E402

SCRIPT = RACINE / "tools" / "check_adresses_du_depot.py"
CONFIG = "app/lib/core/config.dart"

DEPOT = b"https://github.com/Msoumaya2019/assiette"
COMPTE = b"https://github.com/Msoumaya2019"
DEPOT_MORT = b"https://github.com/axox934/assiette"
COMPTE_MORT = b"https://github.com/axox934"
EXTERNE = b"https://github.com/flutter/flutter"


def principal() -> int:
    banc = Banc(SCRIPT)

    avant = empreinte_arbre(RACINE / "app" / "lib")

    initial = banc.etat_initial()
    print(f"etat initial : code {initial.code}")
    if initial.code != 0:
        print(initial.texte, file=sys.stderr)
        print("le controle echoue deja avant toute mutation.", file=sys.stderr)
        return 2

    def lien_assistance_mort() -> None:
        # Le defaut d'origine, reproduit a l'identique.
        banc.suivre(CONFIG).muter(DEPOT + b"/issues", DEPOT_MORT + b"/issues")

    def user_agent_mort() -> None:
        banc.suivre(CONFIG).muter(
            b"Assiette/0.1 (" + DEPOT + b")", b"Assiette/0.1 (" + COMPTE_MORT + b")"
        )

    def _ajouter_ligne(contenu: bytes) -> None:
        """Ajoute une constante a `config.dart`, sans toucher au reste."""
        fichier = banc.suivre(CONFIG)
        fichier.ecrire(fichier.origine + b"\n" + contenu + b"\n")

    def compte_divergent() -> None:
        # Adresse reduite au compte, sans chemin de depot : elle doit designer le
        # proprietaire du depot, pas un homonyme.
        _ajouter_ligne(b"const String auteur = '" + COMPTE_MORT + b"';")

    def depot_externe_cite() -> None:
        # Temoin negatif : citer un autre depot que le sien est legitime — un
        # paquet, un outil. Le controle ne doit pas le signaler.
        _ajouter_ligne(b"const String outil = '" + EXTERNE + b"';")

    banc.cas("lien d'assistance mort", "[adresse]", lien_assistance_mort)
    banc.cas("user-agent Open Food Facts mort", "[adresse]", user_agent_mort)
    banc.cas("compte divergent", "[adresse]", compte_divergent)
    banc.cas("depot externe cite (legitime)", "[adresse]", depot_externe_cite, attendu=False)

    code = banc.tableau()

    apres = empreinte_arbre(RACINE / "app" / "lib")
    identiques = avant == apres
    print(f"fichiers dans app/lib/           : {len(apres)}")
    print(f"restauration a l'octet           : {'conforme' if identiques else 'DIVERGENTE'}")

    if not identiques:
        for chemin in sorted(set(avant) ^ set(apres)):
            print(f"  - {chemin}", file=sys.stderr)
        return 1

    if code != 0:
        return code

    final = banc.executer()
    print(f"\netat final : code {final.code}")
    if final.code != 0:
        print(final.texte, file=sys.stderr)
        return 1

    print("vert — le controle detecte les adresses mortes et laisse passer les citations.")
    return 0


if __name__ == "__main__":
    sys.exit(principal())
