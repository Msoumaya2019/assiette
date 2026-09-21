#!/usr/bin/env python3
"""Harnais de falsification des controles de `tools/`.

Pourquoi ce harnais existe
--------------------------

Un controle qui n'a jamais echoue ne prouve rien : il peut regarder au mauvais
endroit et compter zero defaut tout aussi tranquillement qu'un controle juste.
La seule facon de savoir s'il detecte ce qu'il pretend couvrir est de fabriquer
le defaut et de verifier qu'il tombe.

Le piege que ce harnais ferme
-----------------------------

Un banc precedent mutait un storyboard en cherchant un bloc termine par `\\n`.
Le fichier etait en CRLF : le motif ne correspondait **zero fois**, `replace()`
n'a rien fait, le controle n'a rien vu, et le banc a conclu « non detecte ».
La mutation n'avait jamais eu lieu.

C'est pourquoi `Fichier.muter()` **leve une exception** quand son ancre ne
correspond pas, ou quand la substitution ne change rien. Une mutation qui ne
mute pas est une erreur du banc, pas un resultat.

Le harnais travaille **au niveau octet**, avec des ancres ASCII, et prouve la
restauration par empreinte SHA-256 — jamais par `git diff`, qui normalise les
fins de ligne et masquerait justement la difference.

Le troisieme piege : etre interrompu
------------------------------------

Un banc tue par un signal en pleine mutation laissait le fichier mute. Mesure :
`tools/version_build.sh` s'est retrouve **ampute de son garde-fou**, et comme il
n'etait pas encore suivi par git, aucun `git checkout` ne pouvait le rendre.

`SIGTERM` ne leve aucune exception par defaut, et `KeyboardInterrupt` herite de
`BaseException`, pas d'`Exception` : un `except Exception` laisse donc passer les
deux. Le harnais arme desormais une restauration d'urgence — gestionnaire de
signal, `atexit`, et capture de `BaseException` autour des deux phases a risque.

Le quatrieme piege : une suppression qui reussit sans supprimer
--------------------------------------------------------------

Sur cette machine, les suppressions sont **bloquees au-dela d'un seuil par
tour**, et le blocage est **silencieux** : `Path.unlink()` rend la main sans
lever, alors que le fichier est toujours la. Le refus n'existe que sur la sortie
d'erreur du processus.

Mesure : une campagne de seize bancs a laisse **quatre** temoins dans l'arbre —
`tools/__banc_essai.txt`, `.github/workflows/__banc_essai.yml`,
`backend/supabase/migrations/0004_oubliee.sql` et une icone iOS — et les bancs
concernes se sont declares **en echec en accusant le depot**, chacun sur un
fichier qu'il avait lui-meme fabrique :

  - « le controle echoue deja avant toute mutation », pour les fins de ligne ;
  - « Icon-App-72x72@1x.png present mais non declare dans Contents.json » ;
  - « La migration 0004_oubliee.sql existe mais n'est pas dans
    MIGRATIONS_ATTENDUES » ;
  - un flux non declare, pour le controle des flux de travail.

Chacun avait pourtant appele `restaurer()`. Le harnais croyait avoir nettoye.

Deux remedes, et il faut les deux :

  - `Banc.retirer` **deplace** au lieu de supprimer — un deplacement n'est pas
    une suppression — et **verifie** que le chemin est libre. `replace`, et non
    `rename`, qui echoue si la cible existe (`FileExistsError`, WinError 183) :
    un premier reste dans `%TEMP%` suffisait a faire lever tous les replis
    suivants ;
  - chaque banc qui verifie l'**absence** d'un artefact retire le sien au
    demarrage, et le dit. C'est le seul remede qui tienne : le nettoyage de fin
    ne peut pas etre garanti ici, donc la campagne doit pouvoir repartir d'un
    arbre ou le passage precedent a laisse quelque chose.

Apres les deux, la campagne rend **16 bancs, tous verts**, et les quatre
nettoyages de demarrage annoncent chacun leur temoin.

Usage : voir `tools/bancs/falsifier_fins_de_ligne.py`.
"""

from __future__ import annotations

import atexit
import hashlib
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent.parent


class AncreIntrouvable(Exception):
    """La mutation n'a pas pu etre appliquee : le banc serait muet, donc faux."""


class MesureImpossible(Exception):
    """Le controle n'a pas pu tourner : le resultat ne prouverait rien.

    A ne pas confondre avec un defaut non detecte. Une mutation qui casse la
    compilation rend, elle aussi, un code de sortie non nul — et un banc qui ne
    distingue pas les deux conclut « non detecte » sur une mutation qui n'a
    jamais ete mesuree.
    """


class Fichier:
    """Un fichier suivi par le banc : son contenu d'origine et son empreinte."""

    def __init__(self, chemin: Path) -> None:
        self.chemin = chemin
        self.origine = chemin.read_bytes()
        self.sha = hashlib.sha256(self.origine).hexdigest()
        # Renseigne par `Banc.supprimer` : l'endroit ou le fichier a ete deplace.
        self.deplace: Path | None = None

    def muter(self, ancien: bytes, nouveau: bytes, occurrences: int | None = None) -> None:
        """Remplace `ancien` par `nouveau`. Leve si l'ancre ne correspond pas."""
        courant = self.chemin.read_bytes()
        trouvees = courant.count(ancien)

        if trouvees == 0:
            raise AncreIntrouvable(
                f"{self.chemin} : l'ancre {ancien[:60]!r} ne correspond a rien "
                f"({trouvees} occurrence). La mutation n'aurait pas eu lieu."
            )

        if occurrences is None:
            resultat = courant.replace(ancien, nouveau)
        else:
            if occurrences > trouvees:
                raise AncreIntrouvable(
                    f"{self.chemin} : {occurrences} remplacements demandes, "
                    f"{trouvees} occurrence(s) trouvee(s)."
                )
            resultat = courant.replace(ancien, nouveau, occurrences)

        if resultat == courant:
            raise AncreIntrouvable(
                f"{self.chemin} : la substitution a laisse le fichier identique."
            )

        self.chemin.write_bytes(resultat)

    def ecrire(self, contenu: bytes) -> None:
        self.chemin.write_bytes(contenu)

    def restaurer(self) -> bool:
        """Remet le contenu d'origine et verifie l'empreinte."""
        self.chemin.write_bytes(self.origine)
        return hashlib.sha256(self.chemin.read_bytes()).hexdigest() == self.sha


def empreinte_arbre(dossier: Path) -> dict[str, str]:
    """Empreinte SHA-256 de chaque fichier d'un dossier, hors `.git`."""
    empreintes: dict[str, str] = {}
    for chemin in sorted(dossier.rglob("*")):
        if not chemin.is_file():
            continue
        if ".git" in chemin.parts:
            continue
        empreintes[chemin.relative_to(dossier).as_posix()] = hashlib.sha256(
            chemin.read_bytes()
        ).hexdigest()
    return empreintes


class Resultat:
    def __init__(self, code: int, sortie: str, erreur: str) -> None:
        self.code = code
        self.sortie = sortie
        self.erreur = erreur

    @property
    def texte(self) -> str:
        return f"{self.sortie}\n{self.erreur}"


class Banc:
    """Falsifie un controle : mute, execute, restaure, et rend compte."""

    def __init__(
        self,
        script: Path,
        arguments: tuple[str, ...] = (),
        interpreteur: list[str] | None = None,
        environnement: dict[str, str] | None = None,
    ) -> None:
        self.script = script
        self.arguments = arguments
        # Certains controles ne sont pas des scripts Python : `falsifier_epreuve_migrations.py`
        # eprouve un `.mjs`, qui a besoin de Node. L'interpreteur est donc un
        # parametre, et non `sys.executable` en dur.
        self.interpreteur = interpreteur if interpreteur is not None else [sys.executable]
        # `None` laisse `subprocess` heriter de l'environnement courant, ce qui
        # est le comportement des bancs qui n'ont rien de particulier a poser.
        self.environnement = environnement
        self.fichiers: dict[Path, Fichier] = {}
        self.crees: list[Path] = []
        self.supprimes: list[Fichier] = []
        self.lignes: list[tuple[str, str, str, bool]] = []
        # Certains cas ecrivent dans l'index (un blob force, par exemple). Quand
        # ce drapeau est arme, `restaurer()` reconstruit l'index depuis HEAD —
        # sans jamais toucher la copie de travail, qu'un `reset` mixte laisse
        # intacte.
        self.index_a_reinitialiser = False
        self._armer_restauration_d_urgence()

    # --- restauration d'urgence ------------------------------------------

    def _armer_restauration_d_urgence(self) -> None:
        """Restaure meme si le processus est interrompu.

        Mesure, et non precaution theorique : un banc tue par un signal en
        pleine mutation a laisse `tools/version_build.sh` **ampute de son
        garde-fou**, sans restauration. Le fichier n'etait pas encore suivi par
        git, donc aucun `git checkout` ne pouvait le rendre : il a fallu le
        reecrire a la main, en se fiant au souvenir de ce qu'il contenait.

        Les deux voies d'interruption ne sont pas les memes :

          - `SIGTERM` ne leve rien du tout par defaut : le processus meurt, et
            aucun `except` ne s'execute. Il faut un gestionnaire de signal.
          - `SIGINT` (Ctrl+C) leve `KeyboardInterrupt`, qui herite de
            `BaseException` et non d'`Exception` : un `except Exception` le
            laisse donc passer. `cas()` attrape desormais `BaseException`.

        `atexit` couvre le troisieme cas : une sortie normale non prevue.
        """
        atexit.register(self.restaurer_en_silence)

        for numero in (signal.SIGTERM, signal.SIGINT):
            try:
                signal.signal(numero, self._sur_signal(numero))
            except (ValueError, OSError):
                # Hors du fil principal, ou signal non installable sur la
                # plateforme. `atexit` reste en place.
                continue

    def _sur_signal(self, numero: int):
        """Fabrique le gestionnaire : restaure, puis rend la main au systeme."""

        def gestionnaire(_signature, _cadre) -> None:
            print(
                f"\ninterruption ({signal.Signals(numero).name}) — restauration du depot",
                file=sys.stderr,
            )
            self.restaurer_en_silence()
            # 128 + numero : la convention des shells pour « tue par un signal ».
            sys.exit(128 + numero)

        return gestionnaire

    def restaurer_en_silence(self) -> None:
        """Restaure sans jamais lever : utilisable depuis un signal ou `atexit`.

        `restaurer()` peut lever pour signaler un echec de restauration. Depuis
        un gestionnaire de signal, lever remplacerait l'interruption par une
        autre panne et masquerait la cause. On rapporte, et on continue.
        """
        try:
            self.restaurer()
        except BaseException as erreur:  # noqa: BLE001
            print(f"restauration incomplete : {erreur}", file=sys.stderr)

    # --- preparation -----------------------------------------------------

    def suivre(self, chemin_relatif: str) -> Fichier:
        chemin = RACINE / chemin_relatif
        if chemin not in self.fichiers:
            self.fichiers[chemin] = Fichier(chemin)
        return self.fichiers[chemin]

    def creer(self, chemin_relatif: str, contenu: bytes) -> Path:
        chemin = RACINE / chemin_relatif
        chemin.parent.mkdir(parents=True, exist_ok=True)
        chemin.write_bytes(contenu)
        self.crees.append(chemin)
        return chemin

    def supprimer(self, chemin_relatif: str) -> None:
        """Rend un fichier absent, en le **renommant**.

        Renommer plutot que supprimer : la suppression passe par le mecanisme de
        corbeille du systeme, qui peut echouer. Un echec en pleine mutation
        laisse alors le fichier ni supprime ni restaure, et **le depot reste
        mutile** — c'est arrive sur une icone iOS. Un renommage est atomique, ne
        depend d'aucun service, et se defait a l'identique.
        """
        chemin = RACINE / chemin_relatif
        fichier = Fichier(chemin)
        fichier.deplace = chemin.with_name(chemin.name + ".banc-deplace")
        chemin.rename(fichier.deplace)
        self.supprimes.append(fichier)

    # --- execution -------------------------------------------------------

    def executer(self) -> Resultat:
        resultat = subprocess.run(
            [*self.interpreteur, str(self.script), *self.arguments],
            cwd=RACINE,
            capture_output=True,
            text=True,
            env=self.environnement,
            check=False,
        )
        return Resultat(resultat.returncode, resultat.stdout, resultat.stderr)

    def etat_initial(self) -> Resultat:
        return self.executer()

    # --- cas de test -----------------------------------------------------

    def cas(self, libelle: str, marqueur: str, appliquer, attendu: bool = True) -> None:
        """Applique une mutation, execute le controle, restaure, enregistre.

        `attendu=True`  : le marqueur doit apparaitre (le defaut est detecte).
        `attendu=False` : le marqueur doit rester absent (temoin negatif) — sans
        quoi rien ne prouve que le controle distingue, plutot qu'il ne compte.
        """
        try:
            appliquer()
        except AncreIntrouvable as erreur:
            self._invalide(
                libelle,
                erreur,
                "La mutation n'a pas eu lieu : le banc ne prouverait rien. "
                "Corriger l'ancre, pas le controle.",
            )
            raise SystemExit(2)
        except Exception as erreur:  # noqa: BLE001
            # Toute autre panne pendant la mutation doit restaurer. Sans cela le
            # banc laisse le depot mutile, et la panne se lit plus tard, ailleurs
            # — c'est arrive sur une icone iOS laissee supprimee.
            self._invalide(
                libelle,
                erreur,
                "La mutation a echoue en cours de route : le banc ne prouverait "
                "rien. Le depot a ete restaure.",
            )
            raise SystemExit(2)
        except BaseException as erreur:  # noqa: BLE001
            # `KeyboardInterrupt` et `SystemExit` heritent de `BaseException`,
            # pas d'`Exception` : un Ctrl+C en pleine mutation traversait donc
            # les deux `except` ci-dessus sans restaurer. Le gestionnaire de
            # signal couvre le cas, mais autant remettre le depot en etat ici
            # aussi, pendant que le contexte est encore lisible.
            self.restaurer_en_silence()
            raise

        try:
            resultat = self.executer()
        except MesureImpossible as erreur:
            self._invalide(
                libelle,
                erreur,
                "La mesure n'a pas pu tourner : le banc ne prouverait rien. "
                "Corriger la mutation, pas le controle.",
            )
            raise SystemExit(2)
        except BaseException:
            # Le fichier est encore mute a cet instant : on le rend avant de
            # laisser filer l'interruption, quelle qu'elle soit.
            self.restaurer_en_silence()
            raise

        present = marqueur in resultat.texte
        self.restaurer()

        reussi = present == attendu
        if attendu:
            verdict = "detecte" if present else "NON DETECTE"
        else:
            verdict = "non signale" if not present else "SIGNALE A TORT"

        self.lignes.append((libelle, marqueur, verdict, reussi))

    def _invalide(self, libelle: str, erreur: BaseException, conseil: str) -> None:
        """Signale un banc qui ne prouve rien, et remet le depot en etat."""
        print(f"\nBANC INVALIDE — cas « {libelle} »", file=sys.stderr)
        print(f"  {type(erreur).__name__} : {erreur}", file=sys.stderr)
        print(f"  {conseil}", file=sys.stderr)
        self.restaurer()

    def retirer(self, chemin: Path) -> None:
        """Retire un fichier fabrique par le banc, et **verifie** qu'il est parti.

        Pourquoi `unlink()` ne suffit pas
        ---------------------------------
        Sur cette machine, les suppressions sont **bloquees au-dela d'un seuil
        par tour**, et le blocage est **silencieux** : `Path.unlink()` rend la
        main sans lever, alors que le fichier est toujours la. Mesure : quatre
        bancs d'une meme campagne ont laisse leurs temoins dans l'arbre —
        `tools/__banc_essai.txt`, `.github/workflows/__banc_essai.yml`,
        `backend/supabase/migrations/0004_oubliee.sql` et une icone iOS — et les
        quatre se sont declares en echec en accusant un depot casse. Le harnais
        croyait avoir nettoye.

        Le remede est donc double : **deplacer** plutot que supprimer — un
        deplacement n'est pas une suppression, donc le garde-fou ne le bloque
        pas —, et **verifier** ensuite que le chemin est bien libre. Un nettoyage
        non verifie est precisement ce qui a echoue ici.

        `replace`, et non `rename` : `os.rename` echoue si la cible existe
        (`FileExistsError`, WinError 183), et un premier reste dans `%TEMP%`
        suffisait alors a faire lever tous les replis suivants. Mesure directe :
        sur la meme cible deja presente, `rename` leve `WinError 183` quand
        `replace` aboutit.
        """
        try:
            chemin.unlink()
        except OSError:
            # La suppression passe par le mecanisme de corbeille du systeme, qui
            # peut refuser (mesure : `SHFileOperationW: 0x2`).
            pass

        if not chemin.exists():
            return

        chemin.replace(Path(tempfile.gettempdir()) / f"banc-{chemin.name}")
        if chemin.exists():
            raise SystemExit(f"retrait impossible : {chemin}")

    def restaurer(self) -> None:
        for fichier in self.fichiers.values():
            if not fichier.restaurer():
                raise SystemExit(f"restauration impossible : {fichier.chemin}")
        for fichier in self.supprimes:
            if fichier.deplace is not None and fichier.deplace.exists():
                fichier.deplace.rename(fichier.chemin)
            if hashlib.sha256(fichier.chemin.read_bytes()).hexdigest() != fichier.sha:
                raise SystemExit(f"restauration impossible : {fichier.chemin}")
        self.supprimes.clear()
        for chemin in self.crees:
            if chemin.exists():
                self.retirer(chemin)
        self.crees.clear()

        if self.index_a_reinitialiser:
            resultat = subprocess.run(
                ["git", "reset", "-q"], cwd=RACINE, capture_output=True, check=False
            )
            if resultat.returncode != 0:
                raise SystemExit(
                    "reinitialisation de l'index impossible : "
                    f"{resultat.stderr.decode(errors='replace').strip()}"
                )

    # --- compte rendu ----------------------------------------------------

    def tableau(self) -> int:
        largeur = max((len(libelle) for libelle, _, _, _ in self.lignes), default=10)
        print(f"\n{'mutation'.ljust(largeur)}  {'attendu'.ljust(26)}  resultat")
        print("-" * (largeur + 44))
        for libelle, marqueur, verdict, _ in self.lignes:
            print(f"{libelle.ljust(largeur)}  {marqueur.ljust(26)}  {verdict}")

        rates = [libelle for libelle, _, _, reussi in self.lignes if not reussi]
        print()
        if rates:
            print(f"{len(rates)} cas en echec :", file=sys.stderr)
            for libelle in rates:
                print(f"  - {libelle}", file=sys.stderr)
            return 1

        print(f"{len(self.lignes)} cas, tous conformes.")
        return 0
