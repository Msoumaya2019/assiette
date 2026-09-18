#!/usr/bin/env python3
"""Detecte les secrets qui auraient ete commites par erreur.

Le depot est public : un secret pousse est un secret brule, meme apres
suppression du commit. Ce controle tourne en CI a chaque push et refuse la
construction si un motif ressemble a une cle ou a un fichier sensible.

Il ne remplace pas une revue humaine, il attrape les oublis mecaniques.

Usage : python3 tools/check_no_secrets.py
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Fichiers qui ne doivent jamais etre suivis par Git.
FORBIDDEN_NAMES = {
    ".env",
    "key.properties",
    "local.properties",
    "google-services.json",
    "GoogleService-Info.plist",
}
FORBIDDEN_SUFFIXES = (".p12", ".keystore", ".jks", ".mobileprovision", ".p8", ".pem", ".key")

# Motifs de secrets, exprimes de facon suffisamment precise pour ne pas
# declencher sur du code legitime.
SECRET_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("cle DeepSeek", re.compile(r"\bsk-[A-Za-z0-9]{20,}\b")),
    ("cle OpenAI", re.compile(r"\bsk-proj-[A-Za-z0-9_\-]{20,}\b")),
    ("cle Google", re.compile(r"\bAIza[0-9A-Za-z_\-]{30,}\b")),
    ("cle Anthropic", re.compile(r"\bsk-ant-[A-Za-z0-9_\-]{20,}\b")),
    ("jeton GitHub", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}\b")),
    ("jeton Slack", re.compile(r"\bxox[baprs]-[A-Za-z0-9\-]{10,}\b")),
    ("cle AWS", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("cle privee", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----")),
    ("service role Supabase", re.compile(r"\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{20,}\b")),
    ("secret en dur", re.compile(r"(?i)\b(api[_-]?key|secret|password|passwd|token)\s*[:=]\s*['\"][^'\"]{16,}['\"]")),
]

# Fichiers ou un motif ressemble a un faux positif legitime.
ALLOWLISTED_FILES = {
    "tools/check_no_secrets.py",
    "app/lib/core/config/app_config.dart",
}
ALLOWLISTED_MARKERS = (
    "example",
    "placeholder",
    "votre_cle",
    "your_key",
    "changeme",
    "xxxx",
    "redacted",
    "REMPLACER",
)

TEXT_SUFFIXES = {
    ".dart", ".ts", ".js", ".py", ".json", ".yaml", ".yml", ".md", ".txt",
    ".sh", ".env", ".xml", ".plist", ".gradle", ".kts", ".properties", ".toml",
}


def tracked_files() -> list[Path]:
    """Fichiers suivis par Git, ou parcours disque si Git est indisponible."""
    try:
        output = subprocess.run(
            ["git", "ls-files", "-z"],
            cwd=ROOT,
            capture_output=True,
            check=True,
        ).stdout.decode("utf-8", errors="replace")
        names = [n for n in output.split("\0") if n]
        if names:
            return [ROOT / n for n in names]
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass

    skip = {".git", "build", ".dart_tool", "node_modules", "Pods", ".gradle"}
    return [
        path
        for path in ROOT.rglob("*")
        if path.is_file() and not any(part in skip for part in path.parts)
    ]


def main() -> int:
    problems: list[str] = []

    for path in tracked_files():
        relative = path.relative_to(ROOT).as_posix()

        if path.name in FORBIDDEN_NAMES or path.name.endswith(FORBIDDEN_SUFFIXES):
            problems.append(f"fichier sensible suivi par Git : {relative}")
            continue

        if relative in ALLOWLISTED_FILES:
            continue
        if path.suffix.lower() not in TEXT_SUFFIXES:
            continue

        try:
            content = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue

        for label, pattern in SECRET_PATTERNS:
            for match in pattern.finditer(content):
                snippet = match.group(0)
                if any(marker in snippet.lower() for marker in ALLOWLISTED_MARKERS):
                    continue
                line = content[: match.start()].count("\n") + 1
                problems.append(f"{label} possible dans {relative}:{line} -> {snippet[:24]}...")

    if problems:
        print("Secrets potentiels detectes :", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        print(
            "\nSi ce sont de faux positifs, ajoutez le fichier a ALLOWLISTED_FILES.",
            file=sys.stderr,
        )
        return 1

    print("Aucun secret detecte.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
