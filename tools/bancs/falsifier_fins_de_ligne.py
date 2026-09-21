#!/usr/bin/env python3
"""Falsifie `tools/check_fins_de_ligne.py`.

Le controle lit une seule information — la comparaison entre l'attribut `eol`
declare et les fins de ligne reellement presentes. Ce banc fabrique chaque
divergence possible et verifie que le controle tombe, puis verifie qu'il ne
signale **pas** un fichier legitimement en CRLF : sans ce temoin negatif, rien
ne prouverait qu'il distingue, plutot qu'il ne compte.

Il verifie aussi le garde-fou : un controle qui ne lit rien doit refuser d'etre
vert.

Usage : python3 tools/bancs/falsifier_fins_de_ligne.py
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, Banc, empreinte_arbre  # noqa: E402

SCRIPT = RACINE / "tools" / "check_fins_de_ligne.py"

# Un fichier suivi dont le contenu est stable et petit : le rendre binaire
# n'aurait pas de sens, mais le rendre CRLF en a un.
CIBLE = "tools/check_prompt_sync.py"


def etat_index() -> set[str]:
    """L'index, compare a HEAD — et **non** l'etat de la copie de travail.

    Ce que la campagne doit rendre intact, c'est l'**index** : le cas « blob
    indexe en CRLF » y ecrit directement, et `restaurer_index()` doit le
    reconstruire a l'identique.

    Mesurer `git status --short` confondait deux choses :

      - l'index, que la campagne touche ;
      - la copie de travail, qu'un auteur modifie **pendant** que le banc
        tourne.

    Mesure, et non precaution theorique : une campagne ou `docs/publication.md`
    a ete edite en parallele a rendu « index reconstruit : DIVERGENT » alors que
    l'index etait intact. Le banc accusait sa propre campagne d'avoir abime
    l'index, et envoyait chercher un defaut qui n'existait pas — le vrai risque
    d'un banc, qui est de faire corriger ce qui n'est pas casse.

    Un repere pris avant et apres ne protege pas de cela : il protege d'une
    modification **deja presente**, pas d'une modification **concurrente**.
    Seule la mesure du bon objet le fait.
    """
    resultat = subprocess.run(
        ["git", "diff", "--cached", "--name-status"],
        cwd=RACINE,
        capture_output=True,
        text=True,
        check=False,
    )
    return {ligne for ligne in resultat.stdout.splitlines() if ligne.strip()}


def etat_copie_de_travail() -> set[str]:
    """Les fichiers suivis modifies dans la copie de travail, hors non suivis.

    Sert a **observer**, non a juger : une copie de travail qui bouge pendant la
    campagne ne dit rien de l'index, mais elle dit que l'environnement n'etait
    pas au repos. Le rapport le signale, sans faire echouer le banc.
    """
    resultat = subprocess.run(
        ["git", "status", "--short", "--", "app", "backend", "tools", "docs"],
        cwd=RACINE,
        capture_output=True,
        text=True,
        check=False,
    )
    return {
        ligne for ligne in resultat.stdout.splitlines() if not ligne.startswith("??")
    }


def principal() -> int:
    banc = Banc(SCRIPT)

    # --- les temoins d'un passage precedent ------------------------------
    #
    # Ceinture et bretelles, apres le vrai remede (voir `Banc.retirer`) : sur
    # cette machine, une suppression peut etre bloquee **sans le dire**, et un
    # passage precedent peut donc avoir laisse son temoin. Le passage suivant
    # refuse alors de demarrer sur « le controle echoue deja avant toute
    # mutation », en accusant un fichier que ce banc fabrique lui-meme — un
    # depot annonce casse pour un desordre que le banc a cause.
    #
    # Ces noms ne peuvent pas etre du contenu du depot : ils portent le prefixe
    # que ce banc reserve a ses essais. Les retirer ne peut donc rien casser, et
    # le retrait est **dit** — un nettoyage silencieux masquerait le meme defaut
    # une autre fois.
    for reste in sorted((RACINE / "tools").glob("__banc_essai*")):
        print(f"temoin d'un passage precedent, retire : {reste.name}")
        banc.retirer(reste)

    # Toutes les mutations de ce banc portent sur `tools/` : c'est la surface a
    # prouver intacte. Mesurer `app/` y ajouterait les artefacts de compilation,
    # qui ne sont jamais touches ici.
    avant = empreinte_arbre(RACINE / "tools")
    index_avant = etat_index()
    travail_avant = etat_copie_de_travail()

    # --- etat initial : le controle doit etre vert -----------------------
    initial = banc.etat_initial()
    print(f"etat initial : code {initial.code}")
    if initial.code != 0:
        print(initial.texte, file=sys.stderr)
        print("le controle echoue deja avant toute mutation.", file=sys.stderr)
        return 2

    def suivi_vers_crlf() -> None:
        fichier = banc.suivre(CIBLE)
        # Au niveau octet, avec une ancre ASCII qui ne contient pas de fin de
        # ligne : c'est exactement ce qui manquait au banc precedent.
        fichier.ecrire(fichier.origine.replace(b"\n", b"\r\n"))

    def non_suivi_vers_crlf() -> None:
        banc.creer("tools/__banc_essai.txt", b"ligne un\r\nligne deux\r\n")

    def non_suivi_bat_vers_lf() -> None:
        # `.gitattributes` impose `*.bat text eol=crlf` : un `.bat` en LF viole
        # l'attribut, dans l'autre sens.
        banc.creer("tools/__banc_essai.bat", b"@echo off\n")

    def bat_en_crlf_conforme() -> None:
        # Temoin negatif : ce fichier respecte son attribut, il ne doit pas etre
        # signale. Un controle qui signalerait tout CRLF echouerait ici.
        banc.creer("tools/__banc_essai_conforme.bat", b"@echo off\r\n")

    def blob_indexe_en_crlf() -> None:
        """Force un blob CRLF dans l'index, hors de la normalisation de git.

        C'est le seul defaut visible en integration continue : un clone frais
        respecte toujours l'attribut, donc la copie de travail y est conforme par
        construction. Un blob CRLF dans l'index, lui, voyage partout.

        `git add` normalise : il faut donc ecrire le blob soi-meme et pointer
        l'index dessus. L'index est ensuite reconstruit par `git reset`, ce que
        fait `restaurer_index()` meme si le cas echoue.
        """
        contenu = (RACINE / CIBLE).read_bytes().replace(b"\n", b"\r\n")
        blob = subprocess.run(
            ["git", "hash-object", "-w", "--stdin"],
            cwd=RACINE,
            input=contenu,
            capture_output=True,
            check=True,
        ).stdout.decode().strip()
        mode = subprocess.run(
            ["git", "ls-files", "--stage", "--", CIBLE],
            cwd=RACINE,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.split()[0]
        subprocess.run(
            ["git", "update-index", "--cacheinfo", f"{mode},{blob},{CIBLE}"],
            cwd=RACINE,
            check=True,
            capture_output=True,
        )

    banc.cas("fichier suivi remis en CRLF", "[fin-de-ligne]", suivi_vers_crlf)
    banc.cas("fichier non suivi en CRLF", "[fin-de-ligne]", non_suivi_vers_crlf)
    banc.cas("fichier .bat en LF", "[fin-de-ligne]", non_suivi_bat_vers_lf)
    banc.cas(".bat en CRLF (conforme)", "[fin-de-ligne]", bat_en_crlf_conforme, attendu=False)
    banc.index_a_reinitialiser = True
    banc.cas("blob indexe en CRLF", "[fin-de-ligne]", blob_indexe_en_crlf)

    # --- le garde-fou : ne rien lire n'est pas un feu vert ---------------
    with tempfile.TemporaryDirectory() as temporaire:
        bac = Path(temporaire)
        subprocess.run(["git", "init", "-q"], cwd=bac, check=True)
        # Le script se croit dans `tools/` : le placer ailleurs lui ferait lire
        # le mauvais dossier, et le banc mesurerait autre chose que le garde-fou.
        (bac / "tools").mkdir()
        copie = bac / "tools" / "check_fins_de_ligne.py"
        shutil.copy2(SCRIPT, copie)
        resultat = subprocess.run(
            [sys.executable, str(copie)],
            cwd=bac,
            capture_output=True,
            text=True,
            check=False,
        )
        refuse = resultat.returncode != 0 and "aucun fichier suivi lu" in (
            resultat.stdout + resultat.stderr
        )
        banc.lignes.append(
            (
                "depot sans fichier suivi",
                "refus de conclure",
                "refuse" if refuse else "VERT A TORT",
                refuse,
            )
        )

    code = banc.tableau()

    # --- la restauration doit etre exacte --------------------------------
    apres = empreinte_arbre(RACINE / "tools")

    identiques = avant == apres
    print(f"fichiers dans tools/             : {len(apres)}")
    print(f"restauration a l'octet           : {'conforme' if identiques else 'DIVERGENTE'}")

    if not identiques:
        differents = sorted(
            set(avant) ^ set(apres) | {c for c in set(avant) & set(apres) if avant[c] != apres[c]}
        )
        for chemin in differents:
            print(f"  - {chemin}", file=sys.stderr)
        return 1

    if code != 0:
        return code

    # --- l'index doit avoir ete reconstruit a l'identique ------------------
    #
    # Le critere est la comparaison avec l'etat d'avant, pas la vacuite : le
    # cas « blob indexe en CRLF » ecrit dans l'index, et la campagne doit le
    # rendre tel qu'elle l'a trouve — qu'il ait ete vide ou non.
    index_apres = etat_index()
    print(
        f"index reconstruit                 : "
        f"{'conforme' if index_apres == index_avant else 'DIVERGENT'}"
    )
    if index_apres != index_avant:
        for ligne in sorted(index_apres ^ index_avant):
            print(f"  - {ligne}", file=sys.stderr)
        return 1

    # --- observation : la copie de travail a-t-elle bouge ? --------------
    #
    # Aucun verdict ici. Une modification concurrente ne dit rien de l'index —
    # c'est justement ce que la mesure ci-dessus a appris a distinguer. Elle dit
    # en revanche que l'environnement n'etait pas au repos, et cela merite d'etre
    # dit plutot que tu : c'est ce qui explique qu'un resultat voisin, mesure
    # ailleurs, puisse differer.
    travail_apres = etat_copie_de_travail()
    if travail_apres != travail_avant:
        print(
            "copie de travail                 : modifiee pendant la campagne "
            "(l'index, lui, est intact)"
        )

    # --- etat final : le controle doit etre redevenu vert ----------------
    final = banc.executer()
    print(f"\netat final : code {final.code}")
    if final.code != 0:
        print(final.texte, file=sys.stderr)
        return 1

    print("vert — le controle detecte, distingue, et sait refuser de conclure.")
    return 0


if __name__ == "__main__":
    sys.exit(principal())
