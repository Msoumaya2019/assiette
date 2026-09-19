#!/usr/bin/env python3
"""Depose la cle de signature Android dans les secrets GitHub, sans l'afficher.

Pourquoi ce script existe
-------------------------
Les quatre valeurs de signature doivent finir dans les secrets du depot pour que
la CI signe les artefacts en release. Les recopier a la main dans l'interface
GitHub marche, mais suppose de les **lire** : ouvrir le fichier, copier, coller.
Aucune de ces etapes n'est verifiable, et une valeur tronquee ne se voit qu'au
moment ou la compilation signe un paquet que le Play Store refuse.

Ici, `gh` lit chaque valeur **depuis son fichier**, par l'entree standard. La
valeur ne traverse ni la ligne de commande — lisible par tout processus de la
machine —, ni la sortie du script, ni une conversation.

Ce que le script verifie
------------------------
  1. Les quatre fichiers existent, et le dossier n'est pas dans le depot.
  2. Le magasin de cles s'ouvre reellement avec le mot de passe enregistre.
     Sans cette etape, on deposerait dans GitHub un couple dont on ne sait pas
     s'il fonctionne, et l'echec n'apparaitrait qu'a la compilation.
  3. Les quatre secrets sont presents **apres** l'envoi. Un envoi qui reussit en
     silence et un envoi qui n'a pas eu lieu se ressemblent.

Usage : python3 tools/publier_cle_signature.py
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
DOSSIER = Path(os.environ.get("USERPROFILE", Path.home())) / "assiette-signature"

MAGASIN = DOSSIER / "assiette-release.jks"
BASE64 = DOSSIER / "assiette-release.jks.base64"
MOT_DE_PASSE = DOSSIER / "mot-de-passe.txt"

ALIAS = "assiette"

# Le nom du secret, et le fichier d'ou vient sa valeur. `None` signifie : la
# valeur est une constante, ecrite ici, et non un secret a lire.
SECRETS: list[tuple[str, Path | None, str | None]] = [
    ("ANDROID_KEYSTORE_BASE64", BASE64, None),
    ("ANDROID_KEYSTORE_PASSWORD", MOT_DE_PASSE, None),
    ("ANDROID_KEY_ALIAS", None, ALIAS),
    ("ANDROID_KEY_PASSWORD", MOT_DE_PASSE, None),
]


def environnement_gh() -> dict[str, str]:
    """L'environnement dont `gh` a besoin pour retrouver sa session.

    Sans `APPDATA`, `gh` annonce « not logged into any GitHub hosts » alors que
    la session existe : il cherche sa configuration dans un dossier qu'il ne
    sait plus nommer sous ce shell.
    """
    env = dict(os.environ)
    if sys.platform == "win32":
        env.setdefault("APPDATA", str(Path.home() / "AppData" / "Roaming"))
    return env


def gh(arguments: list[str], entree: Path | None = None) -> subprocess.CompletedProcess[str]:
    """Appelle `gh`. La valeur, si elle vient d'un fichier, passe par l'entree standard."""
    flux = None
    try:
        if entree is not None:
            flux = open(entree, "rb")  # noqa: SIM115 — ferme dans le `finally`
        return subprocess.run(
            ["gh", *arguments],
            cwd=RACINE,
            env=environnement_gh(),
            stdin=flux if flux is not None else subprocess.DEVNULL,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
    finally:
        if flux is not None:
            flux.close()


def verifier_le_magasin() -> bool:
    """Ouvre le magasin avec le mot de passe enregistre, pour de vrai.

    On ne se contente pas de verifier que les fichiers existent : un mot de
    passe mal enregistre — un `\\r` ajoute par un editeur, une ligne vide —
    laisse un magasin et un fichier parfaitement presents, et un couple qui ne
    fonctionne pas.
    """
    keytool = (
        Path(os.environ.get("USERPROFILE", Path.home()))
        / ".workbuddy-ai"
        / "binaries"
        / "java"
        / "jre21"
        / "bin"
        / "keytool.exe"
    )
    if not keytool.is_file():
        print("keytool introuvable : verification du magasin ignoree.", file=sys.stderr)
        return True

    resultat = subprocess.run(
        [
            str(keytool),
            "-list",
            "-alias", ALIAS,
            "-keystore", str(MAGASIN),
            "-storetype", "PKCS12",
            "-storepass:file", str(MOT_DE_PASSE),
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if resultat.returncode != 0:
        print("Le magasin ne s'ouvre pas avec le mot de passe enregistre.", file=sys.stderr)
        print(resultat.stdout or "", file=sys.stderr)
        print(resultat.stderr or "", file=sys.stderr)
        return False
    print("magasin de cles : ouvert avec le mot de passe enregistre, alias present")
    return True


def main() -> int:
    for chemin in (MAGASIN, BASE64, MOT_DE_PASSE):
        if not chemin.is_file():
            print(f"introuvable : {chemin}", file=sys.stderr)
            print("Lancez d'abord : python3 tools/creer_cle_signature.py", file=sys.stderr)
            return 1

    # Le dossier de signature est hors du depot. On le verifie plutot que de le
    # supposer : si quelqu'un l'a deplace dans le depot, la cle partirait sur
    # GitHub au prochain `git add -A`.
    if RACINE in DOSSIER.parents or DOSSIER == RACINE:
        print(
            f"Le dossier de signature est dans le depot : {DOSSIER}\n"
            "Le depot est public. Deplacez-le avant de continuer.",
            file=sys.stderr,
        )
        return 1

    if not verifier_le_magasin():
        return 1

    print("\nDepot des secrets...")
    for nom, source, constante in SECRETS:
        if source is not None:
            resultat = gh(["secret", "set", nom], entree=source)
        else:
            # Une constante non sensible : `--body` suffit, et la valeur peut
            # etre affichee.
            resultat = gh(["secret", "set", nom, "--body", constante or ""])

        if resultat.returncode != 0:
            print(f"  ECHEC  {nom}", file=sys.stderr)
            print(f"         {resultat.stderr.strip()}", file=sys.stderr)
            return 1
        origine = source.name if source is not None else "(constante)"
        print(f"  ok     {nom}  <- {origine}")

    # --- verification apres coup ---
    #
    # Un envoi qui reussit et un envoi qui n'a pas eu lieu se ressemblent
    # exactement. On relit donc la liste, qui ne montre que les noms et les
    # dates — jamais les valeurs.
    print("\nVerification :")
    resultat = gh(["secret", "list"])
    if resultat.returncode != 0:
        print("  lecture de la liste impossible :", file=sys.stderr)
        print(f"  {resultat.stderr.strip()}", file=sys.stderr)
        return 1

    presents = {
        ligne.split()[0]
        for ligne in resultat.stdout.splitlines()
        if ligne.split()
    }
    attendus = {nom for nom, _, _ in SECRETS}
    manquants = attendus - presents
    if manquants:
        print(f"  absents apres envoi : {', '.join(sorted(manquants))}", file=sys.stderr)
        return 1

    print(f"  {len(attendus)} secrets presents : {', '.join(sorted(attendus))}")
    print("\nLa prochaine compilation Android signera les artefacts en release.")
    print("Le suffixe du nom passera de 'debug-key' a 'signe'.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
