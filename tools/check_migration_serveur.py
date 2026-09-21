#!/usr/bin/env python3
"""Tient l'accord entre le schema local (SQLite) et le schema serveur (Supabase).

Pourquoi ce controle existe
---------------------------

La meme verite est ecrite a deux endroits qui ne peuvent pas se lire :
`app/lib/data/local/app_database.dart` decrit ce que l'application stocke, et
`backend/supabase/migrations/*.sql` decrit ce que le serveur acceptera un jour.
Rien ne relie les deux.

Le 21 septembre, la comparaison a ete faite a la main et le serveur etait **en
retard** : il ne connaissait ni les portions nommees, ni les pesees, ni les
mensurations. Aucune erreur ne se declenchait, parce que rien ne lit ce schema
aujourd'hui — mais le jour ou la synchronisation serait branchee, tout le suivi
du poids et toutes les portions auraient ete perdus **en silence**, chez
l'utilisateur, sur des donnees qu'il avait saisies.

Un retard de schema ne se voit pas : les deux cotes restent valides, les tests
passent, et le defaut n'apparait qu'a l'usage. C'est exactement le motif que ce
controle ferme.

Ce qu'il tient
--------------

1. **Chaque colonne locale a une destination serveur.** La correspondance est
   declaree dans `app/lib/data/distant/correspondance_distant.dart`, ou le
   transport la lira — c'est elle qui porte les renommages (`poids_kg` vers
   `weight_kg`, `payload_json` vers `payload`) et les changements de table
   (`templates` vers `meal_templates`). Ce fichier la **lit**, il ne la
   recopie pas : deux copies de la meme verite ne se relisent jamais. Une
   colonne sans destination est un defaut nomme, pas une devinette.
2. **L'ensemble des tables locales est clos.** Ajouter une table au schema
   local fait echouer ce controle tant qu'elle n'a pas ete prise en compte. Un
   accord verifie entre A et B ne dit rien le jour ou C apparait.
3. **L'ensemble des colonnes serveur sans equivalent local est clos aussi.**
   Un `id` de serveur, un `user_id` ou un `total_carbs_g` denormalise sont
   normaux ; un `user_id` oublie ne l'est pas. Les deux sens sont declares.
4. **Les politiques RLS sont rejouables** — chaque `create policy` a son
   `drop policy if exists` — **et le lecteur qui les compte n'est pas aveugle.**

Le troisieme point a une histoire, et elle justifie la forme du controle
-----------------------------------------------------------------------

Un validateur de syntaxe ecrit plus tot annoncait, sur `0001_init.sql` :

    Politiques : 0 | tables : 6
    [OK] forme rejouable : chaque politique a son drop

Le fichier porte **six** politiques. Le motif de lecture exigeait un retour a la
ligne entre le nom de la politique et `on` ; aucune des six n'en a. Le lecteur
n'en voyait donc zero, la boucle de verification ne s'executait pas, et le
verdict etait **vert en n'ayant rien mesure**. Il l'etait depuis le premier
jour.

C'est pourquoi chaque lecteur de ce fichier est double d'un **comptage brut
independant** : le nombre d'occurrences du texte `create policy`, sans motif
elabore. Si le lecteur voit moins que le comptage brut, le controle echoue — et
c'est le comptage brut qui l'emporte. Un controle qui ne peut rien affirmer
doit echouer, pas passer.

Ce que ce controle ne fait pas
------------------------------

Il ne **prouve pas** que la migration s'execute. Il lit du texte. L'execution
reelle contre un PostgreSQL est mesuree separement, par
`tools/eprouver_migration_sur_postgres.mjs`, et le resultat est consigne dans
`backend/README.md`. Un controle de forme ne remplace pas une mesure du reel.

Usage : python tools/check_migration_serveur.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
MIGRATIONS = RACINE / "backend" / "supabase" / "migrations"
BASE_LOCALE = RACINE / "app" / "lib" / "data" / "local" / "app_database.dart"
SOURCE_DART = RACINE / "app" / "lib"

# ---------------------------------------------------------------------------
# La correspondance, lue a la source
#
# Elle est declaree **une seule fois**, en Dart, dans
# `app/lib/data/distant/correspondance_distant.dart` — c'est la que le transport
# la lira. La recopier ici creerait deux verites que rien ne relierait, et c'est
# exactement le defaut que ce controle existe pour fermer.
#
# Ce fichier la **lit**, avec un lecteur strict : une declaration introuvable,
# ou un nombre d'entrees sous un plancher, fait echouer le controle au lieu de
# rendre un vert qui ne prouverait rien. Meme discipline que le comptage brut
# des politiques, et pour la meme raison : le 21 septembre, un lecteur trop
# exigeant a rendu « 0 politique » sur un fichier qui en portait six, et le
# verdict etait vert en n'ayant rien mesure.
# ---------------------------------------------------------------------------

CORRESPONDANCE = (
    RACINE / "app" / "lib" / "data" / "distant" / "correspondance_distant.dart"
)

# Planchers de lecture, avec une **marge volontaire**.
#
# Leur role est d'attraper un lecteur qui ne trouve presque rien — pas de se
# substituer au controle d'accord. Un plancher pose a la valeur exacte (14
# renommages, 7 tables) fait exactement l'inverse : retirer **une** entree de la
# declaration declenche le plancher, qui sort avant que l'accord ne soit
# verifie. Le banc l'a montre — deux cas « non detecte » alors que la faute
# etait bien la, mais signalee par la mauvaise porte, avec un message qui ne
# nommait pas la colonne perdue.
#
# La marge est donc ce qui rend les deux garde-fous complementaires : le
# plancher voit l'aveuglement, l'accord voit l'oubli d'une entree.
MIN_TABLES_DECLAREES = 5
MIN_RENOMMAGES = 10
MIN_TABLES_SERVEUR_SEULES = 5
MIN_TABLES_ENTIEREMENT_SERVEUR = 1


def _sans_commentaires_dart(texte: str) -> str:
    """Retire les commentaires `//` avant toute lecture.

    Sans cela, une apostrophe de prose — « l'identifiant du telephone » — se
    lirait comme une chaine, et le lecteur pourrait apparier deux morceaux de
    commentaires en croyant lire une entree. Aucun `//` de ce fichier ne figure
    dans une chaine : le retrait est donc sans perte.
    """
    return re.sub(r"//[^\n]*", "", texte)


def _corps_declaration(texte: str, nom: str) -> str:
    """Le corps d'une declaration `const ... nom = { ... };` de niveau racine.

    Le motif accepte les deux formes que `dart format` produit : une accolade
    fermante seule sur sa ligne, pour une table ou un ensemble long, et une
    declaration tenant sur une ligne, pour un ensemble court. Aucun corps ne
    contient `};` : les sous-ensembles se terminent par `},`.
    """
    motif = re.compile(rf"^const\s+[^\n=]*\b{nom}\s*=\s*\{{(.*?)\}};", re.S | re.M)
    trouve = motif.search(texte)
    if trouve is None:
        raise SystemExit(
            f"declaration `{nom}` introuvable dans {CORRESPONDANCE} : "
            "le controle ne peut rien verifier."
        )
    return trouve.group(1)


def _paires_de_textes(corps: str) -> dict[str, str]:
    """`'cle': 'valeur',` -> dictionnaire."""
    return dict(re.findall(r"'([^']+)'\s*:\s*'([^']*)'", corps))


def _paires_denombres(corps: str) -> dict[str, set[str]]:
    """`'cle': {'a', 'b'},` -> dictionnaire d'ensembles."""
    return {
        cle: set(re.findall(r"'([^']+)'", contenu))
        for cle, contenu in re.findall(r"'([^']+)'\s*:\s*\{([^}]*)\}", corps, re.S)
    }


def lire_correspondance() -> tuple[
    dict[str, str], dict[str, str], dict[str, set[str]], set[str]
]:
    """Lit la correspondance declaree cote Dart, et refuse d'en lire trop peu."""
    try:
        texte = _sans_commentaires_dart(CORRESPONDANCE.read_text(encoding="utf-8"))
    except OSError as erreur:
        raise SystemExit(f"correspondance illisible : {erreur}") from erreur

    tables = _paires_de_textes(_corps_declaration(texte, "tablesDistantes"))
    renommages = _paires_de_textes(_corps_declaration(texte, "renommagesDistants"))
    seules = _paires_denombres(_corps_declaration(texte, "colonnesServeurSeules"))
    entieres = set(
        re.findall(
            r"'([^']+)'",
            _corps_declaration(texte, "tablesEntierementDistantes"),
        )
    )

    planchers = (
        ("tablesDistantes", len(tables), MIN_TABLES_DECLAREES),
        ("renommagesDistants", len(renommages), MIN_RENOMMAGES),
        ("colonnesServeurSeules", len(seules), MIN_TABLES_SERVEUR_SEULES),
        ("tablesEntierementDistantes", len(entieres), MIN_TABLES_ENTIEREMENT_SERVEUR),
    )
    for nom, trouve, attendu in planchers:
        if trouve < attendu:
            raise SystemExit(
                f"{nom} : {trouve} entree(s) lue(s), {attendu} attendues au moins. "
                "Le lecteur a perdu un morceau : corriger le lecteur, pas le "
                "plancher."
            )

    return tables, renommages, seules, entieres


TABLES, RENOMMAGES, SERVEUR_SEUL, TABLES_ENTIEREMENT_SERVEUR = lire_correspondance()

# Ou va le contenu de la table locale `settings`.
#
# Son absence cote serveur est une exception, et une exception doit etre
# **meritee** : elle ne vaut que si la decomposition est reelle. Chaque cle
# ci-dessous doit donc trouver sa colonne dans `profiles` — sinon le controle
# echoue, et l'exception se revele etre un pretexte.
SETTINGS_DECOMPOSE = {
    "objectif_poids": ["goal_weight_kg"],
    "daily_goals": [
        "goal_kcal",
        "goal_carbs_g",
        "goal_protein_g",
        "goal_fat_g",
        "goal_fiber_g",
    ],
    "theme_mode": ["theme_mode"],
    "onboarding_done": ["onboarding_done"],
}

# Cles de reglages qui restent sur l'appareil, et pourquoi.
#
# Ce ne sont pas des donnees de l'utilisateur mais des preferences de cet
# appareil-ci : les synchroniser ferait changer le theme du telephone de bureau
# parce qu'on a touche a celui de la cuisine.
SETTINGS_LOCAUX = {
    "analysis_mode",
    "keep_photos",
    "meal_reminders",
    "daily_summary",
    "reminder_hour",
    "reminder_minute",
    "disclaimer_seen",
    "privacy_version",
}

# Planchers d'extraction. Un lecteur qui ne trouve rien rend un vert qui ne
# prouve rien ; ces bornes le font echouer au lieu de le laisser passer.
#
# Ils sont tenus **pres de la realite** (67 colonnes locales, 8 tables), avec
# une petite marge : un plancher trop bas laisserait passer un lecteur qui a
# perdu un morceau, ce qui est exactement le defaut qu'ils existent pour
# fermer. Les tables ont en plus un comptage brut, qui les rend exactes.
MIN_TABLES_LOCALES = 8
MIN_COLONNES_LOCALES = 65
MIN_TABLES_SERVEUR = 8
MIN_POLITIQUES = 9


# ---------------------------------------------------------------------------
# Lecteurs
# ---------------------------------------------------------------------------


def _sans_commentaires_sql(texte: str) -> str:
    """Retire les commentaires `--`.

    Indispensable : ce fichier de migration **documente** les colonnes qu'il
    ajoute. Un lecteur qui garde les commentaires trouve `portion_label` dans
    la phrase qui l'explique, et declare la colonne presente alors qu'elle ne
    l'est peut-etre plus.
    """
    return re.sub(r"--[^\n]*", "", texte)


def _aplatir(texte: str) -> str:
    return re.sub(r"\s+", " ", texte).strip()


def _colonnes_dun_bloc(corps: str) -> list[str]:
    """Colonnes d'un corps de `create table`, une par ligne."""
    colonnes: list[str] = []
    for ligne in corps.split("\n"):
        ligne = ligne.strip().rstrip(",")
        if not ligne:
            continue
        # Les contraintes de table ne sont pas des colonnes.
        if re.match(
            r"(?i)^(primary\s+key|foreign\s+key|unique|constraint|check|exclude)\b",
            ligne,
        ):
            continue
        correspondance = re.match(r'^"?([A-Za-z_][A-Za-z0-9_]*)"?\s', ligne)
        if correspondance:
            colonnes.append(correspondance.group(1))
    return colonnes


def _blocs(texte: str, motif: str) -> list[tuple[str, str]]:
    """Rend (nom, corps) pour chaque `motif <nom> (` a parenthese equilibree.

    Le comptage de profondeur est necessaire : `REFERENCES meals (id)` ouvre
    une parenthese a l'interieur du bloc, et une coupe paresseuse s'arreterait
    dessus.
    """
    resultats: list[tuple[str, str]] = []
    for correspondance in re.finditer(motif, texte, re.I):
        debut = correspondance.end() - 1
        profondeur = 0
        i = debut
        while i < len(texte):
            if texte[i] == "(":
                profondeur += 1
            elif texte[i] == ")":
                profondeur -= 1
                if profondeur == 0:
                    break
            i += 1
        resultats.append((correspondance.group(1), texte[debut + 1 : i]))
    return resultats


def lire_local() -> tuple[dict[str, set[str]], int]:
    """Schema local, et le nombre brut de `CREATE TABLE` rencontres."""
    brut = BASE_LOCALE.read_text(encoding="utf-8")
    tables: dict[str, set[str]] = {}
    for nom, corps in _blocs(brut, r"CREATE TABLE\s+(\w+)\s*\("):
        tables.setdefault(nom, set()).update(_colonnes_dun_bloc(corps))
    # Les `ALTER TABLE ... ADD COLUMN` de `_ajoutsVersion2` s'ecrivent dans des
    # chaines Dart, donc sur une ligne — mais on aplatit quand meme, pour que
    # la lecture ne depende pas de la mise en forme.
    for correspondance in re.finditer(
        r"ALTER TABLE\s+(\w+)\s+ADD COLUMN\s+(\w+)", _aplatir(brut), re.I
    ):
        tables.setdefault(correspondance.group(1), set()).add(
            correspondance.group(2)
        )
    return tables, len(re.findall(r"CREATE TABLE", brut, re.I))


def lire_serveur() -> tuple[dict[str, set[str]], int, int]:
    """Schema serveur, et les comptages bruts de `create table` et d'`alter`."""
    tables: dict[str, set[str]] = {}
    bruts_tables = 0
    bruts_alterations = 0
    for chemin in sorted(MIGRATIONS.glob("*.sql")):
        brut = _sans_commentaires_sql(chemin.read_text(encoding="utf-8"))
        bruts_tables += len(re.findall(r"create table if not exists", brut, re.I))
        bruts_alterations += len(
            re.findall(r"alter table\s+\S+\s+add column if not exists", brut, re.I)
        )
        # Deux formes du texte, et les confondre ne rend rien : un `create
        # table` se lit ligne a ligne, un `alter table ... add column` s'ecrit
        # sur plusieurs lignes et exige donc un aplatissement. Mesure de
        # l'erreur inverse — aplatir avant d'extraire les colonnes d'un bloc ne
        # rendait qu'une colonne de `meals` sur dix-neuf.
        for nom, corps in _blocs(
            brut, r"create table if not exists public\.(\w+)\s*\("
        ):
            tables.setdefault(nom, set()).update(_colonnes_dun_bloc(corps))
        for correspondance in re.finditer(
            r"alter table public\.(\w+)\s+add column if not exists\s+(\w+)",
            _aplatir(brut),
            re.I,
        ):
            tables.setdefault(correspondance.group(1), set()).add(
                correspondance.group(2)
            )
    return tables, bruts_tables, bruts_alterations


def lire_politiques() -> tuple[list[tuple[str, str]], int, int]:
    """Politiques lues, et les comptages bruts qui rendent le lecteur non aveugle.

    Le motif n'exige **pas** de retour a la ligne entre le nom et `on` : c'est
    precisement ce qui rendait le validateur precedent aveugle aux six
    politiques de `0001_init.sql`, ecrites sur une seule ligne.
    """
    politiques: list[tuple[str, str]] = []
    bruts_creations = 0
    bruts_suppressions = 0
    for chemin in sorted(MIGRATIONS.glob("*.sql")):
        plat = _aplatir(_sans_commentaires_sql(chemin.read_text(encoding="utf-8")))
        bruts_creations += len(re.findall(r"create policy", plat, re.I))
        bruts_suppressions += len(re.findall(r"drop policy if exists", plat, re.I))
        for correspondance in re.finditer(
            r'create policy\s+"?([A-Za-z_][A-Za-z0-9_]*)"?\s+on\s+([A-Za-z_.]+)',
            plat,
            re.I,
        ):
            politiques.append((correspondance.group(1), correspondance.group(2)))
    return politiques, bruts_creations, bruts_suppressions


def lire_cles_de_reglages() -> set[str]:
    """Cles de reglages que l'application lit ou ecrit, relevees dans le source.

    Sert a fermer l'ensemble : une cle ajoutee sans destination declaree doit
    faire echouer le controle, sinon elle partirait sur l'appareil sans que
    personne n'ait decide qu'elle n'y reste.
    """
    cles: set[str] = set()
    for chemin in SOURCE_DART.rglob("*.dart"):
        texte = chemin.read_text(encoding="utf-8")
        for correspondance in re.finditer(
            r"(?:read|write)Setting\(\s*'([A-Za-z_][A-Za-z0-9_]*)'", texte
        ):
            cles.add(correspondance.group(1))
    return cles


# ---------------------------------------------------------------------------
# Controles
# ---------------------------------------------------------------------------


def controler_extraction(
    local: dict[str, set[str]],
    serveur: dict[str, set[str]],
    politiques: list[tuple[str, str]],
    bruts_tables_serveur: int,
    bruts_creations: int,
    bruts_suppressions: int,
    bruts_tables_local: int,
) -> list[str]:
    """Le lecteur a-t-il trouve ce qu'il cherchait ?

    C'est le controle le plus important du fichier, et celui qu'on oublie : un
    test qui lit des fichiers peut etre vert **en ne lisant rien**. C'est le
    pire des etats — un defaut avec l'apparence d'une protection.
    """
    defauts: list[str] = []

    if len(local) < MIN_TABLES_LOCALES:
        defauts.append(
            f"schema local : {len(local)} table(s) lue(s), {MIN_TABLES_LOCALES} attendues "
            "au moins — le lecteur ne lit plus ce qu'il croit lire"
        )
    if len(serveur) < MIN_TABLES_SERVEUR:
        defauts.append(
            f"schema serveur : {len(serveur)} table(s) lue(s), {MIN_TABLES_SERVEUR} attendues "
            "au moins"
        )

    total_local = sum(len(colonnes) for colonnes in local.values())
    if total_local < MIN_COLONNES_LOCALES:
        defauts.append(
            f"schema local : {total_local} colonne(s) lue(s), {MIN_COLONNES_LOCALES} attendues "
            "au moins"
        )

    # Le nombre de `CREATE TABLE` ecrits et le nombre de tables lues doivent
    # coincider : rien d'autre n'ajoute de table, ni d'un cote ni de l'autre.
    # Un ecart veut dire que le lecteur de blocs en a manque une.
    if bruts_tables_local != len(local):
        defauts.append(
            f"schema local : {bruts_tables_local} `CREATE TABLE` ecrits, "
            f"{len(local)} table(s) lue(s) — le lecteur en a manque"
        )
    if bruts_tables_serveur != len(serveur):
        defauts.append(
            f"schema serveur : {bruts_tables_serveur} `create table` ecrits, "
            f"{len(serveur)} table(s) lue(s) — le lecteur en a manque"
        )

    if bruts_creations == 0:
        defauts.append(
            "aucune politique RLS lue : le controle de rejouabilite ne mesurerait rien"
        )
    if bruts_creations != len(politiques):
        defauts.append(
            f"politiques : {len(politiques)} lue(s) pour {bruts_creations} `create policy` "
            "dans les fichiers — le motif de lecture en manque, et un controle qui ne "
            "peut rien affirmer doit echouer"
        )
    if bruts_suppressions != bruts_creations:
        defauts.append(
            f"{bruts_creations} `create policy` pour {bruts_suppressions} "
            "`drop policy if exists` : la migration ne serait pas rejouable"
        )
    if len(politiques) < MIN_POLITIQUES:
        defauts.append(
            f"{len(politiques)} politique(s) lue(s), {MIN_POLITIQUES} attendues au moins"
        )

    return defauts


def controler_accord(
    local: dict[str, set[str]], serveur: dict[str, set[str]]
) -> list[str]:
    """Chaque colonne locale a une destination serveur, et les deux ensembles sont clos."""
    defauts: list[str] = []

    # --- Les tables locales sont-elles toutes declarees ? ---
    #
    # La declaration vit dans `correspondance_distant.dart` : les messages la
    # nomment, pour que le lecteur sache ou corriger.
    for nom in sorted(set(local) - set(TABLES) - {"settings"}):
        defauts.append(
            f"table locale `{nom}` sans destination declaree : "
            "l'ajouter a `tablesDistantes`, ou expliquer son absence"
        )
    for nom in sorted(set(TABLES) - set(local)):
        defauts.append(
            f"`tablesDistantes` declare `{nom}`, que le schema local ne connait pas"
        )
    for nom in sorted(set(TABLES.values()) - set(serveur)):
        defauts.append(
            f"`tablesDistantes` declare la table serveur `{nom}`, absente des migrations"
        )

    # --- Chaque colonne locale a-t-elle une colonne serveur ? ---
    for nom_local, nom_serveur in sorted(TABLES.items()):
        if nom_local not in local or nom_serveur not in serveur:
            continue
        colonnes_serveur = serveur[nom_serveur]
        for colonne in sorted(local[nom_local]):
            cible = RENOMMAGES.get(f"{nom_local}.{colonne}", colonne)
            if cible not in colonnes_serveur:
                defauts.append(
                    f"colonne locale `{nom_local}.{colonne}` sans destination : "
                    f"`{nom_serveur}.{cible}` n'existe pas cote serveur — "
                    "une synchronisation la perdrait en silence"
                )

    # --- Le serveur a-t-il des colonnes qu'aucun local n'alimente ? ---
    for nom_serveur, colonnes in sorted(serveur.items()):
        if nom_serveur in TABLES_ENTIEREMENT_SERVEUR:
            continue
        if nom_serveur not in SERVEUR_SEUL:
            defauts.append(
                f"table serveur `{nom_serveur}` absente de SERVEUR_SEUL : "
                "declarer ses colonnes sans equivalent local, meme si l'ensemble "
                "est vide — ou la nommer dans `tablesEntierementDistantes`"
            )
            continue
        declarees = SERVEUR_SEUL[nom_serveur]
        alimentees = {
            RENOMMAGES.get(f"{nom_local}.{colonne}", colonne)
            for nom_local, cible in TABLES.items()
            if cible == nom_serveur
            for colonne in local.get(nom_local, set())
        }
        for colonne in sorted(colonnes - alimentees - declarees):
            defauts.append(
                f"colonne serveur `{nom_serveur}.{colonne}` n'est alimentee par aucune "
                "colonne locale, et n'est pas declaree dans SERVEUR_SEUL"
            )
        for colonne in sorted(declarees - (colonnes - alimentees)):
            defauts.append(
                f"SERVEUR_SEUL declare `{nom_serveur}.{colonne}`, qui est en fait "
                "alimentee par le local (ou n'existe plus)"
            )

    return defauts


def controler_reglages(serveur: dict[str, set[str]]) -> list[str]:
    """L'exception de `settings` est-elle meritee, et l'ensemble est-il clos ?"""
    defauts: list[str] = []

    profils = serveur.get("profiles", set())
    for cle, colonnes in sorted(SETTINGS_DECOMPOSE.items()):
        for colonne in colonnes:
            if colonne not in profils:
                defauts.append(
                    f"reglage `{cle}` : `profiles.{colonne}` n'existe pas — "
                    "l'exception de `settings` ne serait pas meritee"
                )

    # Une exception qui ne couvre rien est une exception qui cache.
    if not SETTINGS_DECOMPOSE:
        defauts.append(
            "aucun reglage decompose : l'absence de table `settings` cote serveur "
            "n'aurait plus de justification"
        )

    # Fermeture : une cle de reglage ajoutee au source doit etre classee.
    cles = lire_cles_de_reglages()
    if len(cles) < 10:
        defauts.append(
            f"{len(cles)} cle(s) de reglage relevee(s) dans le source, 10 attendues au "
            "moins — le lecteur ne lit plus ce qu'il croit lire"
        )
    for cle in sorted(cles - set(SETTINGS_DECOMPOSE) - SETTINGS_LOCAUX):
        defauts.append(
            f"cle de reglage `{cle}` sans decision : la mettre dans SETTINGS_DECOMPOSE "
            "(elle part sur le serveur) ou dans SETTINGS_LOCAUX (elle reste sur "
            "l'appareil)"
        )
    for cle in sorted(set(SETTINGS_DECOMPOSE) | SETTINGS_LOCAUX):
        if cle not in cles:
            defauts.append(
                f"`{cle}` est declare mais n'est lu ni ecrit nulle part dans le source"
            )

    return defauts


def controler_politiques(politiques: list[tuple[str, str]]) -> list[str]:
    """Chaque politique a son `drop policy if exists` correspondant."""
    defauts: list[str] = []
    supprimees: set[tuple[str, str]] = set()
    for chemin in sorted(MIGRATIONS.glob("*.sql")):
        plat = _aplatir(_sans_commentaires_sql(chemin.read_text(encoding="utf-8")))
        for correspondance in re.finditer(
            r'drop policy if exists\s+"?([A-Za-z_][A-Za-z0-9_]*)"?\s+on\s+([A-Za-z_.]+)',
            plat,
            re.I,
        ):
            supprimees.add((correspondance.group(1), correspondance.group(2)))
    for nom, table in politiques:
        if (nom, table) not in supprimees:
            defauts.append(
                f"politique `{nom}` sur `{table}` : aucun `drop policy if exists` "
                "correspondant — la migration ne serait pas rejouable"
            )
    return defauts


def main() -> int:
    local, bruts_tables_local = lire_local()
    serveur, bruts_tables_serveur, _ = lire_serveur()
    politiques, bruts_creations, bruts_suppressions = lire_politiques()

    defauts = controler_extraction(
        local,
        serveur,
        politiques,
        bruts_tables_serveur,
        bruts_creations,
        bruts_suppressions,
        bruts_tables_local,
    )
    defauts += controler_accord(local, serveur)
    defauts += controler_reglages(serveur)
    defauts += controler_politiques(politiques)

    if defauts:
        print(
            "Echec de l'accord entre le schema local et le schema serveur :",
            file=sys.stderr,
        )
        for defaut in defauts:
            print(f"  - {defaut}", file=sys.stderr)
        return 1

    colonnes = sum(len(colonnes) for colonnes in local.values())
    print(f"  OK  schema local : {len(local)} tables, {colonnes} colonnes")
    print(f"  OK  schema serveur : {len(serveur)} tables, {len(politiques)} politiques")
    print(
        "  OK  chaque colonne locale a une destination, et les deux ensembles sont clos"
    )
    print(
        f"  OK  correspondance lue dans {CORRESPONDANCE.name} : "
        f"{len(TABLES)} table(s), {len(RENOMMAGES)} renommage(s)"
    )
    print(
        f"  OK  reglages : {len(SETTINGS_DECOMPOSE)} decompose(s), "
        f"{len(SETTINGS_LOCAUX)} declare(s) locaux"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
