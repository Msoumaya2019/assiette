#!/usr/bin/env python3
"""Falsifie le transport reel, vers Supabase.

Pourquoi ce banc existe
-----------------------
`transport_supabase.dart` est le **seul** endroit du projet ou les deux
vocabulaires se rencontrent : les noms du serveur, les noms du local, et les
trois familles de conversion. Tout le reste est eprouve sans lui — le service
contre un faux transport, la regle d'arbitrage sans base, la declaration sans
reseau. Ce fichier-la, donc, ne tombe que si on l'eprouve lui.

Ce que ses tests ont trouve avant meme que ce banc existe
---------------------------------------------------------
Deux defauts reels, tous les deux **silencieux**, et tous les deux invisibles a
un faux serveur ecrit trop gentiment :

  - **la casse de l'en-tete `Date`.** `http.Response.headers` est une table
    sensible a la casse, et le client y recopie le nom tel que le serveur l'a
    envoye — `Date`, avec sa majuscule, comme l'envoient les passerelles HTTP.
    Chercher `'date'` rendait donc `null` contre un vrai serveur, et l'ecart
    d'horloge disparaissait **sans un mot** : `ServiceSynchronisation._decalage`
    avale l'echec et rend `null`. Un diagnostic qui cesse de fonctionner sans le
    dire vaut moins que pas de diagnostic.
  - **`meals.photo_path` revenait du serveur.** Le contenu local ne porte pas
    cette colonne ; le contenu lu sur le serveur la portait, `null` aujourd'hui.
    Deux empreintes qui different a jamais pour une colonne dont la valeur n'a
    jamais eu a circuler : l'arbitrage designerait un gagnant a chaque passage,
    et chaque passage reecrirait la meme ligne. Une boucle sans erreur et sans
    fin.

Le premier cas de ce banc est la casse. Le huitieme est la colonne retenue.

Ce que ce banc refuse de falsifier, et pourquoi
-----------------------------------------------
  - **la borne de pages (`pagesMax`).** Une mutation qui la deplacerait ne se
    verrait qu'au bout d'un temps non borne : le controle teste fait deja deux
    cents tours, et une borne elargie le ferait tourner plus longtemps sans rien
    changer au verdict. Une mutation qui ne peut pas etre mesuree n'a rien a
    faire dans un banc.
  - **l'arret sur une page incomplete.** Un serveur honnete rend une page courte
    **parce qu'il n'a plus rien** : s'arreter la ou continuer jusqu'a la page
    vide donne alors le meme resultat, au prix d'une requete. Les deux regles
    sont justes, donc aucune faute ne se cache derriere l'une ou l'autre. Ce
    n'est pas un defaut a falsifier, c'est un choix — et il est ecrit.

Usage : python3 tools/bancs/falsifier_transport_supabase_dart.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, MesureImpossible  # noqa: E402
from banc_flutter import BancFlutter  # noqa: E402
from environnement_flutter import executable_flutter  # noqa: E402

TRANSPORT = "app/lib/services/transport_supabase.dart"
TESTS = "test/services/transport_supabase_test.dart"

# A mettre a jour en meme temps que le fichier de tests, jamais pour faire
# passer le banc.
TESTS_ATTENDUS = 23

# --- ancres : au niveau octet, telles que `dart format` les ecrit ---

# 1. L'en-tete du serveur, cherche sans egard a la casse.
ENTETE_SANS_CASSE = b"    final date = _entete(reponse, 'date');\n"
ENTETE_SENSIBLE_CASSE = b"    final date = reponse.headers['date'];\n"

# 2. La fenetre de lecture, qui doit avancer d'une page a l'autre.
FENETRE_QUI_AVANCE = b"            'Range': '$debut-${debut + lignesParPage - 1}',\n"
FENETRE_FIGEE = b"            'Range': '0-${lignesParPage - 1}',\n"

# 3. Le `206`, reponse normale d'une lecture bornee.
ACCEPTE_206 = b"      _verifier(reponse, acceptes: const {200, 206});\n"
REFUSE_206 = b"      _verifier(reponse, acceptes: const {200});\n"

# 4. Les deux familles de colonnes qui n'entrent pas dans le contenu.
HORS_CONTENU_SERVEUR = b"        ...?colonnesServeurSeules[tableDistante],\n"
HORS_CONTENU_LOCAL = (
    b"        for (final locale in colonnesLocalesSeulesDe(tableLocale))\n"
    b"          colonneDistante(tableLocale, locale),\n"
)

# 5. Le lien d'un aliment, exclu du contenu comme `contenuDe` l'exclut.
LIEN_EXCLU = b"      if (colonne == lien) continue;\n"

# 6. Les trois conversions descendantes.
CONVERSION_DATES_DESCENDANTE = (
    b"    if ((colonnesDatesDistantes[table] ?? const <String>{}).contains(locale)) {\n"
    b"      return millisecondesDepuisIso(valeur);\n"
    b"    }\n"
)
CONVERSION_BOOLEENS_DESCENDANTE = (
    b"    if ((colonnesBooleennesDistantes[table] ?? const <String>{}).contains(\n"
    b"      locale,\n"
    b"    )) {\n"
    b"      return valeur == true ? 1 : 0;\n"
    b"    }\n"
)
CONVERSION_JSON_DESCENDANTE = (
    b"    if ((colonnesJsonDistantes[table] ?? const <String>{}).contains(locale)) {\n"
    b"      return texteDepuisJson(valeur);\n"
    b"    }\n"
)

# 7. Le deuxieme passage : relire l'`uuid` avant de rattacher les aliments.
RELECTURE_UUID = b"    final uuidParCle = await _uuidDesRepas(cles);\n"
SANS_RELECTURE = b"    final uuidParCle = <String, String>{};\n"

# 8. Les identifiants, proteges dans la grammaire de `in.(...)`.
IDENTIFIANT_PROTEGE = (
    b"  String _identifiant(String valeur) =>\n"
    b"      '\"${valeur.replaceAll('\\\\', '\\\\\\\\').replaceAll('\"', '\\\\\"')}\"';\n"
)
IDENTIFIANT_NU = b"  String _identifiant(String valeur) => valeur;\n"

# 9. La contrainte d'unicite de l'`upsert`.
CONFLIT_COMPLET = (
    b"      'user_id,${colonneCleDistante(table.nom, table.colonneCle)}';\n"
)
CONFLIT_INCOMPLET = b"      'user_id';\n"

# 10. Les trois conversions montantes.
CONVERSION_DATE_MONTANTE = (
    b"      'updated_at': isoDepuisMillisecondes(ligne.updatedAt),\n"
)
DATE_NON_CONVERTIE = b"      'updated_at': ligne.updatedAt,\n"

# 11. La colonne retenue, qui ne part pas non plus.
COLONNE_RETENUE_NON_ECRITE = b"      if (localesSeules.contains(entree.key)) continue;\n"

# 12. La plomberie d'en-tetes et de pannes.
PREFER_TRANSMIS = (
    b"      if (resolution) 'Prefer': 'resolution=merge-duplicates,return=minimal',\n"
)
SESSION_REFUSEE = b"        throw const SessionRefuseeFailure();\n"
SESSION_CONFONDUE = b"        throw const MissingCredentialFailure();\n"
LIMITE_DEBIT = b"        throw const RateLimitFailure();\n"
LIMITE_CONFONDUE = b"        throw const InvalidResponseFailure();\n"
REESSAYABLE_SELON_STATUT = b"          isRetryable: reponse.statusCode >= 500,\n"
REESSAYABLE_TOUJOURS = b"          isRetryable: true,\n"
COUPURE_TRADUITE = (
    b"    } on http.ClientException {\n      throw const NetworkFailure();\n"
)
DELAI_BORNE = b"      return await requete().timeout(delai);\n"
DELAI_SANS_BORNE = b"      return await requete();\n"
CLIENT_INJECTE_EPARGNE = b"    if (!_clientFourni) _client.close();\n"
CLIENT_INJECTE_FERME = b"    _client.close();\n"

# --- temoin negatif : une reformulation legitime ---

COMMENTAIRE = (
    b"  /// Le decoupage se fait par l'en-tete `Range`, et non par `limit`/`offset` :\n"
)
COMMENTAIRE_REFORMULE = (
    b"  /// Le decoupage se fait par l'en-tete `Range`, plutot que `limit`/`offset` :\n"
)

# --- noms des tests qui doivent tomber -----------------------------------------
#
# Les marqueurs evitent l'apostrophe **et son echappement**. Le nom compare par
# le banc est celui du rapport JSON, donc la chaine **decodee** : dans le source
# du test, l'apostrophe s'ecrit `\'`, et un marqueur qui la traverserait ne
# correspondrait ni au source ni au nom decode. Mesure faite : cinq marqueurs
# ecrits d'abord avec leur apostrophe ne correspondaient a **rien**.

T_CASSE = "Date est lu quelle que soit sa casse"
T_PAGES = "les pages sont demandees par Range"
T_TYPES = "une ligne distante revient en vocabulaire local"
T_COLONNES_SERVEUR = "les colonnes du serveur n"
T_PHOTO_LUE = "appareil ne revient pas dans le contenu"
T_JSON = "un jsonb revient en texte local"
T_ALIMENTS = "les aliments se rattachent a leur repas"
T_UPSERT = "un repas part en upsert"
T_ISO = "les dates repartent en ISO"
T_PHOTO_ECRITE = "appareil ne part jamais"
T_DEUX_PASSAGES = "les aliments sont rattaches en deux passages"
T_GUILLEMETS = "les identifiants sont mis entre guillemets"
T_SESSION = "un 401 et un 403 sont une session refusee"
T_429 = "un 429 est une limite de debit"
T_RETRY = "un 500 est reessayable"
T_RESEAU = "une coupure reseau et un delai depasse sont traduits"
T_CLIENT = "client injecte n"


def principal() -> int:
    flutter = executable_flutter()
    if flutter is None:
        print(
            "flutter introuvable : ni dans le SDK local, ni dans le PATH.",
            file=sys.stderr,
        )
        return 2

    banc = BancFlutter(RACINE / TRANSPORT, flutter, TESTS, TESTS_ATTENDUS)

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

    def cas(libelle: str, marqueur: str, ancien: bytes, nouveau: bytes) -> None:
        banc.cas(
            libelle,
            marqueur,
            lambda: banc.suivre(TRANSPORT).muter(ancien, nouveau),
        )

    def sans(libelle: str, marqueur: str, ancien: bytes) -> None:
        cas(libelle, marqueur, ancien, b"")

    # --- l'heure du serveur ---
    cas(
        "l'en-tete est cherche avec sa casse",
        T_CASSE,
        ENTETE_SANS_CASSE,
        ENTETE_SENSIBLE_CASSE,
    )

    # --- la lecture ---
    cas(
        "la fenetre de lecture n'avance plus",
        T_PAGES,
        FENETRE_QUI_AVANCE,
        FENETRE_FIGEE,
    )
    cas("un 206 n'est plus accepte", T_PAGES, ACCEPTE_206, REFUSE_206)
    sans("les colonnes du serveur entrent dans le contenu", T_COLONNES_SERVEUR, HORS_CONTENU_SERVEUR)
    sans("la colonne retenue revient du serveur", T_PHOTO_LUE, HORS_CONTENU_LOCAL)
    sans("le lien d'un aliment entre dans son contenu", T_ALIMENTS, LIEN_EXCLU)
    sans("la date n'est plus convertie", T_TYPES, CONVERSION_DATES_DESCENDANTE)
    sans("le booleen n'est plus converti", T_TYPES, CONVERSION_BOOLEENS_DESCENDANTE)
    sans("le jsonb n'est plus converti", T_JSON, CONVERSION_JSON_DESCENDANTE)

    # --- l'ecriture ---
    sans("la colonne retenue part quand meme", T_PHOTO_ECRITE, COLONNE_RETENUE_NON_ECRITE)
    # Remplacement, et non retrait : supprimer la declaration laisserait ses
    # usages orphelins, et la mutation ne compilerait pas — elle ne mesurerait
    # donc rien. Mesure faite : ecrit d'abord en `sans`, ce cas a fait tomber le
    # banc sur « The getter 'uuidParCle' isn't defined ».
    cas(
        "le repas n'est plus relu",
        T_DEUX_PASSAGES,
        RELECTURE_UUID,
        SANS_RELECTURE,
    )
    cas(
        "les identifiants ne sont plus proteges",
        T_GUILLEMETS,
        IDENTIFIANT_PROTEGE,
        IDENTIFIANT_NU,
    )
    cas(
        "on_conflict ne porte plus la cle",
        T_UPSERT,
        CONFLIT_COMPLET,
        CONFLIT_INCOMPLET,
    )
    sans("Prefer n'est plus transmis", T_UPSERT, PREFER_TRANSMIS)
    cas(
        "la date d'ecriture n'est plus convertie",
        T_ISO,
        CONVERSION_DATE_MONTANTE,
        DATE_NON_CONVERTIE,
    )

    # --- les pannes ---
    cas(
        "une session refusee redevient une cle d'analyse",
        T_SESSION,
        SESSION_REFUSEE,
        SESSION_CONFONDUE,
    )
    cas("un 429 n'est plus une limite de debit", T_429, LIMITE_DEBIT, LIMITE_CONFONDUE)
    cas(
        "tout echec devient reessayable",
        T_RETRY,
        REESSAYABLE_SELON_STATUT,
        REESSAYABLE_TOUJOURS,
    )
    sans("la coupure reseau n'est plus traduite", T_RESEAU, COUPURE_TRADUITE)
    cas("le delai n'est plus borne", T_RESEAU, DELAI_BORNE, DELAI_SANS_BORNE)

    # --- le client ---
    cas(
        "le client injecte est ferme",
        T_CLIENT,
        CLIENT_INJECTE_EPARGNE,
        CLIENT_INJECTE_FERME,
    )

    # --- temoin negatif ---
    banc.cas(
        "commentaire reformule",
        T_PAGES,
        lambda: banc.suivre(TRANSPORT).muter(COMMENTAIRE, COMMENTAIRE_REFORMULE),
        attendu=False,
    )

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
        "vert — le transport tombe sur chacune de ses vingt et une fautes, et "
        "pas sur une reformulation."
    )
    return 0


if __name__ == "__main__":
    sys.exit(principal())
