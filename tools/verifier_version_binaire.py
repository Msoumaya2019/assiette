#!/usr/bin/env python3
"""Lit la version qu'un APK ou un IPA **declare**, et la compare a son nom.

Pourquoi ce controle existe
---------------------------
`verifier_version_build.py` verifie la valeur **passee** a Flutter. Il ne peut pas
verifier la valeur **inscrite** dans le binaire : entre les deux, il y a
`flutter build`, Gradle, Xcode, et un `Info.plist`.

C'est exactement ce qui est passe inapercu. Le tag `v0.1.1` a produit une IPA
nommee `Assiette-v0.1.1-non-signee.ipa` dont l'`Info.plist` declarait `0.1.0` :
le nom venait du tag, la version venait du pubspec. La chaine de controle etait
verte, et le fichier livrait une information fausse sur lui-meme.

Ce controle lit donc le binaire, et confronte les deux :

  - le nom du fichier doit contenir la version declaree ;
  - le nom doit contenir le numero de compilation declare.

Un fichier dont le nom et le contenu se contredisent ne peut pas etre installe en
confiance : c'est la seule chose qu'une personne a sous les yeux avant de choisir
quoi installer.

Usage :
    python3 tools/verifier_version_binaire.py chemin/vers/fichier.apk
    python3 tools/verifier_version_binaire.py chemin/vers/fichier.ipa
"""

from __future__ import annotations

import plistlib
import re
import subprocess
import sys
import zipfile
from pathlib import Path

# `aapt2` vient avec les outils de compilation Android. On cherche la version la
# plus recente installee, sans dependre d'un numero fixe : les outils de
# compilation evoluent avec les versions d'Android visees.
DOSSIERS_BUILD_TOOLS = [
    Path.home() / "AppData" / "Local" / "Android" / "Sdk" / "build-tools",
    Path("/usr/local/lib/android/sdk/build-tools"),
]


def trouver_aapt2() -> Path | None:
    for dossier in DOSSIERS_BUILD_TOOLS:
        if not dossier.is_dir():
            continue
        candidats = sorted(
            (chemin / "aapt2.exe" for chemin in dossier.iterdir()),
            key=lambda chemin: chemin.parent.name,
        )
        candidats += sorted(
            (chemin / "aapt2" for chemin in dossier.iterdir()),
            key=lambda chemin: chemin.parent.name,
        )
        for candidat in reversed(candidats):
            if candidat.is_file():
                return candidat
    return None


def lire_apk(chemin: Path) -> tuple[str, str] | None:
    """Rend (versionName, versionCode) tel que declare dans l'APK."""
    aapt2 = trouver_aapt2()
    if aapt2 is None:
        print(
            "aapt2 introuvable : impossible de lire l'APK.\n"
            "Il vient avec les outils de compilation Android "
            "(SDK Manager > Android SDK Build-Tools).",
            file=sys.stderr,
        )
        return None

    resultat = subprocess.run(
        [str(aapt2), "dump", "badging", str(chemin)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if resultat.returncode != 0:
        print(f"aapt2 a refuse le fichier : {resultat.stderr.strip()}", file=sys.stderr)
        return None

    premiere = resultat.stdout.splitlines()[0] if resultat.stdout else ""
    version = re.search(r"versionName='([^']*)'", premiere)
    code = re.search(r"versionCode='([^']*)'", premiere)
    if version is None or code is None:
        print(f"ligne 'package' illisible : {premiere!r}", file=sys.stderr)
        return None
    return version.group(1), code.group(1)


def lire_ipa(chemin: Path) -> tuple[str, str] | None:
    """Rend (CFBundleShortVersionString, CFBundleVersion) tel que declare dans l'IPA."""
    with zipfile.ZipFile(chemin) as archive:
        plists = [
            nom
            for nom in archive.namelist()
            if nom.startswith("Payload/")
            and nom.count("/") == 2
            and nom.endswith(".app/Info.plist")
        ]
        if not plists:
            print("aucun `Payload/*.app/Info.plist` dans l'archive.", file=sys.stderr)
            return None
        with archive.open(plists[0]) as flux:
            # `plistlib` lit le format binaire comme le format XML : Xcode
            # produit du binaire, mais un outil tiers peut produire de l'XML.
            infos = plistlib.load(flux)

    version = infos.get("CFBundleShortVersionString")
    build = infos.get("CFBundleVersion")
    if not isinstance(version, str) or not isinstance(build, str):
        print(
            f"versions absentes ou mal formees dans l'Info.plist : "
            f"{version!r}, {build!r}",
            file=sys.stderr,
        )
        return None
    return version, str(build)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    chemin = Path(sys.argv[1])
    if not chemin.is_file():
        print(f"introuvable : {chemin}", file=sys.stderr)
        return 2

    suffixe = chemin.suffix.lower()
    if suffixe == ".apk":
        lues = lire_apk(chemin)
    elif suffixe == ".ipa":
        lues = lire_ipa(chemin)
    else:
        print(f"format non reconnu : {suffixe} (attendu .apk ou .ipa)", file=sys.stderr)
        return 2

    if lues is None:
        return 1

    version, compilation = lues
    nom = chemin.name

    print(f"fichier            : {nom}")
    print(f"taille             : {chemin.stat().st_size} octets")
    print(f"version declaree   : {version}")
    print(f"compilation declaree : {compilation}")

    # Le nom doit contenir les deux valeurs. On ne cherche pas une forme exacte
    # (`0.1.0+1`, `0.1.0-1`) : les flux les assembleront differemment, et exiger
    # une forme precise ferait echouer ce controle sur un simple renommage.
    def present(valeur: str) -> bool:
        return re.search(rf"(?<![0-9.]){re.escape(valeur)}(?![0-9.])", nom) is not None

    manquants = []
    if not present(version):
        manquants.append(f"la version declaree {version!r}")
    if not present(compilation):
        manquants.append(f"la compilation declaree {compilation!r}")

    print()
    if manquants:
        print("NOM ET CONTENU DIVERGENT", file=sys.stderr)
        for manquant in manquants:
            print(f"  le nom ne contient pas {manquant}", file=sys.stderr)
        print(
            "\nQui installe ce fichier lit le nom pour decider. Un nom qui "
            "contredit le contenu est une information fausse livree avec le "
            "binaire.",
            file=sys.stderr,
        )
        return 1

    print(f"conforme — le nom annonce ce que le binaire declare.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
