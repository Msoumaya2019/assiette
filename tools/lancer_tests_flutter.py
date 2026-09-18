#!/usr/bin/env python3
"""Lance `flutter test` avec l'environnement que la machine reclame.

Sans argument, toute la suite est lancee. Avec un argument, seule la cible
indiquee l'est — utile pour boucler vite sur un seul fichier.

    python tools/lancer_tests_flutter.py
    python tools/lancer_tests_flutter.py test/data/deepseek_provider_test.dart

La sortie n'est pas capturee : la progression reste visible.

Le pourquoi des deux reglages est documente dans
`tools/environnement_flutter.py`.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from environnement_flutter import executable_flutter, environnement_mesure  # noqa: E402

RACINE = Path(__file__).resolve().parent.parent
APP = RACINE / "app"


def principal(arguments: list[str]) -> int:
    flutter = executable_flutter()
    if flutter is None:
        print(
            "flutter introuvable : ni dans le SDK local, ni dans le PATH.",
            file=sys.stderr,
        )
        return 2

    if not APP.is_dir():
        print(f"dossier introuvable : {APP}", file=sys.stderr)
        return 2

    commande = [str(flutter), "test", *arguments]
    print(f"commande : {' '.join(commande)}", flush=True)
    print(f"dossier  : {APP}", flush=True)

    resultat = subprocess.run(
        commande,
        cwd=APP,
        env=environnement_mesure(),
        check=False,
    )
    return resultat.returncode


if __name__ == "__main__":
    sys.exit(principal(sys.argv[1:]))
