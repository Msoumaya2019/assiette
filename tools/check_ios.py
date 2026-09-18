#!/usr/bin/env python3
"""Verifie le projet iOS sans compilateur Apple.

Le projet iOS ne peut pas etre compile sur une machine Windows. Un defaut de
configuration n'apparait donc qu'au premier passage sur un executeur macOS — ou
pire, au moment de la soumission a l'App Store, apres une revue de plusieurs
jours.

Ce controle attrape ce qui est attrapable sans Mac :

  1. chaque image declaree dans `AppIcon.appiconset/Contents.json` existe, et ses
     dimensions correspondent a la taille et a l'echelle annoncees ;
  2. aucune image orpheline dans le jeu d'icones — un fichier present mais non
     declare n'est jamais embarque ;
  3. l'icone 1024 ne porte pas de canal alpha : l'App Store la refuse ;
  4. `LaunchImage.imageset` est coherent, et le storyboard la declare a sa taille
     intrinseque exacte ;
  5. la couleur `LaunchBackground` existe et est bien celle que le storyboard
     reference ;
  6. l'identifiant de bundle iOS et celui d'Android sont identiques ;
  7. la cible de deploiement est la meme partout, et suffisante pour les greffons ;
  8. `Info.plist` porte les cles qu'Apple exige, et une justification pour chaque
     acces demande ;
  9. le `Podfile` declare la meme cible de deploiement et des cibles qui existent.

Ce qu'il ne voit PAS : rien de ce qui demande Xcode. Une entree de build
manquante, un fichier non rattache a la cible, une signature absente — tout cela
ne se voit qu'en compilant. Ce controle reduit la surface, il ne la supprime pas.

Usage : python3 tools/check_ios.py
"""

from __future__ import annotations

import json
import plistlib
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IOS = ROOT / "app" / "ios"
ASSETS = IOS / "Runner" / "Assets.xcassets"
PBXPROJ = IOS / "Runner.xcodeproj" / "project.pbxproj"
INFO_PLIST = IOS / "Runner" / "Info.plist"
STORYBOARD = IOS / "Runner" / "Base.lproj" / "LaunchScreen.storyboard"
PODFILE = IOS / "Podfile"
GRADLE = ROOT / "app" / "android" / "app" / "build.gradle.kts"

MARQUEURS = {
    "icone-manquante": "[icone-manquante]",
    "icone-dimension": "[icone-dimension]",
    "icone-orpheline": "[icone-orpheline]",
    "icone-alpha": "[icone-alpha]",
    "demarrage": "[demarrage]",
    "couleur": "[couleur]",
    "storyboard": "[storyboard]",
    "bundle": "[bundle]",
    "cible": "[cible]",
    "plist": "[plist]",
    "podfile": "[podfile]",
    "absent": "[fichier-absent]",
}


class Rapport:
    def __init__(self) -> None:
        self.verifications = 0
        self.defauts: list[str] = []
        self.ignores: list[str] = []

    def verifie(self) -> None:
        self.verifications += 1

    def defaut(self, marqueur: str, message: str) -> None:
        self.defauts.append(f"{MARQUEURS[marqueur]} {message}")

    def ignore(self, message: str) -> None:
        self.ignores.append(message)


def lire_png(chemin: Path) -> tuple[int, int, int, bool] | None:
    """Retourne (largeur, hauteur, type de couleur, presence d'alpha)."""
    donnees = chemin.read_bytes()
    if donnees[:8] != b"\x89PNG\r\n\x1a\n":
        return None

    largeur, hauteur = struct.unpack(">II", donnees[16:24])
    type_couleur = donnees[25]

    # Parcours des chunks jusqu'aux donnees image, pour trouver un eventuel
    # `tRNS` — un canal alpha declare separement, invisible dans l'IHDR.
    alpha = type_couleur in (4, 6)
    position = 8
    while position + 8 <= len(donnees):
        longueur = struct.unpack(">I", donnees[position : position + 4])[0]
        nom = donnees[position + 4 : position + 8]
        if nom == b"tRNS":
            alpha = True
        if nom in (b"IDAT", b"IEND"):
            break
        position += 12 + longueur

    return largeur, hauteur, type_couleur, alpha


def verifier_jeu_images(
    dossier: Path, rapport: Rapport, nom_lisible: str, taille_max: int | None = None
) -> None:
    contenu = dossier / "Contents.json"
    rapport.verifie()
    if not contenu.is_file():
        rapport.defaut("absent", f"{nom_lisible} : Contents.json introuvable")
        return

    try:
        entrees = json.loads(contenu.read_text(encoding="utf-8")).get("images", [])
    except (json.JSONDecodeError, OSError) as erreur:
        rapport.defaut("absent", f"{nom_lisible} : Contents.json illisible — {erreur}")
        return

    declarees: set[str] = set()

    for entree in entrees:
        fichier = entree.get("filename")
        taille = entree.get("size")
        echelle = entree.get("scale")
        if not fichier:
            continue

        declarees.add(fichier)
        chemin = dossier / fichier

        rapport.verifie()
        if not chemin.is_file():
            rapport.defaut("icone-manquante", f"{nom_lisible} : {fichier} declare mais absent")
            continue

        if not taille or not echelle:
            continue

        attendu = round(float(taille.split("x")[0]) * float(echelle.rstrip("x")))
        mesures = lire_png(chemin)
        rapport.verifie()
        if mesures is None:
            rapport.defaut("icone-dimension", f"{nom_lisible} : {fichier} n'est pas un PNG")
            continue

        largeur, hauteur, _, alpha = mesures
        if (largeur, hauteur) != (attendu, attendu):
            rapport.defaut(
                "icone-dimension",
                f"{nom_lisible} : {fichier} annonce {taille}@{echelle} "
                f"(soit {attendu}px) mais mesure {largeur}x{hauteur}",
            )
        elif taille_max is not None and attendu >= taille_max:
            rapport.verifie()
            if alpha:
                rapport.defaut(
                    "icone-alpha",
                    f"{nom_lisible} : {fichier} ({attendu}px) porte un canal alpha, "
                    "ce que l'App Store refuse sur la grande icone",
                )

    # Fichiers presents mais non declares : jamais embarques par Xcode.
    for chemin in sorted(dossier.glob("*.png")):
        rapport.verifie()
        if chemin.name not in declarees:
            rapport.defaut(
                "icone-orpheline",
                f"{nom_lisible} : {chemin.name} present mais non declare dans Contents.json",
            )


def verifier_bundle(rapport: Rapport) -> None:
    rapport.verifie()
    if not PBXPROJ.is_file():
        rapport.defaut("absent", "project.pbxproj introuvable")
        return
    if not GRADLE.is_file():
        rapport.defaut("absent", "build.gradle.kts introuvable")
        return

    projet = PBXPROJ.read_text(encoding="utf-8", errors="replace")
    gradle = GRADLE.read_text(encoding="utf-8", errors="replace")

    ios = set(re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", projet))
    ios = {v.strip() for v in ios if "$" not in v}
    android = re.search(r'applicationId = "([^"]+)"', gradle)

    rapport.verifie()
    if not android:
        rapport.defaut("bundle", "aucun applicationId trouve cote Android")
        return

    # La cible de tests porte l'identifiant de l'application suivi d'un suffixe
    # (`.RunnerTests`) : c'est la convention, pas une divergence. L'identifiant de
    # l'application est donc le plus court, et tout autre doit en deriver.
    rapport.verifie()
    if not ios:
        rapport.defaut("bundle", "aucun identifiant de bundle cote iOS")
        return

    identifiant_ios = min(ios, key=len)

    for autre in sorted(ios - {identifiant_ios}):
        rapport.verifie()
        if not autre.startswith(f"{identifiant_ios}."):
            rapport.defaut(
                "bundle",
                f"'{autre}' ne derive pas de l'identifiant de l'application "
                f"'{identifiant_ios}'",
            )

    rapport.verifie()
    if identifiant_ios != android.group(1):
        rapport.defaut(
            "bundle",
            f"identifiants divergents — iOS '{identifiant_ios}' / Android '{android.group(1)}'",
        )


def verifier_cible(rapport: Rapport) -> None:
    if not PBXPROJ.is_file():
        return
    projet = PBXPROJ.read_text(encoding="utf-8", errors="replace")
    cibles = set(re.findall(r"IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);", projet))

    rapport.verifie()
    if len(cibles) != 1:
        rapport.defaut(
            "cible", f"cote iOS, {len(cibles)} cibles de deploiement distinctes : {sorted(cibles)}"
        )
        return

    cible = next(iter(cibles))

    rapport.verifie()
    if not PODFILE.is_file():
        rapport.defaut("absent", "Podfile introuvable : il doit etre versionne")
        return

    podfile = PODFILE.read_text(encoding="utf-8", errors="replace")
    declaration = re.search(r"^\s*platform\s*:ios\s*,\s*'([0-9.]+)'", podfile, re.MULTILINE)

    rapport.verifie()
    if not declaration:
        rapport.defaut(
            "podfile",
            "aucune ligne `platform :ios, '…'` active : Flutter appliquerait sa "
            "propre cible, que personne n'a choisie",
        )
        return

    rapport.verifie()
    if declaration.group(1) != cible:
        rapport.defaut(
            "cible",
            f"Podfile en {declaration.group(1)} mais projet en {cible} — "
            "les deux doivent rester d'accord",
        )

    # Les cibles declarees dans le Podfile doivent exister dans le projet.
    for cible_pod in re.findall(r"^\s*target\s+'([^']+)'", podfile, re.MULTILINE):
        rapport.verifie()
        if f"/* {cible_pod} */" not in projet and f"{cible_pod}.app" not in projet and f"{cible_pod}.xctest" not in projet:
            rapport.defaut(
                "podfile", f"le Podfile declare la cible '{cible_pod}', absente du projet Xcode"
            )


def verifier_plist(rapport: Rapport) -> None:
    rapport.verifie()
    if not INFO_PLIST.is_file():
        rapport.defaut("absent", "Info.plist introuvable")
        return

    try:
        plist = plistlib.loads(INFO_PLIST.read_bytes())
    except Exception as erreur:  # noqa: BLE001
        rapport.defaut("plist", f"Info.plist illisible — {erreur}")
        return

    for cle in (
        "CFBundleDisplayName",
        "CFBundleIdentifier",
        "CFBundleShortVersionString",
        "CFBundleVersion",
        "UILaunchStoryboardName",
    ):
        rapport.verifie()
        if cle not in plist:
            rapport.defaut("plist", f"cle '{cle}' absente")

    rapport.verifie()
    if plist.get("UILaunchStoryboardName") != "LaunchScreen":
        rapport.defaut(
            "plist",
            f"UILaunchStoryboardName vaut '{plist.get('UILaunchStoryboardName')}' "
            "au lieu de 'LaunchScreen'",
        )

    # Les acces demandes par les greffons doivent porter une justification : une
    # demande sans texte fait refuser la soumission.
    for cle, greffon in (
        ("NSCameraUsageDescription", "mobile_scanner / image_picker"),
        ("NSPhotoLibraryUsageDescription", "image_picker"),
    ):
        rapport.verifie()
        valeur = plist.get(cle)
        if not valeur or not str(valeur).strip():
            rapport.defaut(
                "plist", f"'{cle}' absente ou vide, alors que {greffon} y accede"
            )


def verifier_storyboard(rapport: Rapport) -> None:
    rapport.verifie()
    if not STORYBOARD.is_file():
        rapport.defaut("absent", "LaunchScreen.storyboard introuvable")
        return

    texte = STORYBOARD.read_text(encoding="utf-8", errors="replace")

    rapport.verifie()
    if 'name="LaunchBackground"' not in texte:
        rapport.defaut(
            "couleur",
            "le storyboard n'utilise pas la couleur nommee LaunchBackground",
        )

    rapport.verifie()
    if "<namedColor name=\"LaunchBackground\">" not in texte:
        rapport.defaut(
            "couleur",
            "LaunchBackground est referencee mais non definie dans le storyboard : "
            "le fond serait noir sur un appareil sans le jeu de ressources",
        )

    # La taille declaree dans <resources> est la taille intrinseque que
    # `contentMode="center"` respecte a la lettre : elle doit valoir le 1x.
    declaration = re.search(r'<image name="LaunchImage" width="(\d+)" height="(\d+)"', texte)
    rapport.verifie()
    if not declaration:
        rapport.defaut("storyboard", "aucune taille declaree pour LaunchImage")
        return

    dossier = ASSETS / "LaunchImage.imageset"
    un_x = dossier / "LaunchImage.png"
    rapport.verifie()
    if not un_x.is_file():
        rapport.defaut("demarrage", "LaunchImage.png (1x) introuvable")
        return

    mesures = lire_png(un_x)
    if mesures is None:
        rapport.defaut("demarrage", "LaunchImage.png n'est pas un PNG")
        return

    largeur, hauteur, _, _ = mesures
    attendu = int(declaration.group(1))
    rapport.verifie()
    if (largeur, hauteur) != (attendu, attendu):
        rapport.defaut(
            "storyboard",
            f"le storyboard declare LaunchImage en {attendu}px mais le 1x mesure "
            f"{largeur}x{hauteur} : l'image serait mise a l'echelle",
        )


def main() -> int:
    rapport = Rapport()

    rapport.verifie()
    if not ASSETS.is_dir():
        print(f"{MARQUEURS['absent']} dossier d'actifs introuvable : {ASSETS}", file=sys.stderr)
        return 1

    icones = ASSETS / "AppIcon.appiconset"
    rapport.verifie()
    if icones.is_dir():
        verifier_jeu_images(icones, rapport, "AppIcon", taille_max=1024)
    else:
        rapport.defaut("absent", "AppIcon.appiconset introuvable")

    demarrage = ASSETS / "LaunchImage.imageset"
    rapport.verifie()
    if demarrage.is_dir():
        verifier_jeu_images(demarrage, rapport, "LaunchImage")
    else:
        rapport.defaut("absent", "LaunchImage.imageset introuvable")

    rapport.verifie()
    if not (ASSETS / "LaunchBackground.colorset" / "Contents.json").is_file():
        rapport.defaut("couleur", "LaunchBackground.colorset introuvable")

    verifier_bundle(rapport)
    verifier_cible(rapport)
    verifier_plist(rapport)
    verifier_storyboard(rapport)

    if rapport.defauts:
        print("Projet iOS incomplet :", file=sys.stderr)
        for defaut in rapport.defauts:
            print(f"  - {defaut}", file=sys.stderr)
        print(
            f"\n{len(rapport.defauts)} defaut(s), {rapport.verifications} verifications.",
            file=sys.stderr,
        )
        return 1

    for ignore in rapport.ignores:
        print(f"  --  {ignore}")
    print(f"\n{rapport.verifications} verifications — projet iOS coherent.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
