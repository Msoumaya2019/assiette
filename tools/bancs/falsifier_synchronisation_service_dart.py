#!/usr/bin/env python3
"""Falsifie le service de synchronisation, c'est-a-dire la couche qui relie.

Ce que ce banc vise
-------------------
Le service fait converger deux bases. Trois fautes le rendraient faux **sans
que rien ne le signale**, et ce sont les trois premieres de ce banc :

1. **Redater la ligne appliquee.** Une ligne transporte sa date ; la refabriquer
   avec l'horloge locale fait de chaque passage une modification. Deux appareils
   se renverraient alors la meme ligne sans fin, chacun trouvant l'autre plus
   recent. Le defaut ne se voit pas sur un appareil seul — il faut deux
   appareils, et un troisieme passage pour qu'il se montre.

2. **Recopier le serveur au lieu d'arbitrer.** Ecrire tout ce qui arrive ecrase
   la version que l'appareil venait de gagner. Elle est renvoyee juste apres,
   donc l'etat final est juste : c'est ce qui rend la faute discrete. Ce qui est
   faux, c'est l'intervalle — et une application qui s'arrete la perd. Le
   rapport, lui, annonce zero ligne appliquee alors qu'il en a ecrit.

3. **Laisser une table en panne emporter les autres.** Une table refusee par le
   serveur ne doit pas empecher les cinq autres de converger.

L'ecart d'horloge est mesure, signale **et retenu**. Deux cas visent la mesure —
au milieu de l'aller-retour, et inconnu quand le serveur ne sait pas donner
l'heure, jamais tenu pour nul — et deux autres visent la correction elle-meme :

4. **Ne jamais retenir la correction.** Le diagnostic reste juste et **rien ne
   change** : le rapport annonce l'ecart, l'interface l'affiche, et les
   modifications continuent d'etre estampillees avec l'horloge fausse. C'est la
   faute la plus discrete du fichier, parce que tout ce qui se voit reste vrai.

5. **Mesurer l'ecart sur l'horloge corrigee.** L'ecart rend alors zero des que la
   correction est appliquee : l'appareil se declare juste au deuxieme passage, et
   la correction s'annule elle-meme. Le premier passage, lui, est parfaitement
   juste — d'ou un test qui synchronise **deux fois**.

Le dernier cas est le temoin negatif : une reformulation de commentaire ne doit
rien faire tomber.

Usage : python3 tools/bancs/falsifier_synchronisation_service_dart.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, MesureImpossible  # noqa: E402
from banc_flutter import BancFlutter  # noqa: E402
from environnement_flutter import executable_flutter  # noqa: E402

SERVICE = "app/lib/services/synchronisation_service.dart"
TESTS = "test/services/synchronisation_service_test.dart"

# A mettre a jour en meme temps que le fichier de tests, jamais pour faire
# passer le banc.
TESTS_ATTENDUS = 22

# --- ancres : au niveau octet, telles que `dart format` les ecrit ---

APPLICATION_ARBITREE = (
    b"      if (plan.aAppliquer.isNotEmpty) {\n"
    b"        // Une transaction : une table a moitie ecrite serait un etat que\n"
    b"        // personne n'a jamais produit, et que le prochain passage devrait\n"
    b"        // demeler.\n"
    b"        await db.transaction((transaction) async {\n"
    b"          for (final ligne in plan.aAppliquer) {\n"
    b"            await ecrireLigne(transaction, table, ligne);\n"
    b"          }\n"
    b"        });\n"
    b"      }\n"
)
LIGNE_REDATEE = (
    b"      if (plan.aAppliquer.isNotEmpty) {\n"
    b"        await db.transaction((transaction) async {\n"
    b"          for (final ligne in plan.aAppliquer) {\n"
    b"            await ecrireLigne(\n"
    b"              transaction,\n"
    b"              table,\n"
    b"              LigneSynchronisable(\n"
    b"                cle: ligne.cle,\n"
    b"                updatedAt: horloge.maintenantMs(),\n"
    b"                deletedAt: ligne.deletedAt,\n"
    b"                contenu: ligne.contenu,\n"
    b"              ),\n"
    b"            );\n"
    b"          }\n"
    b"        });\n"
    b"      }\n"
)
SERVEUR_RECOPIE = (
    b"      if (distantes.isNotEmpty) {\n"
    b"        await db.transaction((transaction) async {\n"
    b"          for (final ligne in distantes) {\n"
    b"            await ecrireLigne(transaction, table, ligne);\n"
    b"          }\n"
    b"        });\n"
    b"      }\n"
)

TABLE_EN_PANNE = (
    b"    } on Object catch (erreur) {\n"
    b"      return RapportTable(erreur: erreur);\n"
    b"    }\n"
)
TABLE_EN_PANNE_EMPORTE_TOUT = (
    b"    } on Object catch (erreur) {\n"
    b"      throw erreur;\n"
    b"    }\n"
)

ECART_MILIEU = b"      final milieu = avant + (apres - avant) ~/ 2;\n"
ECART_APRES = b"      final milieu = apres;\n"

ECART_INCONNU = b"    final decalage = await _decalage();\n"
ECART_INCONNU_TENU_POUR_NUL = b"    final decalage = (await _decalage()) ?? 0;\n"

# La correction, et les deux facons de la perdre.
#
# `CORRECTION_RETENUE` est l'appel qui range l'ecart mesure dans l'horloge. Sans
# lui, le diagnostic reste juste et **rien ne change** : le rapport annonce
# toujours l'ecart, l'interface l'affiche, et les modifications continuent d'etre
# estampillees avec l'horloge fausse. C'est la faute la plus discrete du fichier,
# parce que tout ce qui se voit reste vrai.
CORRECTION_RETENUE = b"    await horloge.corriger(mesure);\n"
CORRECTION_OMISE = b""

# La mesure de l'ecart se fait sur l'horloge **brute**. La faire sur l'horloge
# corrigee rend zero des que la correction est appliquee : l'appareil se declare
# juste au deuxieme passage, et la correction s'annule elle-meme.
ECART_SUR_HORLOGE_BRUTE = (
    b"      final avant = horloge.brutMs();\n"
    b"      final serveur = await transport.heureServeur();\n"
    b"      final apres = horloge.brutMs();\n"
)
ECART_SUR_HORLOGE_CORRIGEE = (
    b"      final avant = horloge.maintenantMs();\n"
    b"      final serveur = await transport.heureServeur();\n"
    b"      final apres = horloge.maintenantMs();\n"
)

BOUCLE_DES_TABLES = b"    for (final table in tablesSynchronisables) {\n"
BOUCLE_ELARGIE = (
    b"    for (final table in [\n"
    b"      ...tablesSynchronisables,\n"
    b"      const TableSynchronisable(nom: 'settings', colonneCle: 'key'),\n"
    b"    ]) {\n"
)

COMMENTAIRE = (
    b"  /// L'ecart entre l'horloge de l'appareil et celle du serveur, mesure puis\n"
)
COMMENTAIRE_REFORMULE = (
    b"  /// L'ecart mesure entre l'horloge de l'appareil et celle du serveur, puis\n"
)

# --- noms des tests qui doivent tomber -----------------------------------------

T_REDATE = "les dates traversees ne sont pas reecrites"
T_ECRASE = "une ligne que l'appareil gagne n'est pas ecrasee par la version distante"
T_PANNE = "la table en echec est nommee, les autres passent"
T_MILIEU = "l'ecart est mesure au milieu de l'aller-retour"
T_INCONNU = "un serveur qui ne donne pas l'heure laisse l'ecart inconnu, sans bloquer"
T_HORS_ENSEMBLE = "les tables hors de l'ensemble ne sont jamais visitees"
T_PERSISTE = "un ecart mesure survit a la fermeture de la base"
T_SANS_ANNULATION = "un deuxieme passage ne remet pas l'ecart a zero"


def principal() -> int:
    flutter = executable_flutter()
    if flutter is None:
        print(
            "flutter introuvable : ni dans le SDK local, ni dans le PATH.",
            file=sys.stderr,
        )
        return 2

    banc = BancFlutter(RACINE / SERVICE, flutter, TESTS, TESTS_ATTENDUS)

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

    def ligne_redatee() -> None:
        banc.suivre(SERVICE).muter(APPLICATION_ARBITREE, LIGNE_REDATEE)

    def serveur_recopie() -> None:
        banc.suivre(SERVICE).muter(APPLICATION_ARBITREE, SERVEUR_RECOPIE)

    def table_en_panne_emporte_tout() -> None:
        banc.suivre(SERVICE).muter(TABLE_EN_PANNE, TABLE_EN_PANNE_EMPORTE_TOUT)

    def ecart_mesure_apres() -> None:
        banc.suivre(SERVICE).muter(ECART_MILIEU, ECART_APRES)

    def ecart_inconnu_tenu_pour_nul() -> None:
        banc.suivre(SERVICE).muter(ECART_INCONNU, ECART_INCONNU_TENU_POUR_NUL)

    def table_sans_cycle_de_vie_visitee() -> None:
        banc.suivre(SERVICE).muter(BOUCLE_DES_TABLES, BOUCLE_ELARGIE)

    def correction_omise() -> None:
        banc.suivre(SERVICE).muter(CORRECTION_RETENUE, CORRECTION_OMISE)

    def ecart_mesure_sur_horloge_corrigee() -> None:
        banc.suivre(SERVICE).muter(
            ECART_SUR_HORLOGE_BRUTE, ECART_SUR_HORLOGE_CORRIGEE
        )

    def commentaire_reformule() -> None:
        banc.suivre(SERVICE).muter(COMMENTAIRE, COMMENTAIRE_REFORMULE)

    banc.cas("ligne appliquee redatee", T_REDATE, ligne_redatee)
    banc.cas("serveur recopie au lieu d'arbitrer", T_ECRASE, serveur_recopie)
    banc.cas("table en panne qui emporte tout", T_PANNE, table_en_panne_emporte_tout)
    banc.cas("ecart mesure apres l'aller-retour", T_MILIEU, ecart_mesure_apres)
    banc.cas("ecart inconnu tenu pour nul", T_INCONNU, ecart_inconnu_tenu_pour_nul)
    banc.cas(
        "table sans cycle de vie visitee",
        T_HORS_ENSEMBLE,
        table_sans_cycle_de_vie_visitee,
    )
    banc.cas("correction d'horloge jamais retenue", T_PERSISTE, correction_omise)
    banc.cas(
        "ecart mesure sur l'horloge corrigee",
        T_SANS_ANNULATION,
        ecart_mesure_sur_horloge_corrigee,
    )
    banc.cas("commentaire reformule", T_REDATE, commentaire_reformule, attendu=False)

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
        "vert — le service tombe sur chacune de ses huit fautes, et pas sur une "
        "reformulation."
    )
    return 0


if __name__ == "__main__":
    sys.exit(principal())
