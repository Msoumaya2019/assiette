#!/usr/bin/env python3
"""Falsifie `tools/check_workflows.py`.

Pourquoi ce banc existe
-----------------------

`check_workflows.py` est le seul controle de la chaine qui lit les flux GitHub
Actions. Il a ete ecrit **apres** que plusieurs defauts reels ont atteint la
publication : un tag `v0.1.1` a produit des binaires qui s'annoncaient `0.1.0`,
et une option `build_name` declaree dans `workflow_dispatch` n'etait lue par
personne. Or ce controle n'avait, jusqu'ici, aucun banc : rien ne prouvait qu'il
detectait les defauts qu'il pretend couvrir. Un controle jamais falsifie peut
regarder au mauvais endroit et compter zero defaut tout aussi tranquillement
qu'un controle juste.

Ce que ce banc eprouve
----------------------

Chaque marqueur du controle est atteint par une mutation qui fabrique le defaut
correspondant. Trois cas meritent d'etre signales :

  - **la version non injectee** : une commande `flutter build` qui recoit un
    `APP_ENV` mais pas d'`APP_VERSION` laisserait l'ecran des reglages annoncer
    une version sans rapport avec le binaire installe — c'est exactement le
    defaut mesure, l'ecran disait `0.1.0` quand le binaire etait `0.1.2` ;
  - **la valeur recopiee** : `APP_VERSION=0.1.2` ecrit en dur doit etre refuse,
    sinon la valeur se desynchronise au premier oubli de mise a jour ;
  - **l'attribution par commande** : deux commandes de compilation dans le meme
    bloc `run:`, l'une portant l'`APP_ENV`, l'autre l'`APP_VERSION`. Un controle
    qui chercherait dans tout le script trouverait les deux et se declarerait
    satisfait. Ce cas prouve qu'il les attribue a la bonne commande.

Les temoins negatifs ne sont pas decoratifs : sans eux, rien ne prouve que le
controle distingue, plutot qu'il ne signale tout ce qu'on ajoute.

Usage : python3 tools/bancs/falsifier_check_workflows.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from banc import RACINE, Banc, empreinte_arbre  # noqa: E402

SCRIPT = RACINE / "tools" / "check_workflows.py"

ANDROID = ".github/workflows/android.yml"
IOS = ".github/workflows/ios.yml"
CI = ".github/workflows/ci.yml"

# Le temoin du cas « flux non declare » : un flux que le banc **fabrique**, et
# qu'il doit donc retirer. Nomme ici parce que le nettoyage de demarrage en a
# besoin — voir `principal`.
FLUX_ESSAI = ".github/workflows/__banc_essai.yml"

# Le point d'insertion des etapes fabriquees. `actions/checkout` ouvre la liste
# des etapes des deux flux, et n'y figure qu'une fois.
ANCRE_ETAPES = b"      - name: Recuperer le depot\n        uses: actions/checkout@v4\n"

VERSION_CORRECTE = b"${{ steps.version.outputs.version }}"


def etapes_supplementaires(corps: bytes) -> bytes:
    """Rend l'ancre d'insertion suivie d'une ou plusieurs etapes."""
    return ANCRE_ETAPES + b"\n" + corps


def principal() -> int:
    banc = Banc(SCRIPT)

    # --- le temoin d'un passage precedent --------------------------------
    #
    # Mesure : une campagne de seize bancs a laisse `__banc_essai.yml` dans
    # l'arbre, et ce banc a refuse de demarrer en l'accusant d'etre un flux non
    # declare — un depot annonce casse par un fichier que ce banc avait
    # lui-meme fabrique.
    #
    # La cause est du cote de l'environnement : sur cette machine, le garde de
    # suppression refuse parfois **sans le dire**, et `Path.unlink()` rend alors
    # la main sans lever. Le banc ne peut donc pas compter sur son propre
    # nettoyage pour la fois d'apres. Il retire son temoin au demarrage, et le
    # dit.
    temoin = RACINE / FLUX_ESSAI
    if temoin.exists():
        print(f"temoin d'un passage precedent, retire : {temoin.name}")
        banc.retirer(temoin)

    # La surface a prouver intacte : ce banc ne touche qu'aux flux.
    avant = empreinte_arbre(RACINE / ".github")

    # --- etat initial ----------------------------------------------------
    #
    # Un controle deja rouge rendrait tous les cas « non detectes » : le banc
    # conclurait a un controle aveugle alors qu'il n'a rien mesure. Le cas le
    # plus probable est l'absence de PyYAML, qui fait sortir le controle en 1
    # avec un message et **sans aucun marqueur**.
    initial = banc.etat_initial()
    print(f"etat initial : code {initial.code}")
    if initial.code != 0:
        print(initial.texte, file=sys.stderr)
        print(
            "le controle echoue deja avant toute mutation : le banc ne "
            "prouverait rien. Verifier que PyYAML est disponible pour "
            "l'interpreteur qui lance ce banc.",
            file=sys.stderr,
        )
        return 2

    # --- le point 11 : la version affichee -------------------------------
    def version_non_injectee() -> None:
        fichier = banc.suivre(ANDROID)
        fichier.muter(
            b"            --dart-define=APP_VERSION=" + VERSION_CORRECTE + b" \\\n",
            b"",
            occurrences=1,
        )

    def version_recopiee_en_dur() -> None:
        fichier = banc.suivre(ANDROID)
        fichier.muter(VERSION_CORRECTE, b"0.1.2", occurrences=1)

    def deux_commandes_dans_un_bloc() -> None:
        """L'`APP_ENV` sur une commande, l'`APP_VERSION` sur la suivante.

        Un controle qui chercherait les deux chaines dans le script entier
        passerait ici. C'est le seul cas qui distingue « la commande porte la
        version » de « le fichier contient la version ».
        """
        fichier = banc.suivre(ANDROID)
        fichier.muter(
            ANCRE_ETAPES,
            etapes_supplementaires(
                b"      - name: Etape ajoutee par le banc\n"
                b"        run: |\n"
                b"          flutter build apk --release \\\n"
                b"            --dart-define=APP_ENV=production\n"
                b"          flutter build appbundle --release \\\n"
                b"            --dart-define=APP_VERSION="
                + VERSION_CORRECTE
                + b"\n"
            ),
        )

    banc.cas("APP_VERSION absente d'une compilation", "[version-non-injectee]", version_non_injectee)
    banc.cas("APP_VERSION recopiee en dur", "[version-non-injectee]", version_recopiee_en_dur)
    banc.cas(
        "APP_ENV et APP_VERSION sur deux commandes",
        "[version-non-injectee]",
        deux_commandes_dans_un_bloc,
    )

    # --- temoins negatifs : le controle ne doit pas crier a tort ----------
    def compilation_sans_app_env() -> None:
        """Une commande `flutter build` sans `APP_ENV` n'a pas a porter la version."""
        fichier = banc.suivre(ANDROID)
        fichier.muter(
            ANCRE_ETAPES,
            etapes_supplementaires(
                b"      - name: Etape ajoutee par le banc\n"
                b"        run: flutter build web --release\n"
            ),
        )

    def compilation_correcte_supplementaire() -> None:
        """Une seconde commande correcte doit etre acceptee.

        Sans ce temoin, un controle qui signalerait **toute** commande ajoutee
        passerait les trois cas ci-dessus et se croirait juste.
        """
        fichier = banc.suivre(ANDROID)
        fichier.muter(
            ANCRE_ETAPES,
            etapes_supplementaires(
                b"      - name: Etape ajoutee par le banc\n"
                b"        run: |\n"
                b"          flutter build apk --release \\\n"
                b"            --dart-define=APP_ENV=production \\\n"
                b"            --dart-define=APP_VERSION="
                + VERSION_CORRECTE
                + b"\n"
            ),
        )

    banc.cas(
        "compilation sans APP_ENV",
        "[version-non-injectee]",
        compilation_sans_app_env,
        attendu=False,
    )
    banc.cas(
        "compilation correcte ajoutee",
        "[version-non-injectee]",
        compilation_correcte_supplementaire,
        attendu=False,
    )

    # --- le point 10 : une seule source de version -----------------------
    def version_locale_reintroduite() -> None:
        """`ios.yml` recalcule sa version au lieu d'appeler le script partage.

        C'est le defaut d'origine, a la lettre : le nom venait du tag et la
        version du pubspec, donc les deux plateformes pouvaient diverger.
        """
        fichier = banc.suivre(IOS)
        fichier.muter(
            b"bash tools/version_build.sh app/pubspec.yaml",
            b"bash -c 'echo version calculee localement'",
        )

    banc.cas("ios.yml n'appelle plus le script partage", "[version-non-partagee]", version_locale_reintroduite)

    # --- les points 1 a 9 -------------------------------------------------
    def script_du_depot_absent() -> None:
        fichier = banc.suivre(ANDROID)
        fichier.muter(
            ANCRE_ETAPES,
            etapes_supplementaires(
                b"      - name: Etape ajoutee par le banc\n"
                b"        run: bash tools/__inexistant_du_banc.sh\n"
            ),
        )

    def script_invalide() -> None:
        fichier = banc.suivre(ANDROID)
        fichier.muter(
            ANCRE_ETAPES,
            etapes_supplementaires(
                b"      - name: Etape ajoutee par le banc\n"
                b"        run: |\n"
                b"          if [ -f app/pubspec.yaml ]; then\n"
                b"            echo present\n"
            ),
        )

    def etape_vide() -> None:
        fichier = banc.suivre(ANDROID)
        fichier.muter(
            ANCRE_ETAPES,
            etapes_supplementaires(b"      - name: Etape ajoutee par le banc\n"),
        )

    def action_non_epinglee() -> None:
        fichier = banc.suivre(ANDROID)
        fichier.muter(b"uses: actions/checkout@v4", b"uses: actions/checkout")

    def permissions_absentes() -> None:
        """`permissions` est en racine : le retirer laisse chaque job sans droits
        declares, ce que le controle doit signaler."""
        fichier = banc.suivre(ANDROID)
        fichier.muter(b"\npermissions:\n  contents: read\n", b"\n")

    def runner_absent() -> None:
        fichier = banc.suivre(ANDROID)
        fichier.muter(b"    runs-on: ubuntu-latest\n", b"")

    def nom_absent() -> None:
        fichier = banc.suivre(ANDROID)
        # La premiere ligne, lue dans le fichier : elle contient un tiret cadratin
        # que recopier a la main risquerait de ne pas reproduire a l'octet.
        premiere = fichier.origine.split(b"\n", 1)[0] + b"\n"
        fichier.muter(premiere, b"")

    def declencheur_absent() -> None:
        # Renommer la cle plutot que la supprimer : supprimer `on:` laisserait un
        # bloc indentue sous une valeur scalaire, donc un YAML invalide — le cas
        # mesurerait la mauvaise chose.
        fichier = banc.suivre(ANDROID)
        fichier.muter(b"\non:\n", b"\nON_RENOMME_PAR_LE_BANC:\n")

    def jobs_absents() -> None:
        fichier = banc.suivre(ANDROID)
        fichier.muter(b"\njobs:\n", b"\nJOBS_RENOMMES_PAR_LE_BANC:\n")

    def etapes_absentes() -> None:
        fichier = banc.suivre(ANDROID)
        fichier.muter(b"    steps:\n", b"    STEPS_RENOMME_PAR_LE_BANC:\n")

    def yaml_invalide() -> None:
        fichier = banc.suivre(ANDROID)
        fichier.muter(b"\npermissions:\n", b'\npermissions: "ouverte\n')

    def flux_non_declare() -> None:
        banc.creer(
            FLUX_ESSAI,
            b"name: Banc\n"
            b"on: push\n"
            b"permissions:\n"
            b"  contents: read\n"
            b"jobs:\n"
            b"  essai:\n"
            b"    runs-on: ubuntu-latest\n"
            b"    steps:\n"
            b"      - run: echo ok\n",
        )

    def flux_absent() -> None:
        banc.supprimer(CI)

    banc.cas("script du depot inexistant", "[script-depot-absent]", script_du_depot_absent)
    banc.cas("script refuse par bash -n", "[script-invalide]", script_invalide)
    banc.cas("etape sans uses ni run", "[etape-vide]", etape_vide)
    banc.cas("action sans version epinglee", "[action-non-epinglee]", action_non_epinglee)
    banc.cas("permissions absentes", "[permissions-absentes]", permissions_absentes)
    banc.cas("job sans runs-on", "[runner-absent]", runner_absent)
    banc.cas("flux sans nom", "[nom-absent]", nom_absent)
    banc.cas("flux sans declencheur", "[declencheur-absent]", declencheur_absent)
    banc.cas("flux sans jobs", "[jobs-absents]", jobs_absents)
    banc.cas("job sans etapes", "[etapes-absentes]", etapes_absentes)
    banc.cas("YAML invalide", "[yaml-invalide]", yaml_invalide)
    banc.cas("flux present mais non declare", "[flux-non-declare]", flux_non_declare)
    banc.cas("flux attendu disparu", "[flux-absent]", flux_absent)

    code = banc.tableau()

    # --- la restauration doit etre exacte --------------------------------
    apres = empreinte_arbre(RACINE / ".github")
    identiques = avant == apres
    print(f"\nfichiers sous .github/           : {len(apres)}")
    print(f"restauration a l'octet           : {'conforme' if identiques else 'DIVERGENTE'}")

    if not identiques:
        differents = sorted(
            set(avant) ^ set(apres)
            | {c for c in set(avant) & set(apres) if avant[c] != apres[c]}
        )
        for chemin in differents:
            print(f"  - {chemin}", file=sys.stderr)
        return 1

    if code != 0:
        return code

    # --- etat final : le controle doit etre redevenu vert -----------------
    final = banc.executer()
    print(f"etat final : code {final.code}")
    if final.code != 0:
        print(final.texte, file=sys.stderr)
        return 1

    print("vert — le controle detecte, distingue, et sait refuser de conclure.")
    return 0


if __name__ == "__main__":
    sys.exit(principal())
