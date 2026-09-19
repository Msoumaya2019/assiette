#!/usr/bin/env bash
#
# Determine la version a inscrire dans le binaire, et la publie en sorties.
#
# Pourquoi ce script existe
# -------------------------
# Le nom de l'artefact venait du tag, la version inscrite dans le binaire venait
# du pubspec. Le tag `v0.1.1` a donc produit une IPA nommee `v0.1.1` qui
# s'annoncait `0.1.0` : deux sources de verite, et rien pour dire laquelle
# croyait l'utilisateur qui installe. Le tag fait desormais foi pour les DEUX,
# et un seul endroit decide.
#
# Ce script est partage par `android.yml` et `ios.yml`. La logique etait
# d'abord recopiee dans les deux : deux copies divergent toujours, et la
# divergence ne se voit qu'a la publication, quand les deux binaires portent des
# versions differentes pour un meme tag. `check_workflows.py` verifie que les
# deux flux l'appellent bien.
#
# Ordre de priorite
# -----------------
#   1. un tag (`v0.1.2`)          -> la version du tag, numero de compilation = run
#   2. une version imposee a la main -> cette version, numero = run
#   3. sinon                      -> ce que declare `app/pubspec.yaml`
#
# Le numero de compilation est `GITHUB_RUN_NUMBER` sur un tag : Android exige un
# `versionCode` strictement croissant a chaque envoi sur le Play Store, et
# reprendre le numero du pubspec ferait refuser le deuxieme envoi d'un meme tag.
#
# Format : la version doit etre des chiffres separes par des points, le numero un
# entier. Tout autre forme est refusee. Voir le commentaire place avant le
# controle : iOS et Android n'en garderaient pas la meme valeur, et la
# divergence serait silencieuse.
#
# Variables lues (toutes fournies par GitHub Actions) :
#   GITHUB_REF_TYPE, GITHUB_REF_NAME, GITHUB_RUN_NUMBER, GITHUB_OUTPUT
#   BUILD_NAME_IMPOSE (facultatif) : version saisie a la main, prioritaire sur
#                                    le pubspec mais pas sur un tag.
#
# Usage : bash tools/version_build.sh [chemin/vers/pubspec.yaml]

set -euo pipefail

PUBSPEC="${1:-app/pubspec.yaml}"

if [ ! -f "$PUBSPEC" ]; then
  echo "pubspec introuvable : $PUBSPEC" >&2
  exit 1
fi

if [ "${GITHUB_REF_TYPE:-}" = "tag" ]; then
  NAME="${GITHUB_REF_NAME#v}"
  NUM="${GITHUB_RUN_NUMBER:?GITHUB_RUN_NUMBER absent : hors GitHub Actions ?}"
  ORIGINE="tag ${GITHUB_REF_NAME}"
elif [ -n "${BUILD_NAME_IMPOSE:-}" ]; then
  NAME="$BUILD_NAME_IMPOSE"
  NUM="${GITHUB_RUN_NUMBER:?GITHUB_RUN_NUMBER absent : hors GitHub Actions ?}"
  ORIGINE="version imposee a la main"
else
  NAME="$(sed -n 's/^version: *\([0-9][0-9.]*\).*/\1/p' "$PUBSPEC")"
  NUM="$(sed -n 's/^version: *[0-9][0-9.]*+\([0-9][0-9]*\).*/\1/p' "$PUBSPEC")"
  ORIGINE="$PUBSPEC"
fi

# Un `sed` qui ne trouve rien rend une chaine vide, et `flutter build
# --build-name=` echouerait bien plus loin, apres l'installation du SDK. On
# s'arrete ici, avec la cause nommee.
if [ -z "$NAME" ]; then
  echo "Version illisible (source : $ORIGINE)." >&2
  exit 1
fi
if [ -z "$NUM" ]; then
  echo "Numero de compilation illisible (source : $ORIGINE)." >&2
  exit 1
fi

# Format impose : des chiffres separes par des points, rien d'autre.
#
# Ce n'est pas une coquetterie. Pour iOS, Flutter retire **en silence** tout
# caractere hors `[0-9.]` avant d'ecrire `CFBundleShortVersionString` : un tag
# `release-2.0` deviendrait `2.0.0` sur iOS, tandis qu'Android garderait
# `release-2.0` tel quel en `versionName`. Le meme tag produirait donc deux
# versions, sans que rien ne le signale — exactement le defaut que ce script
# existe pour supprimer. Ici, on refuse : un echec nomme vaut mieux qu'une
# divergence muette.
#
# Cela ferme aussi la porte a une valeur saisie a la main du type `../../x` :
# la version finit dans un nom de fichier d'artefact.
if ! printf '%s' "$NAME" | grep -Eq '^[0-9]+(\.[0-9]+)*$'; then
  echo "Version refusee : '$NAME' (source : $ORIGINE)." >&2
  echo "Format attendu : des chiffres separes par des points, par exemple 0.1.2." >&2
  echo "Motif : iOS et Android n'en garderaient pas la meme valeur, en silence." >&2
  exit 1
fi
if ! printf '%s' "$NUM" | grep -Eq '^[0-9]+$'; then
  echo "Numero de compilation refuse : '$NUM' (source : $ORIGINE)." >&2
  echo "Format attendu : un entier, par exemple 42." >&2
  exit 1
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "name=${NAME}"
    echo "number=${NUM}"
    echo "version=${NAME}+${NUM}"
  } >> "$GITHUB_OUTPUT"
fi

echo "source de la version : $ORIGINE"
echo "version inscrite dans le binaire : ${NAME}+${NUM}"
