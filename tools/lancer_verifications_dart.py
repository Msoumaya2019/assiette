#!/usr/bin/env python3
"""Rejoue localement les trois etapes Dart de la CI.

`ci.yml` execute, dans cet ordre et dans `app/` :

    dart format --output=none --set-exit-if-changed lib test
    flutter analyze --no-fatal-infos
    flutter test --coverage

Les rejouer a la main sous Git Bash se heurte a deux obstacles :

  - `dart` n'est pas dans le PATH (le SDK local n'y est pas), et `bin/dart` est
    un script shell que Git Bash n'execute pas — il faut passer par
    `bin/cache/dart-sdk/bin/dart.exe` ;
  - `flutter` reclame deux variables d'environnement, dont une dont le nom
    contient des parentheses : `export PROGRAMFILES(X86)=…` est refuse par bash
    comme une erreur de syntaxe, ce qui n'a rien a voir avec la compilation.

Ce script resout les deux, dans le meme environnement que le banc de
falsification, et lit chaque code de sortie **directement** — jamais apres un
tube, qui rendrait celui du tube.

Usage :
    python3 tools/lancer_verifications_dart.py            # les trois etapes
    python3 tools/lancer_verifications_dart.py format     # une seule
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from environnement_flutter import executable_flutter, environnement_mesure  # noqa: E402

RACINE = Path(__file__).resolve().parent.parent
APP = RACINE / "app"


def executable_dart() -> Path | None:
    """`dart.exe` du SDK local, sinon celui du PATH (executeur Linux).

    `bin/dart` n'est pas un binaire : c'est un script shell que Git Bash refuse
    d'executer, avec un `No such file or directory` et un code 127 qui ne nomme
    pas la cause.
    """
    flutter = executable_flutter()
    if flutter is not None:
        sdk = flutter.parent / "cache" / "dart-sdk" / "bin"
        for nom in ("dart.exe", "dart"):
            candidat = sdk / nom
            if candidat.exists():
                return candidat
    from shutil import which

    trouve = which("dart")
    return Path(trouve) if trouve else None


ETAPES: dict[str, tuple[list[str], str]] = {
    "format": (["format", "--output=none", "--set-exit-if-changed", "lib", "test"], "dart"),
    "analyze": (["analyze", "--no-fatal-infos"], "flutter"),
    "test": (["test", "--coverage"], "flutter"),
}

ORDRE = ("format", "analyze", "test")


def main(demandees: list[str]) -> int:
    if not APP.is_dir():
        print(f"dossier introuvable : {APP}", file=sys.stderr)
        return 2

    inconnues = [nom for nom in demandees if nom not in ETAPES]
    if inconnues:
        print(
            f"etape inconnue : {', '.join(inconnues)} "
            f"(connues : {', '.join(ORDRE)})",
            file=sys.stderr,
        )
        return 2

    dart = executable_dart()
    flutter = executable_flutter()
    if dart is None or flutter is None:
        print(
            "SDK introuvable : dart ou flutter absent, ni dans le SDK local ni "
            "dans le PATH.",
            file=sys.stderr,
        )
        return 2

    a_lancer = list(demandees) if demandees else list(ORDRE)
    resultats: list[tuple[str, int]] = []

    for nom in a_lancer:
        arguments, outil = ETAPES[nom]
        commande = [str(dart if outil == "dart" else flutter), *arguments]
        print(f"\n=== {nom} ===", flush=True)
        print(f"    {' '.join(commande)}", flush=True)
        resultat = subprocess.run(
            commande,
            cwd=APP,
            env=environnement_mesure(),
            check=False,
        )
        resultats.append((nom, resultat.returncode))

    print("\n" + "=" * 60)
    for nom, code in resultats:
        print(f"  {'vert' if code == 0 else f'ECHEC (code {code})':<14} {nom}")

    rates = [nom for nom, code in resultats if code != 0]
    if rates:
        print(f"\n{len(rates)} etape(s) en echec sur {len(resultats)}.", file=sys.stderr)
        return 1

    print(f"\n{len(resultats)} etape(s), toutes vertes.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
