#!/usr/bin/env python3
"""Verifie que la copie de travail respecte `.gitattributes`.

Pourquoi ce controle existe
---------------------------

`.gitattributes` declare `* text=auto eol=lf`. Mais `text=auto` normalise **a
l'entree** : le blob indexe est donc en LF meme quand la copie de travail est en
CRLF. Git ne signale rien — `git status` reste propre — et pourtant la copie de
travail diverge de ce que produira un clone sous Linux.

Consequence concrete : un controle local qui lit des octets ne voit pas la meme
chose que l'executeur d'integration continue. Un test peut passer ici et echouer
la-bas sans qu'aucun code n'ait change.

`git ls-files --eol` est le seul endroit ou cette divergence est visible. Ce
script est le seul lecteur de cette information : il doit donc refuser d'etre
vert s'il n'a rien pu lire, et non se contenter de compter zero defaut.

Les fichiers non suivis sont examines aussi, via `git check-attr` : un fichier
nouveau en CRLF violerait l'attribut des son ajout.

Usage : python3 tools/check_fins_de_ligne.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

MARQUEUR = "[fin-de-ligne]"

# Suffixes dont la conversion serait destructrice ou n'a pas de sens : binaires,
# archives, images. Git les traite deja comme tels (`-text`), mais les lire
# couterait du temps pour rien.
IGNORES = {
    ".png", ".jpg", ".jpeg", ".webp", ".gif", ".ico", ".ttf", ".otf", ".woff",
    ".woff2", ".zip", ".gz", ".tar", ".jar", ".apk", ".aab", ".ipa", ".so",
    ".dylib", ".dex", ".class", ".pdf", ".mp4", ".db", ".sqlite",
}


def git(*args: str) -> tuple[int, str]:
    resultat = subprocess.run(
        ["git", *args], cwd=ROOT, capture_output=True, text=True, check=False
    )
    return resultat.returncode, resultat.stdout


class Rapport:
    def __init__(self) -> None:
        self.lus = 0
        self.defauts: list[str] = []

    def defaut(self, chemin: str, attendu: str, trouve: str) -> None:
        self.defauts.append(
            f"{MARQUEUR} {chemin} — attribut '{attendu}', copie de travail en '{trouve}'"
        )


def lignes_de(chemin: Path) -> tuple[int, int] | None:
    """Compte les CRLF et les LF isoles. `None` si le fichier n'est pas lisible."""
    try:
        octets = chemin.read_bytes()
    except OSError:
        return None
    crlf = octets.count(b"\r\n")
    lf = octets.count(b"\n") - crlf
    return crlf, lf


def examiner(rapport: Rapport, chemin: str, attribut: str) -> None:
    """Compare l'attribut declare et les fins de ligne reellement presentes."""
    if Path(chemin).suffix.lower() in IGNORES:
        return

    mesure = lignes_de(ROOT / chemin)
    rapport.lus += 1
    if mesure is None:
        return

    crlf, lf = mesure

    if attribut == "lf" and crlf > 0:
        rapport.defaut(chemin, "lf", f"crlf x{crlf}")
    elif attribut == "crlf" and lf > 0:
        rapport.defaut(chemin, "crlf", f"lf x{lf}")


def fichiers_suivis(rapport: Rapport) -> int:
    """Verifie les deux cotes : le blob indexe, et la copie de travail.

    Le cote indexe est le seul qui compte en integration continue : un clone
    frais respecte toujours l'attribut, donc un controle qui ne regarderait que
    la copie de travail y serait vide. Un blob indexe en CRLF, lui, est un
    defaut reel, visible partout, et que `git add --renormalize` repare.
    """
    code, sortie = git("ls-files", "--eol")
    if code != 0:
        print(f"{MARQUEUR} `git ls-files --eol` a echoue : mesure impossible", file=sys.stderr)
        return -1

    lus = 0
    for ligne in sortie.splitlines():
        champs = ligne.split()
        if len(champs) < 5:
            continue
        index, travail, attribut, eol = champs[0], champs[1], champs[2], champs[3]
        chemin = " ".join(champs[4:])
        if not index.startswith("i/") or not travail.startswith("w/"):
            continue

        if Path(chemin).suffix.lower() in IGNORES:
            continue

        attendu = "lf" if "eol=lf" in eol else ("crlf" if "eol=crlf" in eol else None)
        lus += 1

        if attendu is None:
            continue

        oppose = "crlf" if attendu == "lf" else "lf"
        if index == f"i/{oppose}":
            rapport.defauts.append(
                f"{MARQUEUR} {chemin} — blob indexe en {oppose.upper()} "
                f"alors que l'attribut impose '{attendu}'"
            )

        # La copie de travail est relue au niveau octet : c'est la seule mesure
        # qui attrape aussi un fichier melange (LF et CRLF dans le meme fichier),
        # que `git ls-files --eol` rapporte comme 'mixed'.
        examiner(rapport, chemin, attendu)

    return lus


def fichiers_non_suivis(rapport: Rapport) -> int:
    """Un fichier nouveau en CRLF violerait l'attribut des son ajout."""
    code, sortie = git("ls-files", "--others", "--exclude-standard")
    if code != 0:
        print(f"{MARQUEUR} `git ls-files --others` a echoue : mesure impossible", file=sys.stderr)
        return -1

    chemins = [
        ligne for ligne in sortie.splitlines()
        if ligne.strip() and Path(ligne).suffix.lower() not in IGNORES
    ]
    if not chemins:
        return 0

    # `git check-attr --stdin -z` repond pour chaque chemin, dans l'ordre.
    resultat = subprocess.run(
        ["git", "check-attr", "--stdin", "-z", "eol"],
        cwd=ROOT,
        input="\0".join(chemins),
        capture_output=True,
        text=True,
        check=False,
    )
    if resultat.returncode != 0:
        print(f"{MARQUEUR} `git check-attr` a echoue : mesure impossible", file=sys.stderr)
        return -1

    morceaux = [m for m in resultat.stdout.split("\0") if m != ""]
    # Chaque reponse occupe trois champs : chemin, nom d'attribut, valeur.
    for position in range(0, len(morceaux) - 2, 3):
        chemin, _, valeur = morceaux[position], morceaux[position + 1], morceaux[position + 2]
        if valeur == "lf":
            examiner(rapport, chemin, "lf")
        elif valeur == "crlf":
            examiner(rapport, chemin, "crlf")
        else:
            rapport.lus += 1

    return len(chemins)


def main() -> int:
    rapport = Rapport()

    suivis = fichiers_suivis(rapport)
    non_suivis = fichiers_non_suivis(rapport)

    if suivis < 0 or non_suivis < 0:
        return 1

    # Un controle qui ne lit rien compte zero tout aussi tranquillement : si le
    # depot est vide ou si la mesure a echoue, ce n'est pas un feu vert.
    if suivis == 0:
        print(
            f"{MARQUEUR} aucun fichier suivi lu : la mesure ne prouve rien, "
            "elle n'a rien regarde",
            file=sys.stderr,
        )
        return 1

    if rapport.defauts:
        print("Fins de ligne non conformes a .gitattributes :", file=sys.stderr)
        for defaut in rapport.defauts:
            print(f"  - {defaut}", file=sys.stderr)
        print(
            "\nReparer avec : python3 tools/normaliser_fins_de_ligne.py --appliquer",
            file=sys.stderr,
        )
        print(
            f"\n{len(rapport.defauts)} defaut(s), {rapport.lus} fichiers lus.",
            file=sys.stderr,
        )
        return 1

    print(
        f"{rapport.lus} fichiers lus ({suivis} suivis, {non_suivis} non suivis) — "
        "fins de ligne conformes."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
