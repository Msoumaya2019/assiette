#!/usr/bin/env python3
"""Falsifie `tools/eprouver_migration_sur_postgres.mjs`.

Le controle existe parce qu'une lecture de texte ne dit pas si le SQL
**s'execute**. Ce banc fabrique les defauts que cette epreuve pretend attraper,
et verifie qu'elle tombe.

Le cas le plus important n'est pas une erreur de SQL : c'est l'**oubli**. Une
migration ecrite mais absente de `MIGRATIONS_ATTENDUES` aurait ete silencieusement
non eprouvee, et l'epreuve serait restee verte sans avoir jamais ouvert le
fichier neuf. C'est le defaut que ce depot a deja rencontre — un validateur qui
annoncait « Politiques : 0 » sur un fichier qui en portait six. Le banc reproduit
donc l'oubli **et** l'etat ou le garde-fou est desactive, ce qui est la seule
facon d'etablir que c'est bien lui qui porte quelque chose.

Prerequis : Node et `@electric-sql/pglite`. Le banc les cherche la ou l'espace de
travail isole les range ; s'il ne les trouve pas, il s'arrete en le disant plutot
que de conclure « non detecte » sur des cas qu'il n'a pas mesures.

Usage : python3 tools/bancs/falsifier_epreuve_migrations.py
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, Banc, empreinte_arbre  # noqa: E402

EPREUVE = RACINE / "tools" / "eprouver_migration_sur_postgres.mjs"

MIGRATION_3 = "backend/supabase/migrations/0003_pierres_tombales.sql"
MIGRATION_OUBLIEE = "backend/supabase/migrations/0004_oubliee.sql"

# ---------------------------------------------------------------------------
# Ancres de mutation
# ---------------------------------------------------------------------------

# La reprise des favoris, telle qu'elle est ecrite dans `0003`.
REPRISE_FAVORIS = (
    b"update public.favorites\n"
    b"   set updated_at = created_at\n"
    b" where updated_at is null;"
)

# La colonne qui porte la pierre tombale des portions.
COLONNE_PORTIONS = (
    b"alter table public.portions\n"
    b"  add column if not exists deleted_at timestamptz;"
)

# Le garde-fou d'exhaustivite, dans l'epreuve. On ne le supprime pas — un bloc
# retire laisserait le fichier incoherent. On le rend **inatteignable**, ce qui
# est exactement l'etat d'un controle qu'on aurait oublie d'ecrire.
DEBUT_GARDE_FOU = (
    b"const oubliees = surDisque.filter((nom) => !MIGRATIONS_ATTENDUES.includes(nom));\n"
    b"const fantomes = MIGRATIONS_ATTENDUES.filter((nom) => !surDisque.includes(nom));\n"
    b"if (oubliees.length || fantomes.length) {"
)

# Une migration valide, mais que l'epreuve ne connait pas.
CONTENU_OUBLIEE = (
    b"-- Migration ajoutee par le banc de falsification, jamais commitee.\n"
    b"select 1;\n"
)

# ---------------------------------------------------------------------------
# Les zones que ce banc touche.
# ---------------------------------------------------------------------------

ZONES = (
    "tools",
    "backend/supabase/migrations",
)


def empreintes() -> dict[str, str]:
    """Empreinte SHA-256 de chaque fichier des zones touchees."""
    resultat: dict[str, str] = {}
    for zone in ZONES:
        for chemin, empreinte in empreinte_arbre(RACINE / zone).items():
            resultat[f"{zone}/{chemin}"] = empreinte
    return resultat


# ---------------------------------------------------------------------------
# Ou trouver Node et PGlite
# ---------------------------------------------------------------------------

# L'espace de travail isole range ses binaires cote a cote :
#   .../binaries/python/envs/<nom>/Scripts/python.exe   <- l'interpreteur
#   .../binaries/node/versions/<version>/node.exe
#   .../binaries/node/workspace/node_modules
# On deduit le second du premier plutot que d'ecrire un chemin de machine en
# dur : le depot ne doit pas porter le nom d'un utilisateur.
def _racine_binaires() -> Path | None:
    parents = Path(sys.executable).resolve().parents
    return parents[4] if len(parents) >= 5 else None


def executable_node() -> Path | None:
    racine = _racine_binaires()
    if racine is None:
        return None
    versions = racine / "node" / "versions"
    if not versions.is_dir():
        return None
    for candidat in sorted(versions.glob("*/node.exe")) + sorted(
        versions.glob("*/bin/node")
    ):
        if candidat.is_file():
            return candidat
    return None


def dossier_pglite() -> Path | None:
    candidats: list[Path] = []
    depuis_environnement = os.environ.get("NODE_PATH")
    if depuis_environnement:
        candidats += [Path(partie) for partie in depuis_environnement.split(os.pathsep)]
    racine = _racine_binaires()
    if racine is not None:
        candidats.append(racine / "node" / "workspace" / "node_modules")
    for candidat in candidats:
        if (candidat / "@electric-sql" / "pglite").is_dir():
            return candidat
    return None


def principal() -> int:
    node = executable_node()
    pglite = dossier_pglite()

    if node is None or pglite is None:
        manquant = "Node" if node is None else "@electric-sql/pglite"
        print(
            f"{manquant} est introuvable : ce banc ne peut pas mesurer l'epreuve "
            "des migrations.\n"
            "Sans lui, tous les cas se liraient « non detecte » alors qu'aucun "
            "n'aurait ete mesure.\n"
            "Marche a suivre : backend/README.md, section « Epreuve des migrations ».",
            file=sys.stderr,
        )
        return 2

    environnement = dict(os.environ)
    environnement["NODE_PATH"] = str(pglite)

    banc = Banc(
        EPREUVE,
        interpreteur=[str(node)],
        environnement=environnement,
    )

    # --- le temoin d'un passage precedent --------------------------------
    #
    # Mesure : une campagne de seize bancs a laisse `0004_oubliee.sql` dans
    # l'arbre, et ce banc a refuse de demarrer sur « La migration 0004_oubliee.sql
    # existe mais n'est pas dans MIGRATIONS_ATTENDUES » — une migration oubliee
    # annoncee comme un defaut du depot, alors que ce banc l'avait fabriquee.
    #
    # La cause est du cote de l'environnement : sur cette machine, le garde de
    # suppression refuse parfois **sans le dire**, et `Path.unlink()` rend alors
    # la main sans lever. Le banc ne peut donc pas compter sur son propre
    # nettoyage pour la fois d'apres. Il retire son temoin au demarrage, et le
    # dit.
    temoin = RACINE / MIGRATION_OUBLIEE
    if temoin.exists():
        print(f"temoin d'un passage precedent, retire : {temoin.name}")
        banc.retirer(temoin)

    avant = empreintes()

    initial = banc.etat_initial()
    print(f"etat initial : code {initial.code}")
    if initial.code != 0:
        print(initial.texte, file=sys.stderr)
        print("l'epreuve echoue deja avant toute mutation.", file=sys.stderr)
        return 2

    # --- 1. L'oubli, et le garde-fou qui l'attrape -------------------------

    def migration_non_declaree() -> None:
        """Une migration existe sur le disque, absente de `MIGRATIONS_ATTENDUES`."""
        banc.creer(MIGRATION_OUBLIEE, CONTENU_OUBLIEE)

    def migration_non_declaree_sans_garde_fou() -> None:
        """Le meme oubli, garde-fou rendu inatteignable.

        L'epreuve parcourt alors les migrations du disque, applique la nouvelle
        sans broncher, et rend un **vert sur un ensemble incomplet**. C'est le
        seul cas qui etablit que le garde-fou porte quelque chose : sans lui, on
        aurait seulement constate qu'une migration de plus ne derange pas.
        """
        banc.creer(MIGRATION_OUBLIEE, CONTENU_OUBLIEE)
        banc.suivre("tools/eprouver_migration_sur_postgres.mjs").muter(
            DEBUT_GARDE_FOU, b"if (false) {"
        )

    def migration_declaree_mais_absente() -> None:
        """`MIGRATIONS_ATTENDUES` annonce un fichier qui n'existe pas."""
        banc.supprimer(MIGRATION_3)

    # --- 2. Les assertions de fond -----------------------------------------

    def reprise_des_favoris_retiree() -> None:
        """La reprise `updated_at = created_at` disparait de la migration.

        Rien ne casse : la colonne existe, elle vaut `NULL`. Seule la
        comparaison avec `created_at` peut le voir.
        """
        banc.suivre(MIGRATION_3).muter(REPRISE_FAVORIS, b"-- reprise retiree par le banc")

    def colonne_de_portion_retiree() -> None:
        """La pierre tombale des portions n'est plus ajoutee."""
        banc.suivre(MIGRATION_3).muter(COLONNE_PORTIONS, b"-- colonne retiree par le banc")

    # --- 3. Temoin : ce qui ne doit PAS etre signale ------------------------

    def reformatage_legitime() -> None:
        """Une ligne vide de plus dans la migration ne change rien au schema."""
        banc.suivre(MIGRATION_3).muter(
            REPRISE_FAVORIS, b"\n" + REPRISE_FAVORIS
        )

    # --- Enregistrement ----------------------------------------------------

    banc.cas(
        "migration non declaree",
        "n'est pas dans MIGRATIONS_ATTENDUES",
        migration_non_declaree,
    )
    banc.cas(
        "migration non declaree, garde-fou desactive",
        "n'est pas dans MIGRATIONS_ATTENDUES",
        migration_non_declaree_sans_garde_fou,
        attendu=False,
    )
    banc.cas(
        "migration declaree mais absente",
        "n'existe pas sur le disque",
        migration_declaree_mais_absente,
    )
    banc.cas(
        "reprise des favoris retiree",
        "est rempli depuis created_at",
        reprise_des_favoris_retiree,
    )
    banc.cas(
        "colonne de portion retiree",
        "les pierres tombales de 0003 existent",
        colonne_de_portion_retiree,
    )
    banc.cas(
        "reformatage legitime",
        "ECHEC",
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
        "vert — l'epreuve attrape l'oubli, la reprise manquante et la colonne "
        "absente, et laisse passer le reformatage."
    )
    return 0


if __name__ == "__main__":
    sys.exit(principal())
