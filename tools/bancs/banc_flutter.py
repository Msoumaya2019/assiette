#!/usr/bin/env python3
"""Banc de falsification pour les tests Flutter.

Deux pieges de lecture, tous deux fermes ici
--------------------------------------------

1. Les noms des tests **reussis** apparaissent aussi dans la sortie de
   `flutter test`. Chercher un nom dans le texte brut conclurait « detecte »
   sans qu'aucun test ne tombe. Le rapport JSON est donc lu, et seuls les tests
   dont `result` vaut `failure` sont retenus.

2. Une mutation qui casse la compilation rend un code de sortie non nul **sans
   aucun test en echec**. Un banc qui ne distingue pas les deux conclut
   « non detecte » sur une mutation qui n'a jamais ete mesuree. D'ou le comptage
   des tests executes, et le refus de conclure autrement.

Partage par les bancs qui falsifient des tests Flutter, pour que tous mesurent
dans les memes conditions.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from banc import RACINE, Banc, MesureImpossible  # noqa: E402
from environnement_flutter import environnement_mesure  # noqa: E402


def lire_rapport(sortie: str) -> tuple[int, list[str]]:
    """Nombre de tests reellement executes, et noms de ceux en echec.

    Le test `loading` et les groupes sont marques `hidden` : les compter
    gonflerait le total et masquerait un chargement rate.
    """
    noms: dict[int, str] = {}
    executes = 0
    echecs: list[str] = []

    for ligne in sortie.splitlines():
        ligne = ligne.strip()
        if not ligne.startswith("{"):
            continue
        try:
            evenement = json.loads(ligne)
        except json.JSONDecodeError:
            continue

        genre = evenement.get("type")
        if genre == "testStart":
            test = evenement.get("test") or {}
            identifiant = test.get("id")
            if isinstance(identifiant, int):
                noms[identifiant] = str(test.get("name") or "")
        elif genre == "testDone":
            if evenement.get("hidden"):
                continue
            resultat = evenement.get("result")
            if resultat not in ("success", "failure"):
                continue
            executes += 1
            if resultat == "failure":
                echecs.append(noms.get(evenement.get("testID"), "<test inconnu>"))

    return executes, echecs


class ResultatFlutter:
    def __init__(self, code: int, sortie: str, erreur: str) -> None:
        self.code = code
        self.sortie = sortie
        self.erreur = erreur
        self.executes, self.echecs = lire_rapport(sortie)

    @property
    def texte(self) -> str:
        return "\n".join(self.echecs) + "\n" + self.erreur


class BancFlutter(Banc):
    """Le banc des controles compare des marqueurs ; celui-ci compare des tests."""

    def __init__(
        self,
        script: Path,
        flutter: Path,
        cible: str,
        tests_attendus: int,
    ) -> None:
        super().__init__(script)
        self.flutter = flutter
        self.cible = cible
        self.tests_attendus = tests_attendus

    def executer(self) -> ResultatFlutter:  # type: ignore[override]
        resultat = subprocess.run(
            [str(self.flutter), "test", self.cible, "--reporter", "json"],
            cwd=RACINE / "app",
            env=environnement_mesure(),
            capture_output=True,
            text=True,
            check=False,
        )
        mesure = ResultatFlutter(resultat.returncode, resultat.stdout, resultat.stderr)

        if mesure.executes != self.tests_attendus:
            raise MesureImpossible(
                f"{mesure.executes} test(s) execute(s), {self.tests_attendus} attendu(s) : "
                "les tests n'ont pas pu tourner. Compilation cassee par la mutation, "
                "ou total a mettre a jour si le fichier de tests a change."
            )

        if resultat.returncode != 0 and not mesure.echecs:
            raise MesureImpossible(
                "code de sortie non nul sans aucun test en echec identifie."
            )

        return mesure
