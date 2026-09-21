#!/usr/bin/env python3
"""Falsifie `tools/check_migration_serveur.py`.

Le controle existe parce que le schema serveur etait **en retard** sur le schema
local : il ne connaissait ni les portions nommees, ni les pesees, ni les
mensurations. Rien ne le signalait — les deux schemas restaient valides, et le
defaut aurait produit une perte de donnees silencieuse le jour ou la
synchronisation serait branchee.

Ce banc restaure chacun des defauts possibles et verifie que le controle tombe.
Il verifie aussi ce qu'il ne doit **pas** signaler, et — c'est le cas le plus
important — il reproduit l'aveuglement historique du validateur de politiques,
pour prouver que le comptage brut le rattrape.

Usage : python3 tools/bancs/falsifier_migration_serveur.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, Banc, empreinte_arbre  # noqa: E402

CONTROLE = RACINE / "tools" / "check_migration_serveur.py"
MIGRATION_2 = "backend/supabase/migrations/0002_portions_et_suivi.sql"
MIGRATION_1 = "backend/supabase/migrations/0001_init.sql"
BASE_LOCALE = "app/lib/data/local/app_database.dart"
PROVIDERS = "app/lib/state/providers.dart"

# ---------------------------------------------------------------------------
# Ancres de mutation
# ---------------------------------------------------------------------------

# Colonne serveur retiree : `pesees.poids_kg` n'a plus de destination.
COLONNE_POIDS = b"  weight_kg   numeric not null,\n"

# Table serveur renommee : `body_measurements` disparait des migrations.
TABLE_MESURES = b"create table if not exists public.body_measurements ("

# Table ajoutee au schema local, sans destination declaree.
INDEX_MESURES = b"    'CREATE INDEX idx_mesures_le ON mesures (mesure_le DESC)',"

# Colonne ajoutee au schema local, sans destination declaree.
COLONNES_MEALS = b"        eaten_at INTEGER NOT NULL,\n        name TEXT NOT NULL,\n"

# Colonne ajoutee au schema serveur, non declaree dans SERVEUR_SEUL.
FIN_PORTIONS = (
    b"  updated_at timestamptz not null default now(),\n"
    b"  primary key (user_id, cle)\n"
)

# Politique privee de son `drop` : la migration cesse d'etre rejouable.
DROP_PORTIONS = b'drop policy if exists "portions_owner" on public.portions;\n'

# Reglage lu par l'application, sans decision declaree.
REGLAGE_PRIVACY = b"    final privacyVersion = await database.readSetting('privacy_version');"

# La colonne, remplacee par un commentaire qui la nomme. C'est l'etat exact du
# defaut historique : le texte est la, la colonne ne l'est plus.
ALTER_PORTION_LABEL = (
    b"alter table public.meal_items add column if not exists portion_label text;"
)

# --- ancres visees dans le controle lui-meme ------------------------------

# Le motif de lecture des politiques, dans sa forme juste.
MOTIF_POLITIQUES = (
    b"r'create policy\\s+\"?([A-Za-z_][A-Za-z0-9_]*)\"?\\s+on\\s+([A-Za-z_.]+)'"
)

# La forme historique, aveugle : elle exige un retour a la ligne entre le nom de
# la politique et `on`. Aucune des neuf politiques du depot n'en a, et le
# validateur d'origine annoncait donc « 0 politique » puis « forme rejouable :
# OK » — vert en n'ayant rien mesure.
MOTIF_POLITIQUES_AVEUGLE = b"r'create policy\\s+(\\S+)\\s*\\n\\s*on\\s+(\\S+)'"

# Le motif de lecture des tables locales, dans sa forme juste.
MOTIF_TABLES_LOCALES = b'r"CREATE TABLE\\s+(\\w+)\\s*\\("'

# Le retrait des commentaires SQL, dans sa forme juste.
RETRAIT_COMMENTAIRES = b'    return re.sub(r"--[^\\n]*", "", texte)'


# Les zones que ce banc touche. `empreinte_arbre` sur la racine entiere
# parcourrait `app/build` et les caches de paquets : lent, et sans rapport.
ZONES = (
    "tools",
    "app/lib",
    "backend/supabase/migrations",
)


def empreintes() -> dict[str, str]:
    """Empreinte SHA-256 de chaque fichier des zones touchees."""
    resultat: dict[str, str] = {}
    for zone in ZONES:
        for chemin, empreinte in empreinte_arbre(RACINE / zone).items():
            resultat[f"{zone}/{chemin}"] = empreinte
    return resultat


def principal() -> int:
    banc = Banc(CONTROLE)

    avant = empreintes()

    initial = banc.etat_initial()
    print(f"etat initial : code {initial.code}")
    if initial.code != 0:
        print(initial.texte, file=sys.stderr)
        print("le controle echoue deja avant toute mutation.", file=sys.stderr)
        return 2

    # --- 1. Cote local : une colonne sans destination ----------------------

    def colonne_locale_sans_destination() -> None:
        fichier = banc.suivre(BASE_LOCALE)
        fichier.muter(
            COLONNES_MEALS, COLONNES_MEALS + b"        humeur TEXT,\n"
        )

    def table_locale_sans_destination() -> None:
        fichier = banc.suivre(BASE_LOCALE)
        fichier.muter(
            INDEX_MESURES,
            INDEX_MESURES
            + b"\n    '''CREATE TABLE notes (id TEXT PRIMARY KEY, texte TEXT)''',",
        )

    # --- 2. Cote serveur : une colonne qui a disparu -----------------------

    def colonne_serveur_retiree() -> None:
        banc.suivre(MIGRATION_2).muter(COLONNE_POIDS, b"")

    def table_serveur_renommee() -> None:
        banc.suivre(MIGRATION_2).muter(
            TABLE_MESURES, b"create table if not exists public.body_measures ("
        )

    def colonne_serveur_non_declaree() -> None:
        banc.suivre(MIGRATION_2).muter(
            FIN_PORTIONS,
            b"  updated_at timestamptz not null default now(),\n"
            b"  couleur text,\n"
            b"  primary key (user_id, cle)\n",
        )

    # --- 3. Les politiques -------------------------------------------------

    def politique_sans_drop() -> None:
        banc.suivre(MIGRATION_2).muter(DROP_PORTIONS, b"")

    def lecteur_de_politiques_aveugle() -> None:
        """Reproduit le motif fautif qui a rendu le validateur precedent aveugle.

        Le controle doit tomber malgre tout, et c'est le **comptage brut** qui
        l'y oblige : le lecteur ne voit plus rien, le fichier en contient
        toujours neuf.
        """
        banc.suivre("tools/check_migration_serveur.py").muter(
            MOTIF_POLITIQUES, MOTIF_POLITIQUES_AVEUGLE
        )

    def lecteur_de_tables_aveugle() -> None:
        banc.suivre("tools/check_migration_serveur.py").muter(
            MOTIF_TABLES_LOCALES, b'r"CREATE TABLEZZ\\s+(\\w+)\\s*\\("'
        )

    # --- 4. Les reglages ---------------------------------------------------

    def reglage_sans_decision() -> None:
        banc.suivre(PROVIDERS).muter(
            REGLAGE_PRIVACY,
            REGLAGE_PRIVACY
            + b"\n    final autre = await database.readSetting('nouveau_reglage');",
        )

    # --- 5. Le retrait des commentaires, dans les deux sens ----------------

    def commentaire_tenu_pour_du_code() -> None:
        """La colonne est retiree, le commentaire qui la nomme reste.

        Avec le retrait des commentaires, le controle tombe — correctement.
        """
        banc.suivre(MIGRATION_2).muter(ALTER_PORTION_LABEL, b"-- " + ALTER_PORTION_LABEL)

    def commentaire_tenu_pour_du_code_sans_nettoyage() -> None:
        """Le meme etat, retrait des commentaires **desactive**.

        Le lecteur trouve alors la phrase du commentaire, declare la colonne
        presente, et le controle reste **vert sur un fichier fautif**. C'est le
        seul cas qui etablit que le retrait des commentaires porte quelque
        chose : sans lui, on aurait seulement constate qu'un commentaire ne
        derange pas.
        """
        banc.suivre(MIGRATION_2).muter(ALTER_PORTION_LABEL, b"-- " + ALTER_PORTION_LABEL)
        banc.suivre("tools/check_migration_serveur.py").muter(
            RETRAIT_COMMENTAIRES, b"    return texte"
        )

    # --- 6. Temoin : ce qui ne doit PAS etre signale -----------------------

    def reformatage_legitime() -> None:
        """Une ligne vide dans un `create table` ne retire aucune colonne."""
        banc.suivre(MIGRATION_2).muter(
            COLONNE_POIDS, b"\n" + COLONNE_POIDS
        )

    # --- Enregistrement ----------------------------------------------------

    banc.cas(
        "colonne locale sans destination",
        "meals.humeur",
        colonne_locale_sans_destination,
    )
    banc.cas(
        "table locale sans destination",
        "`notes` sans destination",
        table_locale_sans_destination,
    )
    banc.cas(
        "colonne serveur retiree", "pesees.poids_kg", colonne_serveur_retiree
    )
    banc.cas(
        "table serveur renommee", "absente des migrations", table_serveur_renommee
    )
    banc.cas(
        "colonne serveur non declaree",
        "portions.couleur",
        colonne_serveur_non_declaree,
    )
    banc.cas("politique sans drop", "portions_owner", politique_sans_drop)
    banc.cas(
        "lecteur de politiques aveugle",
        "le motif de lecture en manque",
        lecteur_de_politiques_aveugle,
    )
    banc.cas(
        "lecteur de tables aveugle", "le lecteur en a manque", lecteur_de_tables_aveugle
    )
    banc.cas("reglage sans decision", "nouveau_reglage", reglage_sans_decision)
    banc.cas(
        "commentaire tenu pour du code",
        "meal_items.portion_label",
        commentaire_tenu_pour_du_code,
    )
    banc.cas(
        "commentaire tenu pour du code, sans nettoyage",
        "meal_items.portion_label",
        commentaire_tenu_pour_du_code_sans_nettoyage,
        attendu=False,
    )
    banc.cas(
        "reformatage legitime",
        "sans destination",
        reformatage_legitime,
        attendu=False,
    )

    code = banc.tableau()

    apres = empreintes()
    identiques = avant == apres
    print(f"fichiers suivis                  : {len(apres)}")
    print(
        f"restauration a l'octet           : {'conforme' if identiques else 'DIVERGENTE'}"
    )

    if not identiques:
        for chemin in sorted(set(avant) ^ set(apres)):
            print(f"  - {chemin}", file=sys.stderr)
        return 1

    if code != 0:
        return code

    final = banc.executer()
    print(f"\netat final : code {final.code}")
    if final.code != 0:
        print(final.texte, file=sys.stderr)
        return 1

    print(
        "vert — le controle detecte chaque desaccord, et laisse passer le "
        "reformatage."
    )
    return 0


if __name__ == "__main__":
    sys.exit(principal())
