#!/usr/bin/env python3
"""Valide les fichiers de workflow GitHub Actions avant de pousser.

Ce controle attrape deux familles de defauts, dont le cout n'a rien a voir :

  - un YAML mal forme : le flux ne demarre pas, l'erreur est immediate et claire ;
  - un script `run:` invalide : le flux demarre, installe Java, le SDK Android,
    les dependances, puis echoue vingt minutes plus tard sur une quote non
    fermee. C'est ce cas qui justifie le controle.

Ce qu'il verifie :
  1. le YAML est analysable ;
  2. chaque flux declare un nom, un declencheur et au moins un job ;
  3. chaque job declare un runner et au moins une etape ;
  4. chaque etape fait quelque chose (`uses` ou `run`) ;
  5. chaque action est epinglee a une version (`@v4`), jamais laissee nue ;
  6. `permissions` est declare, en racine ou dans le job ;
  7. la liste des flux attendus est close, dans les DEUX sens : un flux attendu
     absent echoue, un flux present mais non declare echoue aussi ;
  8. chaque script `run:` est accepte par `bash -n`, analyse sans execution ;
  9. chaque script du depot appele par un flux existe reellement ;
 10. `android.yml` et `ios.yml` tirent la version du MEME endroit ;
 11. toute commande `flutter build` qui compile un `APP_ENV` recoit aussi un
     `APP_VERSION`, et cette valeur vient de `steps.version.outputs.version`.

Ce qu'il ne voit PAS : `bash -n` n'evalue aucune expansion. Une faute de frappe
dans `${CHEMIN}` ou `${{ secrets.X }}` n'est signalee ni ici, ni par un
compilateur, ni par un linter. Le controle attrape une quote non fermee, un
`then` manquant, un `fi` orphelin — pas une variable mal nommee.

Pourquoi la liste close du point 7 : un controle qui decouvre ses sujets par
`readdir` mesure ce qui RESTE, jamais ce qui MANQUE. Si `ios.yml` disparaissait,
le controle annoncerait « tous les flux sont valides ». Or rien d'autre dans la
chaine ne lit `.github/workflows` : c'est ici, et seulement ici, que la
disparition se verrait.

Pourquoi le point 9 : `bash -n` analyse la syntaxe d'un script, pas la presence
du fichier qu'il appelle. Un `bash tools/version_build.sh` vers un script
renomme passe `bash -n` sans broncher, puis echoue dans le flux — apres
l'installation du SDK, sur un message qui ne nomme pas la cause.

Pourquoi le point 10 : le nom de l'artefact venait du tag et la version inscrite
dans le binaire venait du pubspec, si bien que le tag `v0.1.1` a produit des
binaires qui s'annoncaient `0.1.0`. La logique vit maintenant dans un script
partage, et ce point verifie que les deux flux l'appellent bien : recopiee, elle
divergerait, et la divergence ne se verrait qu'a la publication.

Pourquoi le point 11 : le point 10 garantit que le binaire porte la bonne
version ; il ne dit rien de ce que l'application **affiche**. L'ecran des
reglages annoncait `0.1.0` ecrit en dur alors que le binaire etait `0.1.2` — le
seul endroit ou l'utilisateur peut lire la version de ce qu'il a installe
mentait. Le `--dart-define` relie les deux, mais rien n'oblige une commande de
compilation a le passer : la suivante pourrait l'oublier et l'ecran se
remettrait a mentir sans qu'aucun flux ne rougisse. Ce point rend l'oubli
impossible, et refuse en plus une valeur recopiee en dur — recopiee, elle
finirait par diverger, ce qui est precisement l'histoire de ce defaut.

Usage : python3 tools/check_workflows.py
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKFLOWS_DIR = ROOT / ".github" / "workflows"

# Liste close. Ajouter un flux est un geste delibere : il faut le declarer ici.
FLUX_ATTENDUS = ["android.yml", "ci.yml", "ios.yml"]

# Un appel a un script du depot, dans une etape `run:`. Le motif exige un
# interpreteur devant le chemin : sans cela il accrocherait aussi les chemins
# cites dans un commentaire ou un `test -f`.
MOTIF_SCRIPT_DEPOT = re.compile(r"\b(?:bash|sh|python3?)\s+(tools/[A-Za-z0-9_./-]+)")

# Le point unique qui decide de la version des deux plateformes, et les flux qui
# doivent l'appeler.
SCRIPT_VERSION = "tools/version_build.sh"
FLUX_AVEC_VERSION = ["android.yml", "ios.yml"]

# La version telle que l'application l'affiche, et la seule source acceptee.
# Une valeur litterale (`APP_VERSION=0.1.2`) est refusee : elle ne serait reliee
# a rien, donc elle mentirait au premier oubli de mise a jour.
#
# Le motif accepte une expression GitHub **entiere** avant de se rabattre sur
# une suite sans espace : `${{ steps.version.outputs.version }}` contient une
# espace, si bien qu'un `\S+` seul n'en capturait que `${{`. Mesure faite : le
# controle refusait alors les quatre commandes pourtant correctes — un controle
# qui crie a tort finit par etre contourne, pas ecoute.
MOTIF_DEFINE_VERSION = re.compile(
    r"--dart-define=APP_VERSION=(?P<valeur>\$\{\{[^}]*\}\}|\S+)"
)
VALEUR_VERSION_ATTENDUE = "${{ steps.version.outputs.version }}"

# Marqueurs ASCII : un banc s'y accroche sans dependre de l'encodage ni de la
# reformulation d'une phrase.
MARQUEURS = {
    "yaml": "[yaml-invalide]",
    "nom": "[nom-absent]",
    "declencheur": "[declencheur-absent]",
    "jobs": "[jobs-absents]",
    "runner": "[runner-absent]",
    "etapes": "[etapes-absentes]",
    "etape-vide": "[etape-vide]",
    "action-non-epinglee": "[action-non-epinglee]",
    "permissions": "[permissions-absentes]",
    "script": "[script-invalide]",
    "flux-absent": "[flux-absent]",
    "flux-non-declare": "[flux-non-declare]",
    "script-depot-absent": "[script-depot-absent]",
    "version-non-partagee": "[version-non-partagee]",
    "version-non-injectee": "[version-non-injectee]",
}

try:
    import yaml  # type: ignore
except ImportError:  # pragma: no cover
    yaml = None


class Rapport:
    """Compte les verifications, pour que le resultat soit croyable.

    Un rapport qui annonce seulement « OK » ne dit pas s'il a regarde quelque
    chose. Un compte se confronte d'un coup d'oeil au nombre de `run:` du depot.
    """

    def __init__(self) -> None:
        self.verifications = 0
        self.defauts: list[str] = []
        self.ignores: list[str] = []

    def verifie(self) -> None:
        self.verifications += 1

    def defaut(self, marqueur: str, message: str) -> None:
        self.defauts.append(f"{MARQUEURS[marqueur]} {message}")

    def ignore(self, message: str) -> None:
        self.ignores.append(message)


def neutraliser(script: str) -> str:
    """Remplace les expressions GitHub par une valeur inerte.

    Ce n'est pas pour eviter un faux positif — `bash -n` tolere `${{ ... }}`,
    c'est mesure. C'est pour la fidelite : analyser le texte substitue, c'est
    analyser ce que le shell verra reellement.
    """
    return re.sub(r"\$\{\{[^}]*\}\}", "VALEUR", script)


def syntaxe_bash_valide(script: str, bash: str) -> tuple[bool, str]:
    """Passe le script a `bash -n`. Ne l'execute pas."""
    with tempfile.NamedTemporaryFile(
        "w", suffix=".sh", encoding="utf-8", newline="\n", delete=False
    ) as fichier:
        fichier.write(neutraliser(script))
        chemin = Path(fichier.name)

    try:
        resultat = subprocess.run(
            [bash, "-n", str(chemin)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError) as erreur:
        return False, f"impossible d'executer bash : {erreur}"
    finally:
        chemin.unlink(missing_ok=True)

    if resultat.returncode == 0:
        return True, ""

    detail = (resultat.stderr or resultat.stdout or "").strip().splitlines()
    return False, detail[0] if detail else "refuse par bash -n"


def commandes_de_compilation(script: str) -> list[str]:
    """Reconstitue chaque commande `flutter build …` avec ses continuations.

    Une commande est decoupee sur plusieurs lignes par des barres obliques
    inverses : la lire ligne a ligne ferait manquer le `--dart-define` pose
    trois lignes plus bas, et le controle signalerait un oubli qui n'existe
    pas. Une commande se termine a la premiere ligne qui ne se continue pas.
    """
    commandes: list[str] = []
    courante: list[str] | None = None

    for ligne in script.splitlines():
        if courante is None:
            if "flutter build" not in ligne:
                continue
            courante = [ligne]
        else:
            courante.append(ligne)

        if not ligne.rstrip().endswith("\\"):
            commandes.append("\n".join(courante))
            courante = None

    if courante is not None:
        # Derniere ligne du bloc qui se termine par une continuation : le script
        # est de toute facon refuse par `bash -n`, mais ne rien rendre ici
        # ferait disparaitre la commande du compte sans le dire.
        commandes.append("\n".join(courante))

    return commandes


def verifier_flux(
    chemin: Path, document: object, rapport: Rapport, bash: str | None
) -> None:
    nom = chemin.name

    if not isinstance(document, dict):
        rapport.verifie()
        rapport.defaut("yaml", f"{nom} : le document racine doit etre un objet")
        return

    rapport.verifie()
    if "name" not in document:
        rapport.defaut("nom", f"{nom} : cle 'name' manquante")

    # PyYAML implemente YAML 1.1, ou `on` est un booleen : la cle ressort en
    # `True`. Accepter les deux formes, sinon le controle crierait a tort.
    rapport.verifie()
    if "on" not in document and True not in document:
        rapport.defaut("declencheur", f"{nom} : declencheur 'on' manquant")

    jobs = document.get("jobs")
    rapport.verifie()
    if not isinstance(jobs, dict) or not jobs:
        rapport.defaut("jobs", f"{nom} : aucun job declare")
        return

    # `permissions` peut etre pose en racine ou dans chaque job.
    permissions_racine = "permissions" in document
    rapport.verifie()

    for nom_job, job in jobs.items():
        if not isinstance(job, dict):
            rapport.verifie()
            rapport.defaut("jobs", f"{nom} : job '{nom_job}' mal forme")
            continue

        rapport.verifie()
        if "runs-on" not in job:
            rapport.defaut("runner", f"{nom} : job '{nom_job}' sans 'runs-on'")

        if not permissions_racine:
            rapport.verifie()
            if "permissions" not in job:
                rapport.defaut(
                    "permissions",
                    f"{nom} : job '{nom_job}' sans 'permissions' "
                    "(le jeton recoit alors des droits plus larges que necessaire)",
                )

        etapes = job.get("steps")
        rapport.verifie()
        if not isinstance(etapes, list) or not etapes:
            rapport.defaut("etapes", f"{nom} : job '{nom_job}' sans etapes")
            continue

        for index, etape in enumerate(etapes, start=1):
            if not isinstance(etape, dict):
                rapport.verifie()
                rapport.defaut(
                    "etape-vide", f"{nom} : job '{nom_job}', etape {index} mal formee"
                )
                continue

            libelle = etape.get("name") or f"etape {index}"
            a_uses = "uses" in etape
            a_run = "run" in etape

            rapport.verifie()
            if not a_uses and not a_run:
                rapport.defaut(
                    "etape-vide",
                    f"{nom} : job '{nom_job}', {libelle} ne fait rien "
                    "(ni 'uses' ni 'run')",
                )

            if a_uses:
                rapport.verifie()
                reference = str(etape.get("uses", ""))
                # Une action locale (`./…`) ou une image Docker n'a pas de
                # version a epingler ; tout le reste en a besoin.
                locale = reference.startswith("./") or reference.startswith("docker://")
                if not locale and "@" not in reference:
                    rapport.defaut(
                        "action-non-epinglee",
                        f"{nom} : {libelle} utilise '{reference}' sans version",
                    )

            if a_run:
                script = etape.get("run")
                rapport.verifie()
                if not isinstance(script, str) or not script.strip():
                    rapport.defaut(
                        "etape-vide", f"{nom} : job '{nom_job}', {libelle} a un 'run' vide"
                    )
                    continue

                shell = str(etape.get("shell", ""))
                if shell and "bash" not in shell and "sh" not in shell:
                    rapport.ignore(
                        f"{nom} › {libelle} : shell '{shell}', non analyse par bash -n"
                    )
                    continue

                if bash is None:
                    rapport.ignore(f"{nom} › {libelle} : bash introuvable, non analyse")
                    continue

                ok, erreur = syntaxe_bash_valide(script, bash)
                if not ok:
                    rapport.defaut(
                        "script",
                        f"{nom} : job '{nom_job}', {libelle} refuse par bash -n — {erreur}",
                    )

                # `bash -n` valide la syntaxe, pas la presence du fichier
                # appele. Un script renomme passerait ici, puis echouerait dans
                # le flux, apres l'installation du SDK.
                for reference in MOTIF_SCRIPT_DEPOT.findall(script):
                    rapport.verifie()
                    if not (ROOT / reference).is_file():
                        rapport.defaut(
                            "script-depot-absent",
                            f"{nom} : {libelle} appelle '{reference}', "
                            "qui n'existe pas dans le depot",
                        )

                # Une commande qui compile un environnement doit aussi compiler
                # la version : c'est la seule chose qui relie ce que l'ecran
                # affiche a ce que le paquet declare.
                for numero, commande in enumerate(
                    commandes_de_compilation(script), start=1
                ):
                    rapport.verifie()

                    if "--dart-define=APP_ENV=" not in commande:
                        continue

                    trouve = MOTIF_DEFINE_VERSION.search(commande)
                    if trouve is None:
                        rapport.defaut(
                            "version-non-injectee",
                            f"{nom} : {libelle}, compilation n°{numero} recoit "
                            "un APP_ENV mais aucun APP_VERSION — l'ecran des "
                            "reglages annoncerait une version sans rapport avec "
                            "le binaire installe",
                        )
                        continue

                    valeur = trouve.group("valeur")
                    if valeur != VALEUR_VERSION_ATTENDUE:
                        rapport.defaut(
                            "version-non-injectee",
                            f"{nom} : {libelle}, compilation n°{numero} passe "
                            f"APP_VERSION={valeur} au lieu de "
                            f"{VALEUR_VERSION_ATTENDUE} — une valeur recopiee "
                            "n'est reliee a aucune source, donc elle divergera",
                        )


def main() -> int:
    if not WORKFLOWS_DIR.is_dir():
        print(f"{MARQUEURS['flux-absent']} dossier introuvable : {WORKFLOWS_DIR}", file=sys.stderr)
        return 1

    presents = sorted(
        chemin.name
        for chemin in WORKFLOWS_DIR.iterdir()
        if chemin.suffix in (".yml", ".yaml")
    )

    rapport = Rapport()

    # Fermeture de la liste, dans les deux sens.
    for attendu in FLUX_ATTENDUS:
        rapport.verifie()
        if attendu not in presents:
            rapport.defaut("flux-absent", f"{attendu} — flux attendu, absent du dossier")
    for present in presents:
        rapport.verifie()
        if present not in FLUX_ATTENDUS:
            rapport.defaut(
                "flux-non-declare",
                f"{present} — present mais non declare dans FLUX_ATTENDUS",
            )

    if yaml is None:
        print(
            "PyYAML absent : analyse structurelle et syntaxique impossible. "
            "Installez pyyaml pour un controle complet.",
            file=sys.stderr,
        )
        print("  (les verifications de structure et de script ont ete ignorees)")
        return 1

    bash = shutil.which("bash")
    if bash is None:
        print("bash introuvable : les scripts 'run' ne seront pas analyses.", file=sys.stderr)

    # Le script de version doit exister avant que quiconque l'appelle : sans ce
    # controle, une suppression se lirait comme « aucun flux ne l'appelle »,
    # donc comme un accord rompu, et non comme un fichier manquant.
    rapport.verifie()
    if not (ROOT / SCRIPT_VERSION).is_file():
        rapport.defaut(
            "script-depot-absent", f"{SCRIPT_VERSION} est absent du depot"
        )

    for nom in presents:
        chemin = WORKFLOWS_DIR / nom
        rapport.verifie()
        try:
            with open(chemin, encoding="utf-8") as fichier:
                document = yaml.safe_load(fichier)
        except yaml.YAMLError as erreur:
            rapport.defaut("yaml", f"{nom} : YAML invalide — {erreur}")
            continue
        verifier_flux(chemin, document, rapport, bash)

    # --- accord entre les deux flux de publication -------------------------
    #
    # Le tag etait la source du nom, le pubspec celle de la version inscrite :
    # deux binaires d'un meme tag annoncaient deux versions. Les deux flux
    # doivent desormais passer par le meme script. L'un des deux qui
    # retournerait a une logique locale rouvrirait exactement ce defaut, et rien
    # d'autre ne le verrait — le flux resterait vert.
    for nom in FLUX_AVEC_VERSION:
        rapport.verifie()
        chemin = WORKFLOWS_DIR / nom
        if not chemin.is_file():
            # Deja signale par la liste close du point 7.
            continue
        if SCRIPT_VERSION not in chemin.read_text(encoding="utf-8"):
            rapport.defaut(
                "version-non-partagee",
                f"{nom} n'appelle pas {SCRIPT_VERSION} : sa version pourrait "
                "diverger de celle de l'autre plateforme pour un meme tag",
            )

    if rapport.defauts:
        print("Workflows invalides :", file=sys.stderr)
        for defaut in rapport.defauts:
            print(f"  - {defaut}", file=sys.stderr)
        print(
            f"\n{len(rapport.defauts)} defaut(s), {rapport.verifications} verifications, "
            f"sur {len(presents)} flux de travail.",
            file=sys.stderr,
        )
        return 1

    for nom in presents:
        print(f"  OK  {nom}")
    for ignore in rapport.ignores:
        print(f"  --  {ignore}")
    print(
        f"\n{rapport.verifications} verifications sur {len(presents)} flux de travail "
        "— tous valides."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
