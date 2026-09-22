"""Assemble les migrations en un seul fichier, pour une application a la main.

Pourquoi ce script existe
-------------------------
Le projet Supabase n'a aucun canal privilegie sur cette machine : ni jeton de
gestion, ni mot de passe de base, ni projet lie. La cle publique ne peut pas
executer de DDL. La seule voie praticable est donc l'editeur SQL du tableau de
bord, qui demande de coller le SQL.

Trois fichiers a coller, c'est trois occasions d'en oublier un. Ce script les
assemble dans l'ordre, et **verifie** que le resultat contient chaque source
octet pour octet -- un assemblage qui perdrait un fichier serait pire que
l'absence d'assemblage.

Le fichier produit est derive : il ne doit pas etre commite (il pourrait
diverger des sources), et il ne doit pas vivre dans `migrations/` (le CLI le
prendrait pour une migration de plus).
"""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path

# L'ordre compte : 0001 cree les tables et les politiques, 0002 ajoute les
# portions et le suivi, 0003 ajoute les pierres tombales.
SOURCES = (
    "0001_init.sql",
    "0002_portions_et_suivi.sql",
    "0003_pierres_tombales.sql",
)

RACINE = Path(__file__).resolve().parent.parent
DOSSIER = RACINE / "backend" / "supabase" / "migrations"
SORTIE = RACINE / "backend" / "supabase" / "a-appliquer-a-la-main.sql"

ENTETE = """-- =====================================================================
--  Assiette -- migrations du serveur, assemblees en un seul fichier.
--
--  FICHIER DERIVE : ne pas modifier a la main, ne pas commiter.
--  Il est produit par `tools/assembler_migrations.py` a partir de
--  `backend/supabase/migrations/`, dans l'ordre des versions.
--
--  Usage : tableau de bord Supabase -> SQL Editor -> New query,
--  coller tout ce fichier, puis Run.
--
--  Aucune borne `begin;`/`commit;` : chaque instruction s'applique telle
--  quelle, et l'editeur SQL execute le lot entier.
-- =====================================================================
"""


def empreinte(donnees: bytes) -> str:
    return hashlib.sha256(donnees).hexdigest()


def main() -> int:
    if not DOSSIER.is_dir():
        print(f"dossier introuvable : {DOSSIER}", file=sys.stderr)
        return 1

    morceaux: list[bytes] = []
    for nom in SOURCES:
        chemin = DOSSIER / nom
        if not chemin.is_file():
            print(f"migration manquante : {chemin}", file=sys.stderr)
            return 1
        donnees = chemin.read_bytes()
        print(f"  {nom:34s} {len(donnees):6d} octets  {empreinte(donnees)[:16]}")
        morceaux.append(donnees)

    corps = b"\n\n".join(morceaux)
    sortie = ENTETE.encode("utf-8") + b"\n" + corps
    if not sortie.endswith(b"\n"):
        sortie += b"\n"

    # Verification : le resultat doit contenir chaque source **verbatim**.
    # Une verification qui ne ferait que compter les octets ne verrait pas un
    # fichier remplace par un autre de meme taille.
    for nom, donnees in zip(SOURCES, morceaux):
        if donnees not in sortie:
            print(f"assemblage infidele : {nom} absent du resultat", file=sys.stderr)
            return 1

    SORTIE.write_bytes(sortie)
    relu = SORTIE.read_bytes()
    if relu != sortie:
        print("le fichier relu differe de ce qui a ete ecrit", file=sys.stderr)
        return 1

    print()
    print(f"  -> {SORTIE.relative_to(RACINE)}")
    print(f"     {len(sortie):6d} octets  {empreinte(sortie)[:16]}")
    print(f"     contient les {len(SOURCES)} sources, verifie octet pour octet")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
