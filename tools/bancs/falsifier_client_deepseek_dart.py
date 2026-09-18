#!/usr/bin/env python3
"""Falsifie les tests du client DeepSeek cote application.

Le client Dart transmettait sa requete sans le champ `thinking`. Or le mode
reflexion est actif par defaut cote fournisseur, ses jetons sont factures comme
des jetons de sortie, et il rend `temperature` inoperant. Le defaut etait donc
paye a chaque analyse, dans le mode que l'application utilise par defaut.

Ce banc restaure le defaut exact, puis chacun de ses voisins, et verifie que les
tests tombent.

Deux pieges de lecture, tous deux fermes ici
--------------------------------------------

1. Les noms des tests **reussis** apparaissent aussi dans la sortie de
   `flutter test`. Chercher le nom dans le texte brut conclurait « detecte » sans
   qu'aucun test ne tombe. Le rapport JSON est donc lu, et seuls les tests dont
   `result` vaut `failure` sont retenus.

2. Une mutation qui casse la compilation rend un code de sortie non nul **sans
   aucun test en echec**. Un banc qui ne distingue pas les deux conclut
   « non detecte » sur une mutation qui n'a jamais ete mesuree — c'est arrive :
   retirer le champ en laissant la virgule produisait `'',` dans le map, le
   fichier ne compilait plus, et le banc annoncait un trou de couverture la ou
   il n'y avait qu'une mutation fautive. D'ou le comptage des tests executes.

Usage : python3 tools/bancs/falsifier_client_deepseek_dart.py
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from banc import RACINE, Banc, MesureImpossible  # noqa: E402
from environnement_flutter import executable_flutter, environnement_mesure  # noqa: E402

CLIENT = "app/lib/data/vision/deepseek_provider.dart"
TESTS = "test/data/deepseek_provider_test.dart"

# Nombre de tests visibles du fichier cible. Sert de garde : si les tests n'ont
# pas pu tourner, ce total n'est pas atteint. A mettre a jour en meme temps que
# le fichier de tests, jamais pour faire passer le banc.
TESTS_ATTENDUS = 9

# --- ancres : au niveau octet ----------------------------------------------------
#
# Retirer une entree d'un map exige de retirer **la ligne entiere**, virgule
# comprise : ne retirer que la paire laisserait `'',` et casserait la
# compilation. Les fichiers du projet sont en LF, donc l'ancre peut porter la fin
# de ligne — mais uniquement pour les mutations qui doivent retirer la ligne.

LIGNE_REFLEXION_ENTIERE = b"      'thinking': {'type': thinking ? 'enabled' : 'disabled'},\n"
LIGNE_REFLEXION = b"'thinking': {'type': thinking ? 'enabled' : 'disabled'},"
REFLEXION_INVERSEE = b"'thinking': {'type': thinking ? 'disabled' : 'enabled'},"
LIGNE_AUTORISATION = b"'Authorization': 'Bearer $apiKey',"
DETAIL = b"'detail': 'high',"
DETAIL_BAS = b"'detail': 'low',"
SECOND_BLOC = b"if (request.hasSecondImage) {"
SECOND_BLOC_MORT = b"if (false) {"
CLE_REFUSEE = b"throw const MissingCredentialFailure(rejected: true);"
CLE_REFUSEE_SANS_MARQUE = b"throw const MissingCredentialFailure();"

# --- noms des tests qui doivent tomber -------------------------------------------

T_REFLEXION = "le mode reflexion est desactive et la temperature transmise"
T_ENTETE = "la cle part en en-tete et jamais dans le corps"
T_IMAGE = "l'image part en data URL et le texte precede l'image"
T_SECONDE = "une seconde image ajoute un second bloc"
T_401 = "un 401 est signale comme cle refusee, sans reessai"


def _lire_rapport(sortie: str) -> tuple[int, list[str]]:
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
        self.executes, self.echecs = _lire_rapport(sortie)

    @property
    def texte(self) -> str:
        return "\n".join(self.echecs) + "\n" + self.erreur


class BancDart(Banc):
    """Le banc des controles compare des marqueurs ; celui-ci compare des tests."""

    def __init__(self, script: Path, flutter: Path) -> None:
        super().__init__(script)
        self.flutter = flutter

    def executer(self) -> ResultatFlutter:  # type: ignore[override]
        resultat = subprocess.run(
            [str(self.flutter), "test", TESTS, "--reporter", "json"],
            cwd=RACINE / "app",
            env=environnement_mesure(),
            capture_output=True,
            text=True,
            check=False,
        )
        mesure = ResultatFlutter(resultat.returncode, resultat.stdout, resultat.stderr)

        if mesure.executes != TESTS_ATTENDUS:
            raise MesureImpossible(
                f"{mesure.executes} test(s) execute(s), {TESTS_ATTENDUS} attendu(s) : "
                "les tests n'ont pas pu tourner. Compilation cassee par la mutation, "
                "ou total a mettre a jour si le fichier de tests a change."
            )

        if resultat.returncode != 0 and not mesure.echecs:
            raise MesureImpossible(
                "code de sortie non nul sans aucun test en echec identifie."
            )

        return mesure


def principal() -> int:
    flutter = executable_flutter()
    if flutter is None:
        print("flutter introuvable : ni dans le SDK local, ni dans le PATH.", file=sys.stderr)
        return 2

    banc = BancDart(RACINE / CLIENT, flutter)

    try:
        initial = banc.executer()
    except MesureImpossible as erreur:
        print(f"la suite de tests ne tourne pas : {erreur}", file=sys.stderr)
        return 2

    print(f"etat initial : code {initial.code}, {initial.executes} test(s) execute(s), "
          f"{len(initial.echecs)} en echec")
    if initial.code != 0:
        print(initial.sortie[-3000:], file=sys.stderr)
        print(initial.erreur[-2000:], file=sys.stderr)
        print("les tests echouent deja avant toute mutation.", file=sys.stderr)
        return 2

    def reflexion_absente() -> None:
        # Le defaut d'origine : le champ n'est pas transmis du tout, le
        # fournisseur applique donc son mode reflexion par defaut.
        banc.suivre(CLIENT).muter(LIGNE_REFLEXION_ENTIERE, b"")

    def reflexion_activee() -> None:
        banc.suivre(CLIENT).muter(LIGNE_REFLEXION, REFLEXION_INVERSEE)

    def autorisation_sans_schema() -> None:
        banc.suivre(CLIENT).muter(LIGNE_AUTORISATION, b"'Authorization': '$apiKey',")

    def detail_abaisse() -> None:
        # Le detail pilote le nombre de jetons consommes par l'image.
        banc.suivre(CLIENT).muter(DETAIL, DETAIL_BAS, occurrences=1)

    def seconde_image_ignoree() -> None:
        banc.suivre(CLIENT).muter(SECOND_BLOC, SECOND_BLOC_MORT, occurrences=1)

    def refus_non_marque() -> None:
        banc.suivre(CLIENT).muter(CLE_REFUSEE, CLE_REFUSEE_SANS_MARQUE)

    banc.cas("champ thinking retire", T_REFLEXION, reflexion_absente)
    banc.cas("reflexion activee", T_REFLEXION, reflexion_activee)
    banc.cas("entete sans Bearer", T_ENTETE, autorisation_sans_schema)
    banc.cas("detail high devenu low", T_IMAGE, detail_abaisse)
    banc.cas("seconde image ignoree", T_SECONDE, seconde_image_ignoree)
    banc.cas("401 non marque comme refus", T_401, refus_non_marque)

    code = banc.tableau()

    try:
        final = banc.executer()
    except MesureImpossible as erreur:
        print(f"\nla suite de tests ne tourne plus : {erreur}", file=sys.stderr)
        return 1

    print(f"\netat final : code {final.code}, {final.executes} test(s) execute(s), "
          f"{len(final.echecs)} en echec")
    if final.code != 0:
        print(final.sortie[-2000:], file=sys.stderr)
        return 1

    if code != 0:
        return code

    print("vert — chaque defaut est detecte, et les tests repassent.")
    return 0


if __name__ == "__main__":
    sys.exit(principal())
