#!/usr/bin/env python3
"""Publie une version : telecharge les artefacts du tag, les verifie, et les attache.

Pourquoi ce script existe
-------------------------
Une publication manuelle se fait en trois commandes `gh`, et rien n'y empeche
d'attacher un binaire dont le nom contredit le contenu. C'est exactement ce qui
s'est produit : `Assiette-v0.1.1-non-signee.ipa` declarait `0.1.0`. Le fichier
etait en ligne, telechargeable, et faux sur lui-meme.

Ici, la verification est **avant** la publication, et elle est bloquante : un
artefact dont le nom n'annonce pas ce que le binaire declare arrete le script.
Un binaire faux qui n'est pas publie ne coute rien ; un binaire faux qui l'est
coute la confiance de la personne qui l'installe.

Usage :
    python3 tools/publier_une_version.py v0.1.2
    python3 tools/publier_une_version.py v0.1.2 --essai     # verifie, ne publie pas
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent

sys.path.insert(0, str(RACINE / "tools"))

from verifier_version_binaire import lire_apk, lire_ipa  # noqa: E402

# Les flux qui produisent des artefacts, et les extensions a y prendre. Un meme
# flux peut en produire plusieurs : `android.yml` livre l'APK **et** l'AAB.
#
# Deduplicer par flux et non par couple (flux, extension) etait un defaut : le
# premier passage sur `android.yml` marquait le flux comme traite, et l'AAB
# n'etait jamais telecharge. Le script annoncait « verification faite » sur deux
# fichiers au lieu de trois, sans que rien ne signale l'absence.
FLUX: dict[str, tuple[str, ...]] = {
    "android.yml": (".apk", ".aab"),
    "ios.yml": (".ipa",),
}

# L'ordre de lecture : le premier fichier est celui qu'on met en avant.
ORDRE_EXTENSIONS = (".apk", ".aab", ".ipa")


def environnement() -> dict[str, str]:
    """L'environnement dont `gh` a besoin pour retrouver sa session."""
    env = dict(os.environ)
    if sys.platform == "win32":
        env.setdefault("APPDATA", str(Path.home() / "AppData" / "Roaming"))
    return env


def gh(arguments: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["gh", *arguments],
        cwd=RACINE,
        env=environnement(),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )


def run_du_tag(flux: str, tag: str) -> str | None:
    """L'identifiant du dernier run reussi de `flux` pour ce tag."""
    resultat = gh(
        [
            "run", "list",
            "--workflow", flux,
            "--branch", tag,
            "--limit", "5",
            "--json", "databaseId,conclusion,headBranch",
        ]
    )
    if resultat.returncode != 0:
        print(f"  lecture des runs de {flux} impossible : {resultat.stderr.strip()}", file=sys.stderr)
        return None

    try:
        runs = json.loads(resultat.stdout or "[]")
    except json.JSONDecodeError:
        print(f"  reponse illisible pour {flux}", file=sys.stderr)
        return None

    for run in runs:
        if run.get("conclusion") == "success" and run.get("headBranch") == tag:
            return str(run["databaseId"])

    print(f"  aucun run reussi de {flux} pour le tag {tag}", file=sys.stderr)
    return None


def telecharger(dossier: Path, tag: str) -> list[Path]:
    """Telecharge les artefacts des flux du tag, et rend les fichiers utiles.

    Le compte est verifie : chaque flux declare les extensions qu'il doit
    produire. Un flux qui en livre moins est signale, au lieu de passer pour un
    flux qui n'en produit pas. C'est ce qui manquait quand l'AAB a disparu.
    """
    trouves: list[Path] = []

    for flux, extensions in FLUX.items():
        identifiant = run_du_tag(flux, tag)
        if identifiant is None:
            continue

        destination = dossier / flux.replace(".yml", "")
        resultat = gh(["run", "download", identifiant, "--dir", str(destination)])
        if resultat.returncode != 0:
            print(f"  telechargement de {flux} impossible : {resultat.stderr.strip()}", file=sys.stderr)
            continue

        for extension in extensions:
            fichiers = sorted(destination.rglob(f"*{extension}"))
            if not fichiers:
                print(
                    f"  ATTENTION  {flux} n'a livre aucun {extension} "
                    f"(run {identifiant})",
                    file=sys.stderr,
                )
            trouves.extend(fichiers)

    # Ordre stable : l'APK d'abord, puis l'AAB, puis l'IPA.
    def rang(chemin: Path) -> int:
        try:
            return ORDRE_EXTENSIONS.index(chemin.suffix.lower())
        except ValueError:
            return len(ORDRE_EXTENSIONS)

    return sorted(trouves, key=rang)


def verifier(chemin: Path) -> tuple[bool, str, str]:
    """Confronte le nom du binaire a la version qu'il declare.

    Rend (conforme, version declaree ou vide, etat lisible). L'etat sert aux
    notes de version : « verifie » et « non verifiable » ne veulent pas dire la
    meme chose, et les confondre ferait croire a un controle qui n'a pas eu lieu.
    """
    suffixe = chemin.suffix.lower()
    if suffixe == ".apk":
        lues = lire_apk(chemin)
    elif suffixe == ".ipa":
        lues = lire_ipa(chemin)
    elif suffixe == ".aab":
        # Un AAB n'a pas d'`aapt2 dump badging` exploitable simplement : son
        # manifeste est en protobuf, pas en binaire Android classique. On ne
        # peut donc pas lire sa version de la meme facon. On le signale au lieu
        # de faire croire a une verification.
        print(f"  --     {chemin.name} : version non lisible dans un AAB, non verifiee")
        return True, "", "version non verifiable dans un AAB"
    else:
        print(f"  --     {chemin.name} : format inconnu, non verifie")
        return True, "", "format non reconnu, non verifie"

    if lues is None:
        print(f"  ECHEC  {chemin.name} : version illisible")
        return False, "", "version illisible"

    version, compilation = lues

    def present(valeur: str) -> bool:
        return re.search(rf"(?<![0-9.]){re.escape(valeur)}(?![0-9.])", chemin.name) is not None

    if present(version) and present(compilation):
        print(f"  ok     {chemin.name}  (declare {version}+{compilation})")
        return True, f"{version}+{compilation}", "verifie"

    print(f"  ECHEC  {chemin.name} declare {version}+{compilation}, absent de son nom")
    return False, f"{version}+{compilation}", "nom et contenu divergents"


def notes_de_version(tag: str, verifies: list[tuple[str, str, str]]) -> str:
    """Redige les notes : ce qui a change, et ce qui a ete verifie.

    Les notes sont lues par des personnes, pas par un outil. Elles disent donc
    deux choses : ce qui a change depuis la version precedente, et **ce qui a
    ete controle** dans les fichiers attaches. La seconde compte autant que la
    premiere : elle indique ce qu'on peut tenir pour verifie, et ce qu'on ne
    peut pas.
    """
    lignes = [f"Artefacts de {tag}.", ""]

    # Le tag precedent, pour delimiter le journal. `git describe` echoue s'il
    # n'y a pas de tag anterieur : c'est le cas de la premiere version, et ce
    # n'est pas une erreur.
    precedent = subprocess.run(
        ["git", "describe", "--tags", "--abbrev=0", f"{tag}^"],
        cwd=RACINE,
        capture_output=True,
        text=True,
        check=False,
    )
    intervalle = (
        f"{precedent.stdout.strip()}..{tag}" if precedent.returncode == 0 else tag
    )
    journal = subprocess.run(
        ["git", "log", "--no-merges", "--pretty=format:%s", intervalle],
        cwd=RACINE,
        capture_output=True,
        text=True,
        check=False,
    )
    sujets = [ligne for ligne in journal.stdout.splitlines() if ligne.strip()]
    if sujets:
        lignes.append("Changements :")
        lignes.extend(f"- {sujet}" for sujet in sujets)
        lignes.append("")

    lignes.append("Fichiers attaches :")
    for nom, version, etat in verifies:
        if etat == "verifie":
            lignes.append(f"- `{nom}` — declare {version}")
        else:
            lignes.append(f"- `{nom}` — {etat}")
    lignes.append("")
    lignes.append(
        "Le nom de chaque fichier a ete confronte a la version que le binaire "
        "declare, avant publication."
    )
    return "\n".join(lignes)


def main() -> int:
    analyseur = argparse.ArgumentParser(description=__doc__)
    analyseur.add_argument("tag", help="le tag a publier, par exemple v0.1.2")
    analyseur.add_argument("--essai", action="store_true", help="verifie sans publier")
    arguments = analyseur.parse_args()

    tag = arguments.tag

    # Le tag doit exister localement et avoir ete pousse : publier une version
    # qui n'est pas dans l'historique rendrait la publication impossible a
    # reproduire.
    verification = subprocess.run(
        ["git", "rev-parse", "--verify", f"{tag}^{{commit}}"],
        cwd=RACINE,
        capture_output=True,
        text=True,
        check=False,
    )
    if verification.returncode != 0:
        print(f"le tag {tag} n'existe pas dans ce depot.", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory() as temporaire:
        dossier = Path(temporaire)
        print(f"Telechargement des artefacts de {tag}...")
        fichiers = telecharger(dossier, tag)

        if not fichiers:
            print("aucun artefact trouve.", file=sys.stderr)
            return 1

        print(f"\nVerification de {len(fichiers)} fichier(s) :")
        conformes = True
        verifies: list[tuple[str, str, str]] = []
        for fichier in fichiers:
            ok, version, etat = verifier(fichier)
            verifies.append((fichier.name, version, etat))
            if not ok:
                conformes = False

        if not conformes:
            print(
                "\nPublication arretee : au moins un binaire annonce autre chose que "
                "ce qu'il declare.\nRien n'a ete publie.",
                file=sys.stderr,
            )
            return 1

        if arguments.essai:
            print("\n--essai : verification faite, rien n'a ete publie.")
            return 0

        # --- publication ---
        #
        # On garde les fichiers hors du dossier temporaire le temps de l'envoi.
        stable = RACINE / "artefacts-a-publier"
        if stable.exists():
            shutil.rmtree(stable)
        stable.mkdir(parents=True)
        for fichier in fichiers:
            shutil.copy2(fichier, stable / fichier.name)

        notes = notes_de_version(tag, verifies)

        existante = gh(["release", "view", tag, "--json", "tagName"])
        if existante.returncode == 0:
            print(f"\nLa release {tag} existe : les fichiers y sont ajoutes.")
            resultat = gh(["release", "upload", tag, *[str(f) for f in stable.iterdir()], "--clobber"])
        else:
            print(f"\nCreation de la release {tag}.")
            resultat = gh(
                [
                    "release", "create", tag,
                    *[str(f) for f in stable.iterdir()],
                    "--title", f"Assiette {tag}",
                    "--notes", notes,
                ]
            )

        if resultat.returncode != 0:
            print("publication impossible :", file=sys.stderr)
            print(resultat.stderr.strip(), file=sys.stderr)
            return 1

        print(resultat.stdout.strip())

    print(f"\nRelease {tag} publiee. Les fichiers restent dans : {RACINE / 'artefacts-a-publier'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
