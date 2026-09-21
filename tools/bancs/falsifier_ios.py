#!/usr/bin/env python3
"""Falsifie `tools/check_ios.py`.

Le projet iOS ne peut pas etre compile sous Windows : ce controle est le seul
filet avant le premier passage sur un executeur macOS. Encore faut-il qu'il
detecte reellement ce qu'il pretend couvrir.

Historique : une version precedente de ce banc mutait le storyboard en cherchant
un bloc termine par `\\n`. Le fichier etait alors en CRLF — le motif ne
correspondait zero fois, `replace()` n'a rien fait, et le banc a conclu « non
detecte ». La mutation n'avait jamais eu lieu. Le harnais `banc.py` leve
desormais une exception dans ce cas, et les ancres ci-dessous ne contiennent
aucune fin de ligne.

Usage : python3 tools/bancs/falsifier_ios.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, Banc, empreinte_arbre  # noqa: E402

SCRIPT = RACINE / "tools" / "check_ios.py"
IOS = RACINE / "app" / "ios"

PBXPROJ = "app/ios/Runner.xcodeproj/project.pbxproj"
PODFILE = "app/ios/Podfile"
STORYBOARD = "app/ios/Runner/Base.lproj/LaunchScreen.storyboard"
ICONE = "app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png"

# Le temoin du cas « icone orpheline » : un PNG que le banc **fabrique**, et
# qu'il doit donc retirer. Nomme ici parce que le nettoyage de demarrage en a
# besoin — voir `principal`.
ICONE_ORPHELINE = (
    "app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-72x72@1x.png"
)

# Ancres ASCII, sans fin de ligne : c'est la lecon du banc precedent.
CIBLE_15_5 = b"IPHONEOS_DEPLOYMENT_TARGET = 15.5;"
CIBLE_14_0 = b"IPHONEOS_DEPLOYMENT_TARGET = 14.0;"
PLATFORM_15_5 = b"platform :ios, '15.5'"
PLATFORM_14_0 = b"platform :ios, '14.0'"
COULEUR_DEFINIE = b'<namedColor name="LaunchBackground">'
COULEUR_AUTRE = b'<namedColor name="LaunchBackgroundAutre">'
BUNDLE_APP = b"PRODUCT_BUNDLE_IDENTIFIER = io.github.axox934.assiette;"
BUNDLE_DIVERGENT = b"PRODUCT_BUNDLE_IDENTIFIER = io.github.axox934.assietteIos;"


def principal() -> int:
    banc = Banc(SCRIPT)

    # --- le temoin d'un passage precedent --------------------------------
    #
    # Mesure : une campagne de seize bancs a laisse `Icon-App-72x72@1x.png` dans
    # l'arbre, et ce banc a refuse de demarrer en l'accusant d'etre un defaut du
    # projet iOS — « Icon-App-72x72@1x.png present mais non declare dans
    # Contents.json ». Le projet etait annonce incomplet par un fichier que ce
    # banc avait lui-meme fabrique.
    #
    # La cause est du cote de l'environnement : sur cette machine, le garde de
    # suppression refuse parfois **sans le dire**, et `Path.unlink()` rend alors
    # la main sans lever. Le banc ne peut donc pas compter sur son propre
    # nettoyage pour la fois d'apres. Il retire son temoin au demarrage, et le
    # dit — un nettoyage silencieux masquerait le meme defaut une autre fois.
    temoin = RACINE / ICONE_ORPHELINE
    if temoin.exists():
        print(f"temoin d'un passage precedent, retire : {temoin.name}")
        banc.retirer(temoin)

    avant = empreinte_arbre(IOS)

    initial = banc.etat_initial()
    print(f"etat initial : code {initial.code}")
    if initial.code != 0:
        print(initial.texte, file=sys.stderr)
        print("le controle echoue deja avant toute mutation.", file=sys.stderr)
        return 2

    def cible_projet_abaissee() -> None:
        # Une seule des trois occurrences : deux valeurs coexistent, ce que le
        # controle doit refuser.
        banc.suivre(PBXPROJ).muter(CIBLE_15_5, CIBLE_14_0, occurrences=1)

    def cible_podfile_abaissee() -> None:
        banc.suivre(PODFILE).muter(PLATFORM_15_5, PLATFORM_14_0)

    def icone_declaree_absente() -> None:
        banc.supprimer(ICONE)

    def icone_orpheline() -> None:
        # Un PNG present mais non declare dans Contents.json n'est jamais
        # embarque par Xcode : le fichier existe pourtant.
        banc.creer(
            ICONE_ORPHELINE,
            (RACINE / ICONE).read_bytes(),
        )

    def couleur_nommee_absente() -> None:
        # La definition, pas la reference : le storyboard utiliserait une couleur
        # que rien ne definit.
        banc.suivre(STORYBOARD).muter(COULEUR_DEFINIE, COULEUR_AUTRE)

    def identifiant_divergent() -> None:
        banc.suivre(PBXPROJ).muter(BUNDLE_APP, BUNDLE_DIVERGENT)

    banc.cas("cible du projet abaissee", "[cible]", cible_projet_abaissee)
    banc.cas("cible du Podfile abaissee", "[cible]", cible_podfile_abaissee)
    banc.cas("icone declaree absente", "[icone-manquante]", icone_declaree_absente)
    banc.cas("icone orpheline", "[icone-orpheline]", icone_orpheline)
    banc.cas("couleur nommee absente", "[couleur]", couleur_nommee_absente)
    banc.cas("identifiant divergent", "[bundle]", identifiant_divergent)

    code = banc.tableau()

    apres = empreinte_arbre(IOS)
    identiques = avant == apres
    print(f"fichiers dans l'arbre iOS        : {len(apres)}")
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

    print("vert — le controle detecte les six defauts et restaure l'arbre a l'octet.")
    return 0


if __name__ == "__main__":
    sys.exit(principal())
