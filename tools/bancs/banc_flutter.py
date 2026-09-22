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

4. Un **marqueur qui ne correspond a aucun nom de test** ne peut jamais
   apparaitre dans le rapport. Le banc concluait « NON DETECTE » sur une faute
   pourtant attrapee, et invitait a corriger la mutation — soit a retirer une
   faute bien reelle. Mesure : un marqueur ecrit « un corps illisible ne remplace
   pas la panne » ne trouvait rien, le test s'appelant « un corps **d'erreur**
   illisible ... ». Reproduite a la main, la mutation faisait bien tomber le
   test. `BancFlutter.cas` refuse desormais de mesurer avec un tel marqueur.

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


def lire_rapport(sortie: str) -> tuple[int, list[str], list[str], list[str]]:
    """Tests executes, noms de ceux en echec, erreurs, et **tous** les noms.

    Le test `loading` et les groupes sont marques `hidden` : les compter
    gonflerait le total et masquerait un chargement rate.

    Le troisieme retour porte le texte des evenements `error`. Il n'est **pas**
    utilise pour juger — il sert a dire **pourquoi** une mesure n'a pas pu
    tourner. Mesure faite : une compilation cassee produit exactement **un**
    test execute, le test de chargement, et le banc refusait alors de conclure en
    annoncant « Compilation cassee par la mutation, ou total a mettre a jour »
    sans jamais dire ce que le compilateur reprochait. Il fallait reproduire la
    mutation a la main pour l'apprendre.

    Le quatrieme retour existe pour une autre raison, et il a fallu une mesure
    pour le voir : un **marqueur qui ne correspond a aucun nom de test** ne peut
    jamais apparaitre dans le rapport. Le banc concluait alors « NON DETECTE » sur
    une faute pourtant attrapee. Voir `BancFlutter.cas`.
    """
    noms: dict[int, str] = {}
    executes = 0
    echecs: list[str] = []
    erreurs: list[str] = []
    tous: list[str] = []

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
            nom = noms.get(evenement.get("testID"), "<test inconnu>")
            tous.append(nom)
            if resultat != "success":
                echecs.append(nom)

    return executes, echecs, erreurs, tous


class ResultatFlutter:
    def __init__(self, code: int, sortie: str, erreur: str) -> None:
        self.code = code
        self.sortie = sortie
        self.erreur = erreur
        self.executes, self.echecs, self.erreurs, self.noms = lire_rapport(sortie)

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
        # Les noms des tests du dernier passage **reussi**. Ils servent a refuser
        # un marqueur qui ne designe aucun test — voir [cas].
        self.noms: list[str] = []

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

        # Les noms ne sont retenus que sur un passage **conforme**. Un passage
        # casse par une mutation rapporterait une liste tronquee, et les cas
        # suivants seraient alors refuses a tort.
        self.noms = mesure.noms
        return mesure

    def cas(self, libelle: str, marqueur: str, appliquer, attendu: bool = True) -> None:
        """Mesure un cas, apres avoir verifie que le marqueur designe un test.

        Un marqueur qui ne correspond a aucun nom de test ne peut **jamais**
        apparaitre dans le rapport. Deux consequences, toutes deux fausses :

          - `attendu=True` conclut « NON DETECTE » sur une faute que le controle
            attrape pourtant, et invite a corriger la mutation — c'est-a-dire a
            **retirer une faute reelle** ;
          - `attendu=False` valide un temoin negatif qui ne prouve rien, puisque
            son absence etait acquise d'avance.

        C'est la meme discipline que `Fichier.muter()`, qui leve quand son ancre
        ne correspond a rien : une mesure qui n'a pas eu lieu est une erreur du
        banc, pas un resultat.

        Le cas est **refuse** plutot que signale : un banc dont un cas ne mesure
        rien ne doit pas se declarer vert.
        """
        if self.noms and not any(marqueur in nom for nom in self.noms):
            print(f"\nBANC INVALIDE — cas « {libelle} »", file=sys.stderr)
            print(
                f"  le marqueur {marqueur!r} ne correspond a aucun des "
                f"{len(self.noms)} tests de {self.cible}.",
                file=sys.stderr,
            )
            print(
                "  Une mutation ne peut donc pas etre vue, dans un sens comme "
                "dans l'autre : corriger le marqueur, pas la mutation.",
                file=sys.stderr,
            )
            raise SystemExit(2)

        super().cas(libelle, marqueur, appliquer, attendu)
