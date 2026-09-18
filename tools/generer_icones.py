#!/usr/bin/env python3
"""Genere les icones, l'icone adaptative et l'ecran de demarrage de l'application.

Le motif reprend la palette de lib/core/theme.dart : terracotta pour l'action,
ambre pour les glucides — la donnee que l'application met en avant — et creme
pour les surfaces. C'est une assiette vue de dessus, avec une portion au centre.

Trois declinaisons du meme motif :
  - icone applicative : assiette creme et portion ambre sur fond terracotta ;
  - icone adaptative Android : motif reduit au cercle sur de 66 dp, sur un
    canevas de 108 dp (le systeme applique ensuite son propre masque) ;
  - ecran de demarrage : motif sans fond, pose sur une couleur resolue par le
    systeme en clair ou en sombre.

Le dessin est fait 4 fois plus grand que la cible puis reduit : Pillow
n'anticrennele pas les ellipses, la reduction s'en charge.

Les tailles iOS ne sont pas ecrites en dur : elles sont lues dans le
Contents.json du catalogue d'images, pour qu'un ajout cote Xcode ne puisse pas
diverger du generateur.

Usage :
    python tools/generer_icones.py --app app
"""

from __future__ import annotations

import argparse
import json
import os
import sys

from PIL import Image, ImageDraw

# Facteur de surechantillonnage, reduit ensuite par LANCZOS.
SS = 4

TERRACOTTA_HAUT = (234, 107, 66)
TERRACOTTA_BAS = (203, 78, 40)
TERRACOTTA = (224, 96, 58)
CREME = (251, 247, 243)
AMBRE = (232, 155, 46)

# Densites Android : nom du dossier -> facteur par rapport a mdpi (1 dp = 1 px).
DENSITES = {
    "mdpi": 1,
    "hdpi": 1.5,
    "xhdpi": 2,
    "xxhdpi": 3,
    "xxxhdpi": 4,
}

# Taille de l'icone classique, en dp.
ICONE_DP = 48
# Canevas de l'icone adaptative et diametre du cercle sur, en dp.
ADAPTATIVE_DP = 108
CERCLE_SUR_DP = 66
# Logo de l'ecran de demarrage, en dp.
DEMARRAGE_DP = 120


def fond_degrade(cote: int) -> Image.Image:
    """Fond terracotta en degrade vertical, du plus clair en haut."""
    bande = Image.new("RGB", (1, cote))
    for y in range(cote):
        t = y / max(cote - 1, 1)
        bande.putpixel(
            (0, y),
            tuple(
                round(TERRACOTTA_HAUT[i] + (TERRACOTTA_BAS[i] - TERRACOTTA_HAUT[i]) * t)
                for i in range(3)
            ),
        )
    return bande.resize((cote, cote), Image.NEAREST).convert("RGBA")


def _disque(dessin: ImageDraw.ImageDraw, cx: float, cy: float, rayon: float, couleur):
    dessin.ellipse([cx - rayon, cy - rayon, cx + rayon, cy + rayon], fill=couleur)


def _anneau(
    dessin: ImageDraw.ImageDraw,
    cx: float,
    cy: float,
    rayon: float,
    couleur,
    largeur: float,
):
    dessin.ellipse(
        [cx - rayon, cy - rayon, cx + rayon, cy + rayon],
        outline=couleur,
        width=max(1, round(largeur)),
    )


def motif_assiette(cote: int, rayon: float) -> Image.Image:
    """Assiette creme et portion ambre, sur fond transparent.

    `rayon` est le rayon exterieur du motif entier, en pixels. Tout le reste est
    proportionnel : c'est ce qui permet de reutiliser le meme dessin pour une
    icone de 48 px et pour un canevas adaptatif de 432 px.
    """
    image = Image.new("RGBA", (cote, cote), (0, 0, 0, 0))
    dessin = ImageDraw.Draw(image)
    cx = cy = cote / 2

    # Liseré exterieur : evoque le bord releve d'une assiette. Semi-transparent
    # pour rester discret quel que soit le fond.
    _anneau(dessin, cx, cy, 0.975 * rayon, (*CREME, 110), 0.05 * rayon)
    # L'assiette elle-meme.
    _disque(dessin, cx, cy, 0.85 * rayon, CREME)
    # La portion. C'est la seule tache coloree, donc la premiere chose que
    # l'oeil attrape — comme les glucides dans l'application.
    _disque(dessin, cx, cy, 0.44 * rayon, AMBRE)
    return image


def motif_contour(cote: int, rayon: float) -> Image.Image:
    """Meme assiette, mais dessinee pour se poser sur un fond clair ou sombre.

    Sur fond creme, une assiette creme serait invisible : le bord de l'assiette
    est donc terracotta. C'est le meme dessin que l'icone, avec un bord franc
    au lieu du liseré discret — l'ecran de demarrage annonce ainsi exactement
    l'icone que l'utilisateur vient de toucher.
    """
    image = Image.new("RGBA", (cote, cote), (0, 0, 0, 0))
    dessin = ImageDraw.Draw(image)
    cx = cy = cote / 2

    # Le bord affleure exactement le rayon exterieur du motif, et son bord
    # interieur touche l'assiette : aucune couture visible.
    _anneau(dessin, cx, cy, 0.93 * rayon, TERRACOTTA, 0.14 * rayon)
    _disque(dessin, cx, cy, 0.86 * rayon, CREME)
    _disque(dessin, cx, cy, 0.44 * rayon, AMBRE)
    return image


def motif_monochrome(cote: int, rayon: float) -> Image.Image:
    """Silhouette pour les icones a theme (Android 13+).

    Le systeme n'utilise que le canal alpha et applique sa propre teinte : les
    formes doivent donc rester distinctes, un anneau et un disque separes.
    """
    image = Image.new("RGBA", (cote, cote), (0, 0, 0, 0))
    dessin = ImageDraw.Draw(image)
    cx = cy = cote / 2
    opaque = (255, 255, 255, 255)

    _anneau(dessin, cx, cy, 0.90 * rayon, opaque, 0.16 * rayon)
    _disque(dessin, cx, cy, 0.44 * rayon, opaque)
    return image


def reduire(image: Image.Image, cote: int, alpha: bool = True) -> Image.Image:
    """Reduit a la taille cible. Sans alpha pour les icones iOS : l'App Store
    refuse un canal alpha sur l'icone 1024."""
    petite = image.resize((cote, cote), Image.LANCZOS)
    return petite if alpha else petite.convert("RGB")


def ecrire(image: Image.Image, chemin: str) -> None:
    os.makedirs(os.path.dirname(chemin), exist_ok=True)
    image.save(chemin, "PNG", optimize=True)


def generer_android(app: str, journal: list[str]) -> None:
    res = os.path.join(app, "android", "app", "src", "main", "res")

    for densite, facteur in DENSITES.items():
        dossier = os.path.join(res, f"mipmap-{densite}")

        # Icone classique : motif sur fond, marges genereuses pour ne pas etre
        # rognee par les lanceurs qui appliquent un masque.
        cote = round(ICONE_DP * facteur)
        grand = fond_degrade(cote * SS)
        assiette = motif_assiette(cote * SS, 0.33 * cote * SS)
        grand.alpha_composite(assiette)
        ecrire(reduire(grand, cote, alpha=False), os.path.join(dossier, "ic_launcher.png"))

        # Icones adaptatives : canevas de 108 dp, motif dans le cercle sur de
        # 66 dp. 0.30 donne un motif de 64.8 dp, qui tient dans le cercle sur
        # tout en remplissant mieux que le minimum recommande de 60 dp.
        cote_adapt = round(ADAPTATIVE_DP * facteur)
        ecrire(
            reduire(motif_assiette(cote_adapt * SS, 0.30 * cote_adapt * SS), cote_adapt),
            os.path.join(dossier, "ic_launcher_foreground.png"),
        )
        ecrire(
            reduire(
                motif_monochrome(cote_adapt * SS, 0.30 * cote_adapt * SS), cote_adapt
            ),
            os.path.join(dossier, "ic_launcher_monochrome.png"),
        )

        # Logo de l'ecran de demarrage.
        cote_splash = round(DEMARRAGE_DP * facteur)
        ecrire(
            reduire(
                motif_contour(cote_splash * SS, 0.5 * cote_splash * SS), cote_splash
            ),
            os.path.join(res, f"drawable-{densite}", "splash_logo.png"),
        )
        journal.append(f"android {densite} : icone {cote} px, adaptative {cote_adapt} px")

    # Descripteur de l'icone adaptative (API 26+). Sans lui, Android 8 et
    # suivants afficheraient l'icone classique en la rognant dans un carre.
    anydpi = os.path.join(res, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    with open(os.path.join(anydpi, "ic_launcher.xml"), "w", encoding="utf-8", newline="\n") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<!-- Icone adaptative : Android applique son propre masque sur le\n"
            "     canevas de 108 dp, le motif reste dans le cercle sur de 66 dp. -->\n"
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@drawable/ic_launcher_background" />\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
            '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
            "</adaptive-icon>\n"
        )

    drawable = os.path.join(res, "drawable")
    os.makedirs(drawable, exist_ok=True)
    with open(
        os.path.join(drawable, "ic_launcher_background.xml"), "w", encoding="utf-8", newline="\n"
    ) as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<!-- Fond de l'icone adaptative : meme degrade que l'icone classique. -->\n"
            '<shape xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    android:shape="rectangle">\n'
            '    <gradient\n'
            '        android:angle="270"\n'
            '        android:startColor="#EA6B42"\n'
            '        android:endColor="#CB4E28"\n'
            '        android:type="linear" />\n'
            "</shape>\n"
        )
    journal.append("android : icone adaptative + silhouette monochrome")


def generer_ios(app: str, journal: list[str]) -> None:
    catalogue = os.path.join(app, "ios", "Runner", "Assets.xcassets")

    # Les tailles sont lues dans le descripteur, pas ecrites en dur.
    appicon = os.path.join(catalogue, "AppIcon.appiconset")
    with open(os.path.join(appicon, "Contents.json"), encoding="utf-8") as f:
        descripteur = json.load(f)

    vues: dict[str, int] = {}
    for entree in descripteur["images"]:
        nom = entree.get("filename")
        if not nom:
            continue
        cote, _, echelle = entree["size"].partition("x")
        px = round(float(cote) * int(entree["scale"].rstrip("x")))
        vues[nom] = px

    for nom, px in sorted(vues.items(), key=lambda item: item[1]):
        grand = fond_degrade(px * SS)
        grand.alpha_composite(motif_assiette(px * SS, 0.33 * px * SS))
        # Pas de canal alpha : exigence de l'App Store sur l'icone 1024.
        ecrire(reduire(grand, px, alpha=False), os.path.join(appicon, nom))
    journal.append(f"ios : {len(vues)} icones, de {min(vues.values())} a {max(vues.values())} px")

    # Logo de l'ecran de demarrage. Le storyboard le pose a sa taille
    # intrinseque : le 1x doit donc valoir exactement DEMARRAGE_DP points.
    lancement = os.path.join(catalogue, "LaunchImage.imageset")
    for echelle, nom in ((1, "LaunchImage.png"), (2, "LaunchImage@2x.png"), (3, "LaunchImage@3x.png")):
        px = DEMARRAGE_DP * echelle
        ecrire(
            reduire(motif_contour(px * SS, 0.5 * px * SS), px),
            os.path.join(lancement, nom),
        )
    journal.append(f"ios : logo de demarrage {DEMARRAGE_DP} pt")

    # Couleur de fond de l'ecran de demarrage, avec sa variante sombre : un
    # storyboard ne sait pas lire le theme de l'application.
    couleurs = os.path.join(catalogue, "LaunchBackground.colorset")
    os.makedirs(couleurs, exist_ok=True)

    def composantes(rgb):
        return {
            "alpha": "1.000",
            "red": f"0x{rgb[0]:02X}",
            "green": f"0x{rgb[1]:02X}",
            "blue": f"0x{rgb[2]:02X}",
        }

    with open(os.path.join(couleurs, "Contents.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(
            {
                "colors": [
                    {
                        "color": {"color-space": "srgb", "components": composantes(CREME)},
                        "idiom": "universal",
                    },
                    {
                        "appearances": [{"appearance": "luminosity", "value": "dark"}],
                        "color": {
                            "color-space": "srgb",
                            "components": composantes((22, 19, 15)),
                        },
                        "idiom": "universal",
                    },
                ],
                "info": {"author": "xcode", "version": 1},
            },
            f,
            indent=2,
        )
        f.write("\n")
    journal.append("ios : couleur de fond clair/sombre")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", default="app", help="dossier de l'application Flutter")
    args = parser.parse_args()

    if not os.path.isdir(args.app):
        print(f"dossier introuvable : {args.app}", file=sys.stderr)
        return 1

    journal: list[str] = []
    generer_android(args.app, journal)
    generer_ios(args.app, journal)
    for ligne in journal:
        print(f"  {ligne}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
