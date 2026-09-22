#!/usr/bin/env python3
"""Lance tous les bancs de `tools/bancs/` et rapporte leur code de sortie.

Ce lanceur existe pour une raison precise : lire le code de sortie **apres un
tube** rend celui du tube, pas celui de la commande. Trois bancs ont ainsi ete
annonces verts alors que l'un d'eux avait plante. Ici, chaque code de sortie est
lu directement sur `subprocess.run(...).returncode`.

La liste des bancs est **close, et verifiee dans les deux sens**. Un `readdir`
seul mesure ce qui reste : un banc ecrit mais non declare ici serait ignore en
silence, et le lanceur annoncerait « tous verts » sur un ensemble incomplet.
C'est le meme defaut que la liste close des flux de travail.

PyYAML est exige : `falsifier_check_workflows.py` eprouve un controle qui lit du
YAML, et sans PyYAML ce controle sort en 1 sans le moindre marqueur — tous les
cas se liraient « non detecte ». Le lanceur le dit avant de commencer, plutot
que de laisser accuser le banc.

`falsifier_epreuve_migrations.py` a besoin de Node et de PGlite. Il les cherche
lui-meme et s'arrete en le disant s'il ne les trouve pas : un banc qui ne peut
pas mesurer doit le dire, pas rendre « non detecte ».

**L'environnement peut refuser un nettoyage sans le dire.** Mesure : sur cette
machine, le garde de suppression bloque au-dela d'un seuil par tour, et le
blocage ne leve **rien** cote Python — `Path.unlink()` rend la main alors que le
fichier est toujours la. Quatre bancs ont donc laisse leurs temoins dans l'arbre,
et **trois autres** se sont declares en echec en les accusant : le banc des flux
sur un `__banc_essai.yml` qu'il avait fabrique, celui du projet iOS sur une icone
qu'il avait fabriquee, celui des migrations sur une `0004_oubliee.sql` qu'il
avait fabriquee. Un depot annonce casse par un nettoyage qui n'avait pas eu lieu.

Chacun de ces bancs **retire donc son propre temoin au demarrage**, et le dit :

```
temoin d'un passage precedent, retire : __banc_essai.yml
```

C'est ce qui rend la campagne rejouable quel que soit l'etat laisse par la
precedente — et c'est la seule facon de la rendre verte, puisque le nettoyage de
fin ne peut pas etre garanti ici.

Usage : python3 tools/lancer_bancs.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
BANCS = RACINE / "tools" / "bancs"

# Le banc du serveur a besoin de Deno ; `falsifier_epreuve_migrations.py` a
# besoin de Node et de PGlite ; les autres, de rien d'autre que Python.
ORDRE = [
    "falsifier_fins_de_ligne.py",
    "falsifier_ios.py",
    "falsifier_adresses.py",
    "falsifier_client_deepseek_dart.py",
    "falsifier_proxy_dart.py",
    "falsifier_arbitrage_dart.py",
    "falsifier_synchronisation_dart.py",
    "falsifier_synchronisation_locale_dart.py",
    "falsifier_colonnes_locales_dart.py",
    "falsifier_synchronisation_service_dart.py",
    "falsifier_correspondance_types_dart.py",
    "falsifier_dates_distantes_dart.py",
    "falsifier_transport_supabase_dart.py",
    "falsifier_client_authentification_dart.py",
    "falsifier_version_build.py",
    "falsifier_check_workflows.py",
    "falsifier_client_deepseek.py",
    "falsifier_migration_serveur.py",
    "falsifier_epreuve_migrations.py",
]


def bancs_non_declares() -> list[str]:
    """Les bancs presents dans `tools/bancs/` mais absents de `ORDRE`.

    Le lanceur ne parcourt pas le dossier : il suit `ORDRE`. Sans cette
    fermeture, un banc ajoute plus tard ne serait jamais lance, et le rapport
    final — « N bancs, tous verts » — porterait sur un ensemble incomplet sans
    que rien ne le signale.
    """
    presents = {chemin.name for chemin in BANCS.glob("falsifier_*.py")}
    return sorted(presents - set(ORDRE))


def main() -> int:
    resultats: list[tuple[str, int]] = []

    manquants = [nom for nom in ORDRE if not (BANCS / nom).is_file()]
    non_declares = bancs_non_declares()

    if manquants or non_declares:
        for nom in manquants:
            print(f"  ABSENT        {nom} — declare dans ORDRE, introuvable", file=sys.stderr)
        for nom in non_declares:
            print(
                f"  NON DECLARE   {nom} — present, mais absent de ORDRE : "
                "il ne serait jamais lance",
                file=sys.stderr,
            )
        return 1

    try:
        import yaml  # noqa: F401
    except ImportError:
        print(
            "PyYAML absent pour l'interpreteur qui lance ce script "
            f"({sys.executable}).\n"
            "`falsifier_check_workflows.py` eprouve un controle qui lit du YAML : "
            "sans PyYAML, ce controle sort en 1 sans marqueur et tous ses cas se "
            "liraient « non detecte ».\n"
            "Utiliser l'interpreteur du projet, ou installer pyyaml.",
            file=sys.stderr,
        )
        return 1

    for nom in ORDRE:
        chemin = BANCS / nom
        if not chemin.is_file():
            print(f"  ABSENT  {nom}", file=sys.stderr)
            resultats.append((nom, 1))
            continue

        print(f"\n=== {nom} ===", flush=True)
        resultat = subprocess.run(
            [sys.executable, str(chemin)],
            cwd=RACINE,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        sortie = (resultat.stdout or "").strip().splitlines()
        for ligne in sortie:
            print(f"    {ligne}")
        if resultat.stderr.strip():
            for ligne in resultat.stderr.strip().splitlines():
                print(f"    ! {ligne}", file=sys.stderr)

        resultats.append((nom, resultat.returncode))

    print("\n" + "=" * 60)
    for nom, code in resultats:
        print(f"  {'vert' if code == 0 else f'ECHEC (code {code})':<14} {nom}")

    rates = [nom for nom, code in resultats if code != 0]
    print()
    if rates:
        print(f"{len(rates)} banc(s) en echec sur {len(resultats)}.", file=sys.stderr)
        return 1
    print(f"{len(resultats)} bancs, tous verts.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
