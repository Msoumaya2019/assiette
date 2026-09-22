#!/usr/bin/env python3
"""Falsifie l'horloge corrigee par le serveur.

Ce que ce banc vise
-------------------
L'horloge decide de la date que porte **chaque** modification, et cette date
decide de quel appareil gagne quand deux versions d'une meme ligne se
rencontrent. Une horloge corrigee a l'envers perd des donnees sans rien
signaler. Six fautes, toutes muettes :

1. **Ne pas appliquer la correction.** `maintenantMs` rend l'horloge de
   l'appareil. Tout le reste reste juste — l'ecart est mesure, signale, range —
   et les modifications continuent d'etre estampillees faux.

2. **Corriger aussi l'horloge brute.** C'est le piege principal du fichier, et il
   est symetrique du precedent : la mesure de l'ecart se fait sur `brutMs`. Si
   `brutMs` rendait deja l'heure corrigee, l'ecart vaudrait zero a chaque
   mesure, et une horloge franchement fausse se declarerait juste.

3. **Corriger sous la resolution de la mesure.** L'heure du serveur vient d'un
   en-tete HTTP, precis a la seconde : un ecart de 900 ms ne se distingue pas
   d'une horloge juste. Le corriger decale chaque estampille d'une seconde tiree
   au hasard. Appliquer du bruit n'est pas corriger.

4. **Jeter la mesure quand elle est inconnue.** Une coupure reseau sur l'appel
   d'heure remettrait l'ecart a zero, donc l'appareil a son horloge fausse — au
   moment ou l'on s'y attend le moins.

5. **Reecrire l'ecart a chaque passage.** Un appareil juste mesure zero, et
   reecrit zero : une ecriture pour rien a chaque synchronisation.

6. **Ne pas noter ce qui est deja range.** `reprendre` applique l'ecart lu mais
   ne le marque pas comme range, donc la premiere mesure identique le reecrit.

Le dernier cas est le temoin negatif : une reformulation de commentaire ne doit
rien faire tomber.

Usage : python3 tools/bancs/falsifier_horloge_dart.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, MesureImpossible  # noqa: E402
from banc_flutter import BancFlutter  # noqa: E402
from environnement_flutter import executable_flutter  # noqa: E402

HORLOGE = "app/lib/core/horloge.dart"
TESTS = "test/core/horloge_test.dart"

# A mettre a jour en meme temps que le fichier de tests, jamais pour faire
# passer le banc.
TESTS_ATTENDUS = 9

# --- ancres : au niveau octet, telles que `dart format` les ecrit ---

HEURE_ESTAMPILLEE = b"  int maintenantMs() => brutMs() + _decalageMs;\n"
HEURE_ESTAMPILLEE_SANS_CORRECTION = b"  int maintenantMs() => brutMs();\n"

HEURE_BRUTE = b"  int brutMs() => _source().millisecondsSinceEpoch;\n"
HEURE_BRUTE_CORRIGEE = (
    b"  int brutMs() => _source().millisecondsSinceEpoch + _decalageMs;\n"
)

ZONE_MORTE = (
    b"      _decalageMs = decalageMs.abs() < ecartMesurableMs ? 0 : decalageMs;\n"
)
ZONE_MORTE_ABSENTE = b"      _decalageMs = decalageMs;\n"

ECART_INCONNU_CONSERVE = (
    b"    if (decalageMs != null) {\n"
    b"      _decalageMs = decalageMs.abs() < ecartMesurableMs ? 0 : decalageMs;\n"
    b"    }\n"
)
ECART_INCONNU_JETE = (
    b"    _decalageMs = decalageMs == null || decalageMs.abs() < ecartMesurableMs\n"
    b"        ? 0\n"
    b"        : decalageMs;\n"
)

ECRITURE_SEULEMENT_SI_CHANGEMENT = (
    b"    if (retenir == null || _retenu == _decalageMs) return;\n"
)
ECRITURE_A_CHAQUE_FOIS = b"    if (retenir == null) return;\n"

REPRENDRE_NOTE_LE_RANGE = (
    b"  void reprendre(int? decalageMs) {\n"
    b"    _decalageMs = decalageMs ?? 0;\n"
    b"    _retenu = _decalageMs;\n"
    b"  }\n"
)
REPRENDRE_SANS_NOTER = (
    b"  void reprendre(int? decalageMs) {\n"
    b"    _decalageMs = decalageMs ?? 0;\n"
    b"  }\n"
)

COMMENTAIRE = b"/// En deca de cet ecart, on ne corrige pas : l'ecart est indiscernable de zero.\n"
COMMENTAIRE_REFORMULE = (
    b"/// Sous cet ecart, on ne corrige pas : l'ecart est indiscernable de zero.\n"
)

# --- noms des tests qui doivent tomber -----------------------------------------

T_CORRECTION = "une correction deplace l'heure estampillee, pas l'horloge brute"
T_ZONE_MORTE = "un ecart sous la resolution de la mesure n'est pas applique"
T_INCONNU = "un ecart inconnu conserve la correction precedente"
T_ECRITURE = "un ecart change est range, un ecart identique ne l'est pas"
T_REPRENDRE = "reprendre applique un ecart range sans le reecrire"


def principal() -> int:
    flutter = executable_flutter()
    if flutter is None:
        print(
            "flutter introuvable : ni dans le SDK local, ni dans le PATH.",
            file=sys.stderr,
        )
        return 2

    banc = BancFlutter(RACINE / HORLOGE, flutter, TESTS, TESTS_ATTENDUS)

    try:
        initial = banc.executer()
    except MesureImpossible as erreur:
        print(f"la suite de tests ne tourne pas : {erreur}", file=sys.stderr)
        return 2

    print(
        f"etat initial : code {initial.code}, {initial.executes} test(s) execute(s), "
        f"{len(initial.echecs)} en echec"
    )
    if initial.code != 0:
        print(initial.sortie[-3000:], file=sys.stderr)
        print(initial.erreur[-2000:], file=sys.stderr)
        print("les tests echouent deja avant toute mutation.", file=sys.stderr)
        return 2

    def correction_non_appliquee() -> None:
        banc.suivre(HORLOGE).muter(HEURE_ESTAMPILLEE, HEURE_ESTAMPILLEE_SANS_CORRECTION)

    def horloge_brute_corrigee() -> None:
        banc.suivre(HORLOGE).muter(HEURE_BRUTE, HEURE_BRUTE_CORRIGEE)

    def zone_morte_absente() -> None:
        banc.suivre(HORLOGE).muter(ZONE_MORTE, ZONE_MORTE_ABSENTE)

    def ecart_inconnu_jete() -> None:
        banc.suivre(HORLOGE).muter(ECART_INCONNU_CONSERVE, ECART_INCONNU_JETE)

    def ecriture_a_chaque_fois() -> None:
        banc.suivre(HORLOGE).muter(
            ECRITURE_SEULEMENT_SI_CHANGEMENT, ECRITURE_A_CHAQUE_FOIS
        )

    def reprendre_sans_noter() -> None:
        banc.suivre(HORLOGE).muter(REPRENDRE_NOTE_LE_RANGE, REPRENDRE_SANS_NOTER)

    def commentaire_reformule() -> None:
        banc.suivre(HORLOGE).muter(COMMENTAIRE, COMMENTAIRE_REFORMULE)

    banc.cas("correction jamais appliquee", T_CORRECTION, correction_non_appliquee)
    banc.cas("horloge brute deja corrigee", T_CORRECTION, horloge_brute_corrigee)
    banc.cas("correction sous la resolution", T_ZONE_MORTE, zone_morte_absente)
    banc.cas("ecart inconnu jete", T_INCONNU, ecart_inconnu_jete)
    banc.cas("ecriture a chaque passage", T_ECRITURE, ecriture_a_chaque_fois)
    banc.cas("reprendre sans noter", T_REPRENDRE, reprendre_sans_noter)
    banc.cas("commentaire reformule", T_CORRECTION, commentaire_reformule, attendu=False)

    code = banc.tableau()

    try:
        final = banc.executer()
    except MesureImpossible as erreur:
        print(f"\nla suite de tests ne tourne plus : {erreur}", file=sys.stderr)
        return 1

    print(
        f"\netat final : code {final.code}, {final.executes} test(s) execute(s), "
        f"{len(final.echecs)} en echec"
    )
    if final.code != 0:
        print(final.sortie[-2000:], file=sys.stderr)
        return 1

    if code != 0:
        return code

    print(
        "vert — l'horloge tombe sur chacune de ses six fautes, et pas sur une "
        "reformulation."
    )
    return 0


if __name__ == "__main__":
    sys.exit(principal())
