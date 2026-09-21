#!/usr/bin/env python3
"""Ce que `flutter test` reclame en plus, sous Windows, pour pouvoir demarrer.

Deux obstacles, tous deux sans rapport avec le projet, et tous deux trompeurs
par leur message d'erreur.

1. `%PROGRAMFILES(X86)% environment variable not found.`

   Le message accuse Visual Studio. En realite, les paquets `objective_c` et
   `sqlite3` declarent des hooks de ressources natives, et `flutter_tools` lit
   cette variable **avant** de chercher `vswhere.exe` : son absence suffit a
   faire echouer la commande. La fournir suffit a passer, car un `vswhere.exe`
   introuvable est explicitement ignore par le SDK.

2. `WebSocketException: Invalid WebSocket upgrade request`

   Une fois le premier point franchi, le processus de test demarre puis tente de
   rejoindre son propre port d'ecoute. Si l'environnement definit `HTTP_PROXY`
   sans `NO_PROXY`, cette connexion part vers le proxy et se fait repondre 400.
   On exclut donc le loopback.

Ce module est partage par `tools/lancer_verifications_dart.py` et par les bancs
de falsification, pour que tous mesurent dans les memes conditions.
"""

from __future__ import annotations

import os
import shutil
from pathlib import Path

LOOPBACK = ("127.0.0.1", "localhost", "::1")


def executable_flutter() -> Path | None:
    """Le SDK local s'il existe, sinon celui du PATH (executeur Linux)."""
    local = Path.home() / ".workbuddy-ai" / "binaries" / "flutter" / "bin"
    for nom in ("flutter.bat", "flutter"):
        candidat = local / nom
        if candidat.exists():
            return candidat
    trouve = shutil.which("flutter")
    return Path(trouve) if trouve else None


def environnement_mesure() -> dict[str, str]:
    """Environnement corrige : variables Windows posees, loopback hors proxy."""
    env = dict(os.environ)

    if os.name == "nt":
        env.setdefault("PROGRAMFILES(X86)", r"C:\Program Files (x86)")
        env.setdefault("ProgramFiles", r"C:\Program Files")

    # On complete la liste existante au lieu de l'ecraser : un executeur peut
    # deja en avoir une, et la remplacer casserait ses propres exclusions.
    existant = env.get("NO_PROXY") or env.get("no_proxy") or ""
    hotes = [hote for hote in existant.split(",") if hote]
    for hote in LOOPBACK:
        if hote not in hotes:
            hotes.append(hote)
    env["NO_PROXY"] = ",".join(hotes)
    env["no_proxy"] = env["NO_PROXY"]

    return env
