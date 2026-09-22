#!/usr/bin/env python3
"""Banc de falsification pour les tests Flutter.

Trois pieges de lecture, tous trois fermes ici
----------------------------------------------

1. Les noms des tests **reussis** apparaissent aussi dans la sortie de
   `flutter test`. Chercher un nom dans le texte brut conclurait « detecte »
   sans qu'aucun test ne tombe. Le rapport JSON est donc lu, et seuls les tests
   qui n'ont pas reussi sont retenus.

2. Une mutation qui casse la compilation rend un code de sortie non nul **sans
   aucun test en echec**. Un banc qui ne distingue pas les deux conclut
   « non detecte » sur une mutation qui n'a jamais ete mesuree. D'ou le comptage
   des tests executes, et le refus de conclure autrement.

3. Un test peut echouer **autrement que par un `expect`** : `result` vaut alors
   `error` et non `failure`. Ne compter que `failure` faisait passer le total
   sous le total attendu, et le banc refusait de conclure sur une faute pourtant
   detectee — en invitant a corriger la mutation, c'est-a-dire a retirer la faute
   que le controle venait d'attraper. `error` compte donc comme un echec.

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


def lire_rapport(sortie: str) -> tuple[int, list[str], list[str]]:
    """Nombre de tests reellement executes, noms de ceux en echec, erreurs.

    Le test `loading` et les groupes sont marques `hidden` : les compter
    gonflerait le total et masquerait un chargement rate.

    Le troisieme retour porte le texte des evenements `error`. Il n'est **pas**
    utilise pour juger — il sert a dire **pourquoi** une mesure n'a pas pu
    tourner. Mesure faite : une compilation cassee produit exactement **un**
    test execute, le test de chargement, et le banc refusait alors de conclure en
    annoncant « Compilation cassee par la mutation, ou total a mettre a jour »
    sans jamais dire ce que le compilateur reprochait. Il fallait reproduire la
    mutation a la main pour l'apprendre.
    """
    noms: dict[int, str] = {}
    executes = 0
    echecs: list[str] = []
    erreurs: list[str] = []

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
        elif genre == "error":
            # Garde tel quel : c'est le message du compilateur ou du test.
            erreurs.append(str(evenement.get("error") or ""))
        elif genre == "testDone":
            if evenement.get("hidden"):
                continue
            resultat = evenement.get("result")
            # `error` compte comme un echec, au meme titre que `failure`. Un
            # test qui leve une exception non rattrapee — un `!` sur un null,
            # un mauvais type — n'a pas reussi : il a echoue autrement.
            #
            # L'ignorer faisait passer le total **sous** le total attendu, et le
            # banc declarait « la mesure n'a pas pu tourner » sur une faute
            # pourtant detectee. Le lecteur etait alors invite a corriger la
            # mutation, c'est-a-dire a retirer la faute que le controle venait
            # d'attraper. Une compilation cassee, elle, ne produit aucun
            # `testDone` : le total reste a zero, et le refus de conclure joue
            # toujours.
            if resultat not in ("success", "failure", "error"):
                continue
            executes += 1
            if resultat != "success":
                echecs.append(noms.get(evenement.get("testID"), "<test inconnu>"))

    return executes, echecs, erreurs


class ResultatFlutter:
    def __init__(self, code: int, sortie: str, erreur: str) -> None:
        self.code = code
        self.sortie = sortie
        self.erreur = erreur
        self.executes, self.echecs, self.erreurs = lire_rapport(sortie)

    @property
    def texte(self) -> str:
        return "\n".join(self.echecs) + "\n" + self.erreur

    @property
    def cause(self) -> str:
        """Le premier message d'erreur, pour dire pourquoi la mesure a echoue.

        Volontairement **hors** de [texte] : un message de compilateur cite le
        chemin du fichier de tests, et un marqueur qui s'y trouverait par
        accident ferait conclure « detecte » sur une mutation qui n'a rien
        mesure du tout.
        """
        if not self.erreurs:
            return ""
        return " ".join(self.erreurs[0].split())[:400]


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
            detail = f"\n  ce que la mesure a rapporte : {mesure.cause}" if mesure.cause else ""
            raise MesureImpossible(
                f"{mesure.executes} test(s) execute(s), {self.tests_attendus} attendu(s) : "
                "les tests n'ont pas pu tourner. Compilation cassee par la mutation, "
                f"ou total a mettre a jour si le fichier de tests a change.{detail}"
            )

        if resultat.returncode != 0 and not mesure.echecs:
            raise MesureImpossible(
                "code de sortie non nul sans aucun test en echec identifie."
            )

        return mesure
