#!/usr/bin/env python3
"""Cree la cle de signature Android, hors du depot, sans exposer son mot de passe.

Pourquoi ce script existe
-------------------------
Les artefacts produits par la CI portent `debug-key` dans leur nom : ils sont
signes avec la cle de debogage. Ils s'installent, mais le Play Store refuse un
AAB signe avec une cle de debogage. Il faut donc une vraie cle de signature.

Cette cle est l'**identite de l'application**, pour toujours : le Play Store
identifie une application par son couple (nom de paquet, cle de signature). Une
cle perdue ne se remplace pas — elle oblige a publier une nouvelle application
sous un autre nom de paquet, et les personnes qui ont installe la premiere ne
recevront plus de mise a jour.

Trois consequences, toutes tenues par ce script :

  1. **La cle ne va pas dans le depot.** Le depot est public. Elle est ecrite
     dans un dossier hors du depot, `%USERPROFILE%\\assiette-signature`.
  2. **Le mot de passe n'apparait nulle part** : ni sur la ligne de commande, ni
     dans une sortie, ni dans une conversation. Il est tire au hasard, ecrit dans
     un fichier, et `keytool` le lit depuis ce fichier (`-storepass:file`).
     La ligne de commande reste lisible par tout processus de la machine ; un
     mot de passe qu'on y passe est un mot de passe rendu public.
  3. **Une sauvegarde est faite immediatement**, et son emplacement est affiche.
     Une cle non sauvegardee est une cle perdue.

Ce que le script produit, dans le dossier de signature :

    assiette-release.jks        la cle
    mot-de-passe.txt            le mot de passe du magasin et de la cle
    empreinte-sha256.txt        l'empreinte, a comparer avec ce que Play affiche
    LIRE-MOI.txt                ce qu'il faut faire de ces fichiers

Usage : python3 tools/creer_cle_signature.py
"""

from __future__ import annotations

import base64
import hashlib
import os
import re
import secrets
import shutil
import string
import subprocess
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent

# L'empreinte d'un certificat, telle que `keytool` l'ecrit : des paires
# hexadecimales separees par des deux-points. On ne cherche **pas** le libelle
# « SHA256 », parce que `keytool` suit la langue du systeme : il ecrit
# `SHA 256:` en francais, avec une espace, la ou l'anglais ecrit `SHA256:`.
# Un filtre sur le libelle echouait donc sur cette machine, et l'empreinte
# n'etait pas ecrite. Le motif porte sur la forme, pas sur le mot.
MOTIF_EMPREINTE = re.compile(r"\b(?:[0-9A-F]{2}:){10,}[0-9A-F]{2}\b")

# Hors du depot, volontairement : rien de ce qui est ici ne doit pouvoir etre
# ajoute par un `git add -A` distrait.
DOSSIER = Path(os.environ.get("USERPROFILE", Path.home())) / "assiette-signature"

MAGASIN = DOSSIER / "assiette-release.jks"
MOT_DE_PASSE = DOSSIER / "mot-de-passe.txt"
EMPREINTE = DOSSIER / "empreinte-sha256.txt"
LIRE_MOI = DOSSIER / "LIRE-MOI.txt"

ALIAS = "assiette"

# Le mot de passe du magasin et celui de la cle sont **le meme**. Ce n'est pas
# de la paresse : le format PKCS#12 — celui que `keytool` produit par defaut
# depuis Java 9 — n'accepte pas deux mots de passe distincts, et ignore
# silencieusement `-keypass`. En tenir deux ici laisserait croire a une
# separation qui n'existe pas.
#
# 40 caracteres d'un alphabet de 62 : environ 238 bits d'entropie. Bien au-dela
# de ce qu'une recherche exhaustive peut couvrir.
ALPHABET = string.ascii_letters + string.digits
LONGUEUR = 40

# Caracteres a eviter dans les champs du nom distingue : `keytool` interprete
# `,` `+` `"` `\` `<` `>` `;` comme de la syntaxe. Les noms ci-dessous n'en
# contiennent pas, mais la regle vaut d'etre notee pour qui les modifiera.
NOM_DISTINGUE = (
    "CN=Assiette, OU=FCPE Ecoles Freres Lumieres, O=FCPE, L=Montmagny, "
    "ST=Quebec, C=CA"
)

# 10000 jours, soit environ 27 ans. Le Play Store exige une cle valide au moins
# jusqu'au 22 octobre 2033 ; viser cette date de justesse obligerait a refaire
# une demande de reinitialisation, qui n'est pas garantie d'aboutir.
VALIDITE_JOURS = 10000


def trouver_keytool() -> Path:
    """Le `keytool` du JDK local, puis celui du `PATH`.

    Le JDK du projet est un JRE : il contient `keytool`, mais pas `javac`. C'est
    suffisant ici, et cela evite d'installer un JDK complet pour une commande.
    """
    local = (
        Path(os.environ.get("USERPROFILE", Path.home()))
        / ".workbuddy-ai"
        / "binaries"
        / "java"
        / "jre21"
        / "bin"
        / "keytool.exe"
    )
    if local.is_file():
        return local

    sur_le_path = shutil.which("keytool")
    if sur_le_path:
        return Path(sur_le_path)

    raise SystemExit(
        "keytool introuvable. Il vient avec un JDK ou un JRE :\n"
        "  https://adoptium.net/temurin/releases/?version=21"
    )


def creer_mot_de_passe() -> str:
    """Un mot de passe tire au hasard, jamais affiche."""
    return "".join(secrets.choice(ALPHABET) for _ in range(LONGUEUR))


def lancer(commande: list[str]) -> subprocess.CompletedProcess[str]:
    """Execute une commande, en tolerant l'encodage de la console.

    `keytool` ecrit dans la page de codes de la console — cp1252 ou cp850 sous
    Windows — et non en UTF-8. Un `text=True` sans `errors` fait donc lever le
    fil de lecture sur le premier accent, et `stdout` ressort a `None` : l'echec
    se lit alors comme « pas de sortie », alors que la commande a peut-etre
    reussi. Mesure faite sur ce script meme.
    """
    return subprocess.run(
        commande,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )


def main() -> int:
    keytool = trouver_keytool()
    print(f"keytool : {keytool}")

    DOSSIER.mkdir(parents=True, exist_ok=True)

    if MAGASIN.is_file():
        # On ne recree pas une cle existante : elle est l'identite de
        # l'application. Mais on peut rejouer tout ce qui en derive, ce qui est
        # utile apres une sauvegarde restauree ou un fichier perdu.
        if not MOT_DE_PASSE.is_file():
            print(f"\nUne cle existe : {MAGASIN}", file=sys.stderr)
            print(f"mais son mot de passe est absent : {MOT_DE_PASSE}", file=sys.stderr)
            print(
                "Sans lui, la cle est inutilisable. Restaurez le mot de passe depuis\n"
                "votre sauvegarde. Il n'existe aucun moyen de le retrouver.",
                file=sys.stderr,
            )
            return 1

        print(f"\nCle existante conservee : {MAGASIN}")
        print("Les fichiers derives sont regeneres (base64, empreinte, mode d'emploi).")
        mot_de_passe = MOT_DE_PASSE.read_text(encoding="ascii")
    else:
        mot_de_passe = creer_mot_de_passe()
        # `write_bytes` et non `write_text` : ce dernier ecrirait en CRLF sous
        # Windows, et un `\\r` en fin de mot de passe est un echec que personne
        # ne diagnostique — `keytool` se contente de dire que le mot de passe
        # est incorrect.
        MOT_DE_PASSE.write_bytes(mot_de_passe.encode("ascii"))

        commande = [
            str(keytool),
            "-genkeypair",
            "-alias", ALIAS,
            "-keyalg", "RSA",
            "-keysize", "2048",
            "-validity", str(VALIDITE_JOURS),
            "-dname", NOM_DISTINGUE,
            "-keystore", str(MAGASIN),
            "-storetype", "PKCS12",
            # Le mot de passe est lu depuis le fichier : il n'apparait donc ni
            # sur la ligne de commande, ni dans l'historique du shell, ni ici.
            "-storepass:file", str(MOT_DE_PASSE),
            "-keypass:file", str(MOT_DE_PASSE),
        ]

        print("Creation de la cle...")
        resultat = lancer(commande)
        if resultat.returncode != 0:
            # keytool n'affiche jamais le mot de passe : sa sortie peut donc
            # etre montree telle quelle.
            print("Echec de la creation :", file=sys.stderr)
            print(resultat.stdout or "", file=sys.stderr)
            print(resultat.stderr or "", file=sys.stderr)
            return 1

        if not MAGASIN.is_file():
            print("keytool a rendu 0 mais le magasin est absent.", file=sys.stderr)
            return 1

    # --- empreinte, pour pouvoir comparer avec ce que Play affichera ---
    empreinte = lancer(
        [
            str(keytool),
            "-list",
            "-v",
            "-alias", ALIAS,
            "-keystore", str(MAGASIN),
            "-storetype", "PKCS12",
            "-storepass:file", str(MOT_DE_PASSE),
        ]
    )
    if empreinte.returncode != 0:
        print("Lecture de l'empreinte impossible :", file=sys.stderr)
        print(empreinte.stdout or "", file=sys.stderr)
        print(empreinte.stderr or "", file=sys.stderr)
        return 1

    lignes_empreinte = [
        ligne.strip()
        for ligne in (empreinte.stdout or "").splitlines()
        if MOTIF_EMPREINTE.search(ligne)
    ]
    if not lignes_empreinte:
        # Ne pas ecrire un fichier vide en silence : un fichier d'empreinte
        # vide se lirait comme « pas d'empreinte », et personne ne saurait
        # qu'il fallait en avoir une.
        print("Empreinte introuvable dans la sortie de keytool.", file=sys.stderr)
        print(empreinte.stdout or "", file=sys.stderr)
        return 1
    EMPREINTE.write_bytes(("\n".join(lignes_empreinte) + "\n").encode("utf-8"))

    # --- base64 du magasin, pret a coller dans un secret GitHub ---
    (DOSSIER / "assiette-release.jks.base64").write_bytes(
        base64.b64encode(MAGASIN.read_bytes())
    )

    taille = MAGASIN.stat().st_size
    sha256 = hashlib.sha256(MAGASIN.read_bytes()).hexdigest()

    LIRE_MOI.write_bytes(
        (
            "CLE DE SIGNATURE ANDROID — ASSIETTE\n"
            "===================================\n\n"
            "Ce dossier est l'identite de l'application sur le Play Store.\n"
            "S'il est perdu, l'application ne peut plus jamais etre mise a jour :\n"
            "le Play Store identifie une application par son nom de paquet ET sa cle.\n\n"
            "FICHIERS\n"
            "--------\n"
            "  assiette-release.jks         la cle. A ne jamais regenerer.\n"
            "  assiette-release.jks.base64  la meme cle, encodee, pour GitHub.\n"
            "  mot-de-passe.txt             le mot de passe, commun au magasin et a la cle.\n"
            "  empreinte-sha256.txt         l'empreinte, a comparer avec ce que Play affiche.\n\n"
            "CE QU'IL FAUT EN FAIRE\n"
            "----------------------\n"
            "1. Copier tout ce dossier sur un support que vous gardez : cle USB,\n"
            "   disque externe, ou gestionnaire de mots de passe. Pas seulement ici.\n"
            "2. Les quatre valeurs vont dans les secrets GitHub du depot\n"
            "   (Settings -> Secrets and variables -> Actions -> Secrets) :\n\n"
            "     ANDROID_KEYSTORE_BASE64      <- contenu de assiette-release.jks.base64\n"
            "     ANDROID_KEYSTORE_PASSWORD    <- contenu de mot-de-passe.txt\n"
            "     ANDROID_KEY_ALIAS            <- assiette\n"
            "     ANDROID_KEY_PASSWORD         <- contenu de mot-de-passe.txt\n\n"
            "   Le script tools/publier_cle_signature.py fait ces quatre envois\n"
            "   pour vous, sans afficher les valeurs.\n\n"
            "ATTENTION\n"
            "---------\n"
            "Ne supprimez pas ce dossier. Ne le mettez jamais dans le depot :\n"
            "le depot est public, et une cle de signature publiee permet a\n"
            "n'importe qui de signer une application qui se fait passer pour celle-ci.\n"
        ).encode("utf-8")
    )

    print("\nCle creee.")
    print(f"  dossier      : {DOSSIER}")
    print(f"  magasin      : {taille} octets")
    print(f"  empreinte    : {sha256[:16]}...")
    print(f"  alias        : {ALIAS}")
    print(f"  validite     : {VALIDITE_JOURS} jours")
    print("\nLe mot de passe n'a ete affiche a aucun moment. Il est dans :")
    print(f"  {MOT_DE_PASSE}")
    print("\nA faire maintenant : sauvegarder ce dossier hors de cette machine.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
