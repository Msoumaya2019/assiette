# Assiette

Estimer les **glucides** d'un repas à partir d'une photo, d'un code-barres ou d'une
recherche manuelle — puis suivre ses apports jour après jour.

Les glucides sont la mesure principale : ils occupent le haut de chaque écran, dans
une couleur qui leur est réservée. Calories, protéines, lipides, fibres et sucres
viennent en complément.

> **Toute valeur issue d'une photo est une estimation.** Les portions sont déduites
> visuellement, avec une marge d'erreur réelle. L'application n'est pas un dispositif
> médical et ne propose ni traitement ni dosage.

---

## Sommaire

- [Ce que fait l'application](#ce-que-fait-lapplication)
- [Comment les valeurs sont calculées](#comment-les-valeurs-sont-calculées)
- [Structure du dépôt](#structure-du-dépôt)
- [Prérequis](#prérequis)
- [Lancer le projet](#lancer-le-projet)
- [Configuration à la compilation](#configuration-à-la-compilation)
- [Backend (facultatif)](#backend-facultatif)
- [Construire une APK, un AAB ou un IPA](#construire-une-apk-un-aab-ou-un-ipa)
- [Intégration continue](#intégration-continue)
- [Sources de données et licences](#sources-de-données-et-licences)
- [Sécurité : où sont les secrets](#sécurité--où-sont-les-secrets)
- [Tests](#tests)
- [Notes d'environnement](#notes-denvironnement)

---

## Ce que fait l'application

| Écran | Rôle |
|---|---|
| **Accueil** | Glucides du jour, puis trois actions : analyser un repas, scanner un produit, rechercher un aliment |
| **Historique** | Tous les repas, groupés par jour, avec le total de glucides de chaque journée |
| **Statistiques** | Glucides des 7 derniers jours ou des 6 dernières semaines, objectifs, répartition |
| **Favoris** | Aliments et produits enregistrés, plus les repas types |
| **Réglages** | Mode d'analyse, objectifs, thème clair/sombre, rappels, effacement des données |

Parcours principal :

```
photo (1 ou 2 angles) → analyse → identification des aliments → estimation des poids
→ correspondance avec la base nutritionnelle → calcul des glucides → correction → enregistrement
```

Autres entrées : **code-barres** (produits industriels), **photo d'étiquette**
(valeurs lues puis vérifiables), **recherche manuelle**, **saisie à la main**.

Méthodes d'estimation de portion : photo rapide, second angle, poids connu saisi
directement, ou petite / moyenne / grande portion. Chaque modification de quantité
recalcule immédiatement l'ensemble des valeurs.

## Comment les valeurs sont calculées

Le point le plus important du projet :

1. Le modèle de vision **n'invente aucune valeur nutritionnelle**. Il renvoie
   uniquement des **noms d'aliments** et des **poids estimés**, avec un indice de
   confiance.
2. Chaque nom est rapproché de la base **Ciqual** (ANSES), embarquée dans
   l'application.
3. Les valeurs nutritionnelles viennent de cette base, jamais du modèle.
4. Un aliment non reconnu est conservé **avec des valeurs à zéro** et signalé à
   l'utilisateur — jamais complété par une valeur inventée.

Toutes les valeurs sont stockées **pour 100 g**, jamais en total. Modifier une
portion ne fait donc qu'un recalcul, sans dérive d'arrondi cumulée.

L'incertitude est propagée : chaque aliment porte un indice de confiance, et
l'application affiche une **fourchette** (`≈ 74 g — estimation 68–82 g`) dont la
largeur dépend de la confiance. En dessous de 0,65, le repas est marqué « à vérifier ».

## Structure du dépôt

```
app/                        Application Flutter (Android + iOS)
  lib/
    core/                   Configuration, thème, formatage, erreurs
    models/                 Valeurs nutritionnelles, aliments, repas, objectifs, réglages
    data/
      vision/               Fournisseurs d'analyse d'image + prompts
      local/                Base SQLite
      ciqual_repository.dart, openfoodfacts_repository.dart
    services/               Calcul nutritionnel, images, trousseau, notifications
    state/                  État applicatif (Riverpod)
    ui/                     Écrans, widgets, navigation
  assets/nutrition/         Base Ciqual générée (3 185 aliments)
  test/                     Tests unitaires
backend/supabase/           Fonctions serveur + schéma SQL (facultatif)
tools/                      Génération de la base Ciqual, contrôles de cohérence
.github/workflows/          Intégration continue, APK/AAB, iOS
```

## Prérequis

- **Flutter 3.47.4** (canal stable), Dart 3.13.3
- **JDK 17 ou 21** pour Android (le JBR fourni avec Android Studio convient)
- **Android SDK** : plateforme **android-36**, build-tools **36.0.0**
  *(`targetSdk` 36 est imposé par Google Play depuis le 31 août 2026)*
- **Xcode 16+** pour iOS, avec CocoaPods

## Lancer le projet

```bash
cd app
flutter pub get
flutter run
```

Premier lancement : un écran d'accueil présente le fonctionnement et la politique de
confidentialité, puis propose de saisir une clé d'analyse — ou de continuer en mode
démonstration, qui produit des données **fictives** et clairement étiquetées.

### Android

```bash
cd app
flutter build apk --release          # APK installable
flutter build appbundle --release    # AAB pour Google Play
```

Sans fichier `app/android/key.properties`, l'APK est signée avec la clé de débogage :
installable pour tester, **non publiable**. Voir `app/android/key.properties.example`.

### iOS

```bash
cd app
flutter build ios --release --no-codesign   # vérifie que ça compile
flutter build ipa --release                 # nécessite un certificat Apple
```

Le projet est compilable sans compte Apple. Produire un **IPA** exploitable demande
une signature ; l'intégration continue sait le faire sans certificat (voir plus bas).

## Configuration à la compilation

Tout passe par `--dart-define`. Aucune valeur sensible n'est écrite dans le dépôt.

| Variable | Effet |
|---|---|
| `APP_ENV` | Étiquette d'environnement (`dev`, `production`). Le mode démonstration est refusé en production. |
| `ANALYSIS_ENDPOINT` | URL de la fonction d'analyse côté serveur. **Sa présence bascule l'application en mode proxy.** |
| `SUPABASE_URL` | Projet Supabase (synchronisation, compte). Facultatif. |
| `SUPABASE_ANON_KEY` | Clé publique Supabase. Publique par conception : la protection repose sur les politiques RLS. |

Exemple :

```bash
flutter build apk --release \
  --dart-define=APP_ENV=production \
  --dart-define=ANALYSIS_ENDPOINT=https://<projet>.supabase.co/functions/v1
```

## Backend (facultatif)

Deux façons d'accéder au modèle de vision :

- **Mode personnel** — l'utilisateur saisit sa propre clé. Elle est rangée dans le
  trousseau du système (Keychain sur iOS, Keystore sur Android). Aucun backend.
  C'est le mode par défaut, utilisable immédiatement.
- **Mode proxy** — l'application appelle une fonction serveur qui détient la clé.
  C'est le mode prévu pour une publication publique : **aucune clé dans le binaire**.

Le backend se déploie sur Supabase :

```bash
supabase functions deploy analyze-meal
supabase functions deploy analyze-label
supabase secrets set DEEPSEEK_API_KEY=...   # jamais dans le dépôt
supabase db push                            # applique migrations/0001_init.sql
```

Voir `backend/README.md`.

## Construire une APK, un AAB ou un IPA

### Localement

```bash
cd app
flutter build apk --release
flutter build appbundle --release
```

### Via GitHub Actions (recommandé)

Trois flux, déclenchables manuellement depuis l'onglet *Actions* :

| Flux | Produit | Exécuteur |
|---|---|---|
| `ci.yml` | Analyse, tests, contrôle des secrets | ubuntu |
| `android.yml` | `app-release.apk`, `app-release.aab` | ubuntu |
| `ios.yml` | IPA non signé (installable via eSign / Sideloadly) ou IPA signé | macOS |

Les fichiers produits sont téléchargeables dans la section **Artifacts** de
l'exécution. Un tag `v*` déclenche Android automatiquement.

Signature Android en CI — secrets à définir dans *Settings → Secrets and variables →
Actions* :

| Secret | Contenu |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Keystore encodé en base64 |
| `ANDROID_KEYSTORE_PASSWORD` | Mot de passe du keystore |
| `ANDROID_KEY_ALIAS` | Alias de la clé |
| `ANDROID_KEY_PASSWORD` | Mot de passe de la clé |

Sans ces secrets, la CI produit une APK signée avec la clé de débogage et l'indique
explicitement dans le journal.

Signature iOS — secrets supplémentaires, à ajouter seulement le jour où un compte
Apple Developer existe : `IOS_CERTIFICATE_BASE64`, `IOS_CERTIFICATE_PASSWORD`,
`IOS_PROVISIONING_PROFILE_BASE64`, `KEYCHAIN_PASSWORD`.

## Intégration continue

Avant chaque compilation, la CI exécute six contrôles :

- `tools/check_no_secrets.py` — refuse tout fichier ou motif ressemblant à un secret
  (clés d'API, keystores, `.env`, certificats, jetons).
- `tools/check_prompt_sync.py` — vérifie que les prompts d'analyse, présents en deux
  copies (Dart pour le mode personnel, TypeScript pour le mode proxy), portent le
  même numéro de version.
- `tools/check_fins_de_ligne.py` — vérifie que les fins de ligne réelles
  correspondent à l'attribut `eol` déclaré dans `.gitattributes`.
- `tools/check_ios.py` — vérifie la cohérence du projet iOS (identifiant, cible
  minimale, permissions, icônes), que Windows ne peut pas compiler.
- `tools/check_adresses_du_depot.py` — vérifie que les adresses sortant dans le
  binaire désignent bien ce dépôt.
- `tools/verifier_version_build.py` — éprouve la logique qui décide de la version
  publiée, laquelle ne tourne sinon que sur un tag.

Puis `dart format --set-exit-if-changed`, `flutter analyze` et `flutter test`, et,
dans un travail séparé, `tools/check_workflows.py` — qui valide la structure des
flux de travail, la présence des scripts qu'ils appellent, et le fait que
`android.yml` et `ios.yml` tirent la version du même endroit.

### La version publiée vient du tag, et d'un seul endroit

Le nom d'un artefact venait du tag Git, la version inscrite dans le binaire venait
de `app/pubspec.yaml`. Le tag `v0.1.1` a donc produit une IPA nommée `v0.1.1` dont
l'`Info.plist` déclarait `0.1.0` : deux sources de vérité, et rien pour dire
laquelle croyait la personne qui installe le fichier.

`tools/version_build.sh` est désormais le point unique qui décide, pour les deux
plateformes. Sur un tag, la version est celle du tag ; sur une branche, celle du
pubspec ; `workflow_dispatch` accepte une version saisie à la main. Le nom du
fichier porte exactement ce que le binaire déclare.

Une valeur qui ne serait pas des chiffres séparés par des points est refusée. Ce
n'est pas une coquetterie : pour iOS, Flutter retire **en silence** tout caractère
hors `[0-9.]` avant d'écrire `CFBundleShortVersionString`, si bien qu'un tag
`release-2.0` donnerait `2.0.0` sur iOS et `release-2.0` sur Android. Un refus
nommé vaut mieux qu'une divergence muette.

```bash
python tools/verifier_version_build.py    # 11 cas, hors GitHub Actions
```

## Sources de données et licences

| Source | Usage | Licence |
|---|---|---|
| **Ciqual 2020** (ANSES) | Aliments génériques, embarqués dans l'application | Licence Ouverte 2.0 (Etalab) |
| **Open Food Facts** | Produits industriels, interrogés à la demande | ODbL (base), DbCL (contenus), CC BY-SA (images) |
| **DeepSeek** (`deepseek-flash`) | Identification des aliments sur photo | Conditions du fournisseur |

La base Ciqual est **embarquée** : recherche instantanée, hors ligne, sans limite de
débit. Open Food Facts est **interrogé à la demande** et n'est pas redistribué, ce qui
respecte sa licence et ses limites d'usage. Les attributions complètes figurent dans
`app/assets/legal/ATTRIBUTION.md` et dans l'application.

Régénérer la base Ciqual :

```bash
python tools/build_ciqual.py
```

## Sécurité : où sont les secrets

- **Aucune clé d'API dans l'APK ou l'IPA.** Une application mobile est inspectable :
  toute clé embarquée est une clé publique.
- Mode personnel : la clé de l'utilisateur va dans le trousseau du système, pas dans
  le binaire.
- Mode proxy : la clé vit dans les variables d'environnement de la fonction serveur.
- `.gitignore` exclut `.env`, `key.properties`, keystores, certificats, profils de
  provisionnement et `local.properties`. Un contrôle automatique le vérifie en CI.
- Les fichiers de signature utilisés en CI sont écrits dans un dossier temporaire et
  **supprimés en fin de build**, y compris en cas d'échec.

## Tests

```bash
python tools/lancer_tests_flutter.py    # toute la suite
```

Sous Windows, ce lanceur pose les deux réglages que Flutter réclame et écarte la
boucle locale du mandataire ; le pourquoi est documenté dans
`docs/publication.md` §7.4. La CI, elle, exécute `flutter test` directement sur
`ubuntu-latest`.

Les contrôles et les scripts qui décident de la version publiée sont éprouvés hors
CI, sur cette machine :

```bash
python tools/verifier_version_build.py    # 11 cas sur tools/version_build.sh
python tools/lancer_bancs.py              # les sept bancs de falsification
```

Un banc de falsification retire un garde-fou à la fois et vérifie que le contrôle
tombe. Un contrôle qui n'a jamais échoué ne prouve rien : il peut regarder au
mauvais endroit et compter zéro défaut tout aussi tranquillement qu'un contrôle
juste. `docs/publication.md` §8 liste les bancs.

`lancer_bancs.py` lit chaque code de sortie **directement**, sans tube : lire
`$?` après un `| tail` rend le code du tube, pas celui de la commande, ce qui a
déjà fait annoncer trois bancs verts alors que l'un d'eux avait planté.

Après avoir téléchargé un APK ou un IPA, son nom et son contenu se vérifient :

```bash
python tools/verifier_version_binaire.py app-release-0.1.0+1-debug-key.apk
python tools/verifier_version_binaire.py Assiette-0.1.0+1-non-signee.ipa
```

Ce contrôle lit la version inscrite dans le binaire — `versionName`/`versionCode`
pour Android, `CFBundleShortVersionString`/`CFBundleVersion` pour iOS — et refuse
un fichier dont le nom annonce autre chose. C'est le seul contrôle qui voie la
valeur **inscrite** : tous les autres vérifient la valeur **passée** à la
compilation.

Couverture actuelle :

- calculs nutritionnels, changement de portion, absence de dérive d'arrondi,
  totaux de glucides, fourchette d'incertitude, objectifs ;
- analyse syntaxique des réponses du modèle (JSON encadré, valeurs aberrantes,
  nombres en texte, virgule décimale, listes tronquées) ;
- **requête réellement transmise au fournisseur** : champ `thinking`, température,
  modèle, format JSON, image en data URL, en-tête d'autorisation, et absence de la
  clé dans le corps ;
- **mode proxy** : adresse visée, image transmise en base64 avec son type, seconde
  image, indices facultatifs envoyés seulement s'ils existent, jeton de session, et
  l'absence de toute clé dans le corps ; traduction des refus du serveur (401, 413,
  415, 429 avec délai, 500) ;
- lecture des réponses Open Food Facts (deux formats de schéma, cache, erreurs 404 /
  429 / 503) ;
- recherche Ciqual (accents, ligatures, classement, appariement approximatif).

## Notes d'environnement

**Windows / Git Bash.** Des variables que Git Bash n'expose pas font échouer
Flutter, chacune avec un message qui ne dit pas sa cause :

1. `PATHEXT` — le paquet Dart `process` le lit sans garde : `Null check operator
   used on a null value`. Exporter `PATHEXT=".COM;.EXE;.BAT;.CMD"`.
2. `PROGRAMFILES(X86)` — `flutter test` s'arrête dessus, et le message **accuse
   Visual Studio**. Fournir la variable suffit : Visual Studio n'est pas
   nécessaire, le SDK ignorant explicitement un `vswhere.exe` introuvable.
3. `HTTP_PROXY` sans `NO_PROXY` — le processus de test ne peut plus rejoindre son
   propre port d'écoute, et **tous** les fichiers échouent d'un coup, avec un
   message qui désigne le WebSocket.

`tools/lancer_tests_flutter.py` et `tools/environnement_flutter.py` posent les
deux derniers réglages ; `docs/publication.md` §7.4 détaille le diagnostic. Sur
macOS et Linux, `flutter` fonctionne normalement.

---

## État du projet

| Partie | État |
|---|---|
| Modèles, calculs nutritionnels, stockage local | Écrit, testé |
| Analyse photo (mode personnel et proxy) | Écrit, testé sur les réponses simulées |
| Base Ciqual embarquée | Générée, 3 185 aliments |
| Recherche, code-barres, étiquettes | Écrit |
| Historique, favoris, repas types, statistiques, objectifs | Écrit |
| Réglages, thème clair/sombre, confidentialité | Écrit |
| Notifications (rappels de repas, résumé du soir) | Écrit, testé |
| Compte et synchronisation | Schéma serveur prêt, interface à brancher |
| Publication App Store / Play Store | Non entamée — volontairement |
