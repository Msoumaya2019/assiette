#!/usr/bin/env python3
"""Genere la base nutritionnelle locale de l'application a partir de la table Ciqual.

Source : table de composition nutritionnelle Ciqual 2020, ANSES.
Licence : Licence Ouverte / Open Licence 2.0 (Etalab) - reutilisation libre,
attribution obligatoire (voir assets/nutrition/ATTRIBUTION.md).

Entree  : les 3 fichiers XML extraits de XML_2020_07_07.zip
Sortie  : assets/nutrition/ciqual.json (compact, embarque dans l'application)

Usage :
    python tools/build_ciqual.py --src <dossier_xml> --out <dossier_sortie>
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import unicodedata

# Constituants Ciqual retenus (code -> cle de sortie)
CONSTITUENTS = {
    "328": "kcal",      # Energie (kcal/100 g)
    "25000": "protein",  # Proteines (g/100 g)
    "31000": "carbs",    # Glucides (g/100 g)
    "32000": "sugars",   # Sucres (g/100 g)
    "33110": "starch",   # Amidon (g/100 g)
    "34100": "fiber",    # Fibres alimentaires (g/100 g)
    "40000": "fat",      # Lipides (g/100 g)
    "10004": "salt",     # Sel chlorure de sodium (g/100 g)
}

SOURCE_NAME = "Ciqual 2020 - ANSES"
SOURCE_URL = "https://ciqual.anses.fr/"
SOURCE_LICENSE = "Licence Ouverte / Open Licence 2.0 (Etalab)"
SOURCE_VERSION = "2020-07-07"

ALIM_RE = re.compile(
    r"<alim_code>\s*(\d+)\s*</alim_code>\s*"
    r"<alim_nom_fr>(.*?)</alim_nom_fr>.*?"
    r"<alim_grp_code>\s*(\d+)\s*</alim_grp_code>",
    re.S,
)
COMPO_RE = re.compile(
    r"<alim_code>\s*(\d+)\s*</alim_code>\s*"
    r"<const_code>\s*(\d+)\s*</const_code>\s*"
    r"<teneur>\s*([^<]*?)\s*</teneur>",
    re.S,
)
GRP_RE = re.compile(
    r"<alim_grp_code>\s*(\d+)\s*</alim_grp_code>\s*"
    r"<alim_grp_nom_fr>(.*?)</alim_grp_nom_fr>",
    re.S,
)


def read_text(path: str) -> str:
    """Les XML Ciqual sont declares en windows-1252."""
    with open(path, "rb") as handle:
        raw = handle.read()
    for encoding in ("windows-1252", "utf-8"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue
    return raw.decode("windows-1252", errors="replace")


def normalize(text: str) -> str:
    """Minuscule sans accents, pour une recherche tolerante en francais."""
    decomposed = unicodedata.normalize("NFD", text.lower())
    stripped = "".join(c for c in decomposed if unicodedata.category(c) != "Mn")
    return re.sub(r"\s+", " ", stripped).strip()


def parse_float(value: str) -> float | None:
    value = value.strip().replace(",", ".")
    if not value or value in {"-", "traces", "TRACES"}:
        return None
    try:
        return float(value)
    except ValueError:
        return None


def build(src: str, out_dir: str) -> dict:
    alim = read_text(os.path.join(src, "alim_2020_07_07.xml"))
    compo = read_text(os.path.join(src, "compo_2020_07_07.xml"))
    groups_raw = read_text(os.path.join(src, "alim_grp_2020_07_07.xml"))

    groups = {code: name.strip() for code, name in GRP_RE.findall(groups_raw)}

    foods: dict[str, dict] = {}
    for code, name, grp in ALIM_RE.findall(alim):
        name = name.strip()
        if not name:
            continue
        foods[code] = {
            "code": code,
            "name": name,
            "n": normalize(name),
            "group": grp,
            "groupName": groups.get(grp, ""),
        }

    kept = 0
    for alim_code, const_code, teneur in COMPO_RE.findall(compo):
        key = CONSTITUENTS.get(const_code)
        if key is None:
            continue
        food = foods.get(alim_code)
        if food is None:
            continue
        value = parse_float(teneur)
        if value is None:
            continue
        food[key] = value
        kept += 1

    # Les nutriments absents sont ramenes a 0 pour simplifier les calculs cote
    # application (une valeur absente dans Ciqual signifie "non mesure", et
    # l'application affiche alors 0 avec la mention "donnee non disponible").
    for food in foods.values():
        for key in CONSTITUENTS.values():
            food.setdefault(key, 0.0)

    ordered = sorted(foods.values(), key=lambda f: f["name"].lower())

    payload = {
        "source": SOURCE_NAME,
        "sourceUrl": SOURCE_URL,
        "license": SOURCE_LICENSE,
        "version": SOURCE_VERSION,
        "unit": "per_100g",
        "count": len(ordered),
        "foods": ordered,
    }

    os.makedirs(out_dir, exist_ok=True)
    target = os.path.join(out_dir, "ciqual.json")
    with open(target, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))

    print(f"aliments : {len(ordered)}")
    print(f"valeurs  : {kept}")
    print(f"fichier  : {target} ({os.path.getsize(target)} octets)")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Construit ciqual.json")
    parser.add_argument("--src", required=True, help="dossier des XML Ciqual")
    parser.add_argument("--out", required=True, help="dossier de sortie")
    args = parser.parse_args()
    build(args.src, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
