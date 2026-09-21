# Publication — Assiette

Ce document décrit ce qui est déjà en place, ce qui reste à faire, et à quelles
conditions actuelles publier. Les exigences des magasins changent souvent :
elles ont été vérifiées le 18 septembre 2026, aux sources citées.

---

## 1. Ce qui est déjà prêt

| Élément | État |
| --- | --- |
| Code source complet, analysé sans avertissement | prêt |
| 273 tests de l'application, tous verts | prêt |
| 18 tests du serveur, tous verts | prêt |
| Dépôt public | https://github.com/Msoumaya2019/assiette |
| Flux `ci.yml` — analyse, 273 tests, 7 contrôles | **vert** |
| Flux Android — APK et AAB | **vert**, artefacts signés et vérifiés |
| Flux iOS — IPA non signée | **vert**, artefact vérifié |
| Déclenchement par étiquette `v*` | **vert** (`v0.1.0`, `v0.1.1`, `v0.1.2`, `v0.1.3`) |
| Dernière version publiée | **`v0.1.3`** — APK signé, AAB signé, IPA (portions nommées, suivi du poids) |
| Icônes et écran de démarrage (Android et iOS) | prêt |
| Politique de confidentialité | `docs/confidentialite.md` |
| Attributions Ciqual et Open Food Facts | `app/assets/legal/ATTRIBUTION.md` |
| Clés d'API absentes du binaire (appel via serveur) | prêt |
| Signature release Android (clé d'envoi) | **faite** — clé créée, 4 secrets déposés, sauvegarde à faire |
| Compte Google Play, compte Apple Developer | **à créer** |
| Projet Supabase (mode serveur) | **à créer** |
| Clé du fournisseur d'analyse (DeepSeek) | **fournie**, à placer |

### Artefacts vérifiés

Produits par `Android — APK et AAB` et `iOS — build et IPA`, puis **ouverts et
contrôlés**, pas seulement lus dans le journal du flux :

| Version | Artefact | Vérification |
| --- | --- | --- |
| `v0.1.3` | `app-release-0.1.3+7-signe.apk` | déclare `0.1.3` / `7`, 84 381 057 octets, signé avec la clé de release |
| `v0.1.3` | `app-release-0.1.3+7-signe.aab` | 72 260 004 octets, version non lisible dans un AAB — non vérifiée, et le script l'écrit |
| `v0.1.3` | `Assiette-0.1.3+6-non-signee.ipa` | déclare `0.1.3` / `6`, 17 059 881 octets |
| `v0.1.2` | `app-release-0.1.2+6-signe.apk` | déclare `0.1.2` / `6`, signé avec la clé de release (`CN=Assiette`, empreinte `22518e30…`) |
| `v0.1.2` | `app-release-0.1.2+6-signe.aab` | 549 entrées, signé (`META-INF/ASSIETTE.RSA`) |
| `v0.1.2` | `Assiette-0.1.2+5-non-signee.ipa` | déclare `0.1.2` / `5`, `MinimumOSVersion` 15.5 |
| `v0.1.1` | `app-release-…-debug-key.apk` | 82 227 529 octets, 531 entrées, 18 bibliothèques natives, signé de la clé de débogage |
| `v0.1.1` | `Assiette-v0.1.1-non-signee.ipa` | 133 entrées, `io.github.axox934.assiette` — **se déclarait `0.1.0`** |

La ligne `v0.1.1` de l'IPA est le défaut qui a motivé tout le travail de version :
le fichier était en ligne, téléchargeable, et faux sur lui-même.

Depuis `v0.1.2`, les artefacts Android sont signés avec la vraie clé : ils sont
publiables sur le Play Store. Les précédents portaient `debug-key`.

Le contenu de l'IPA confirme la cible iOS : `MinimumOSVersion` vaut **15.5**, et
l'identifiant `io.github.axox934.assiette` est identique côté Android et côté iOS.
Les deux textes de justification d'accès (appareil photo, photothèque) sont présents.

**Ce que l'ouverture de l'IPA a appris, et qui a été corrigé depuis.** Le fichier
s'appelait `Assiette-v0.1.1-non-signee.ipa` et son `Info.plist` déclarait
`CFBundleShortVersionString` = `0.1.0`, `CFBundleVersion` = `1`. Le nom venait du
tag Git, la version venait de `app/pubspec.yaml` (`0.1.0+1`). Rien ne permettait
donc de savoir ce qui avait été installé.

Les artefacts de `v0.1.1` restent en ligne tels quels — on ne réécrit pas une
publication, et une version publiée doit rester celle que des gens ont pu
télécharger. Les suivants déclarent la version de leur tag, et leur nom porte la
même valeur. Voir §8 pour le mécanisme, et §9 pour la publication.

---

## 2. Actions qui ne peuvent être faites que par toi

Ces étapes engagent une identité ou une carte bancaire : elles ne peuvent pas
être automatisées.

### 2.1 Autoriser l'outil en ligne de commande GitHub — **fait**

L'autorisation a été donnée le 18 septembre 2026, sur le compte
`Msoumaya2019`. Le dépôt public a été créé :

**https://github.com/Msoumaya2019/assiette**

Note pour la suite : dans un terminal Git Bash, `gh` ne trouve pas son dossier
de configuration si `APPDATA` n'est pas défini — `gh auth status` répond alors
« not logged into any GitHub hosts » alors que l'autorisation est bien
enregistrée. Il faut l'exporter avant tout appel :

```bash
export APPDATA="C:\\Users\\mchik\\AppData\\Roaming"
```

La portée `workflow` est présente sur le jeton, sans quoi GitHub refuse de
recevoir les fichiers de `.github/workflows/`.

### 2.2 Placer la clé du service d'analyse — **clé créée, destination à choisir**

La clé DeepSeek existe. Elle n'a **jamais** sa place dans l'application, dans le
dépôt, ni dans la conversation. Deux destinations possibles, selon l'usage.

**Mode personnel — utilisable tout de suite, sans backend.** L'application
demande la clé dans ses réglages et la conserve dans le trousseau du système
(Keychain sur iOS, Keystore sur Android). Aucun serveur, aucun coût
d'hébergement. C'est le mode par défaut tant que `ANALYSIS_ENDPOINT` n'est pas
compilé. Convient pour un usage personnel.

**Mode serveur — nécessaire pour publier.** La clé est détenue par une fonction
serveur, et l'application ne la connaît pas. C'est le mode prévu pour une
application distribuée, puisque l'utilisateur n'a alors aucune clé à saisir. Il
demande un projet Supabase, qui n'existe pas encore.

Nom exact attendu par le serveur, lu dans `backend/supabase/functions/` :

| Variable | Rôle |
| --- | --- |
| `DEEPSEEK_API_KEY` | la clé, lue par `analyze-meal` et `analyze-label` |
| `ALLOWED_ORIGIN` | origine autorisée pour le CORS. **Sans elle, le CORS reste fermé** — c'est volontaire : la fonction est facturée et sans authentification |

### 2.3 Créer le compte Google Play

**ACTION REQUISE DE TA PART**

Pourquoi : publier sur le Play Store exige un compte développeur nominatif,
avec vérification d'identité et frais d'inscription.

Étape 1 : va sur `play.google.com/console`, crée un compte développeur
(non professionnel si tu publies à titre personnel), et renseigne ton identité.

### 2.4 Créer le compte Apple Developer

**ACTION REQUISE DE TA PART**

Pourquoi : installer l'application sur un iPhone, et à plus forte raison
publier sur l'App Store, exige une signature Apple. Sans compte, la compilation
iOS fonctionne mais aucun IPA signé ne peut être produit.

Étape 1 : va sur `developer.apple.com/programs`, crée un compte Apple Developer
(Programme, 99 $ par an). Un identifiant Apple gratuit ne suffit que pour sept
jours et cinq appareils, sans publication.

---

## 3. Exigences Google Play, vérifiées

### 3.1 Version d'Android visée — **déjà satisfaite**

Depuis le **31 août 2026**, toute nouvelle application et toute mise à jour
publiée sur Google Play doit viser **Android 16 (API 36)**. Le projet vise déjà
`targetSdk 36` et `compileSdk 36`, valeurs par défaut de Flutter 3.47.4. Rien à
changer.

### 3.2 Format de livraison

Google Play exige un **App Bundle (`.aab`)**, pas un APK. Les deux sont produits
par les flux : l'APK sert à l'installation directe et aux tests, l'AAB à la
publication.

### 3.3 Vérification du développeur Android — **nouveauté à connaître**

Depuis juin 2026, Android met en place une vérification des développeurs.
Points vérifiés à la source :

- **30 septembre 2026** : l'enregistrement des applications devient obligatoire
  pour les magasins participants au Brésil, en Indonésie, à Singapour et en
  Thaïlande. La France n'est pas concernée par cette première vague.
- **2027** : extension à l'ensemble des appareils Android certifiés.
- Côté Google Play, l'enregistrement de l'application se fait depuis la page
  d'accueil de la Play Console, et devait être fait **avant le 30 septembre
  2026** pour éviter un retrait.
- Un nouveau type de compte, **« limited distribution »**, existe pour les
  étudiants et les amateurs : jusqu'à 20 appareils, **sans pièce d'identité ni
  frais**. C'est la voie à envisager si tu veux distribuer sans passer par les
  magasins.

Source : blog officiel Android Developers, 18 juin 2026.

### 3.4 Fiche du magasin

Il faudra renseigner : description, captures d'écran (téléphone, et tablette si
tu déclares le support), icône 512 × 512, bandeau 1024 × 500, catégorie,
politique de confidentialité (URL publique — `docs/confidentialite.md` devra
être hébergé), formulaire de sécurité des données et classement de contenu.

Le formulaire de sécurité des données devra déclarer : **aucune donnée
personnelle collectée**, les photos n'étant transmises que pour analyse et non
conservées. C'est exactement ce que décrit la politique de confidentialité.

---

## 4. Exigences App Store

- Compte Apple Developer actif.
- Identifiant de bundle : `io.github.axox934.assiette`, identique côté Android et
  côté iOS (déjà configuré).
- Justifications d'accès déjà présentes dans `Info.plist` : appareil photo,
  photothèque.
- `ITSAppUsesNonExemptEncryption` déjà déclaré à `false` : l'application
  n'utilise que le chiffrement standard du système, ce qui évite une demande de
  conformité à chaque envoi.
- Une politique de confidentialité est exigée pour toute application iOS, même
  gratuite.

---

## 5. Réglages à faire dans GitHub, une fois le dépôt créé

### Secrets (Settings → Secrets and variables → Actions → Secrets)

| Secret | Rôle | Obligatoire |
| --- | --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Magasin de clés de signature, encodé en base64 | pour un APK signé |
| `ANDROID_KEYSTORE_PASSWORD` | Mot de passe du magasin | idem |
| `ANDROID_KEY_ALIAS` | Alias de la clé | idem |
| `ANDROID_KEY_PASSWORD` | Mot de passe de la clé | idem |
| `IOS_DISTRIBUTION_CERTIFICATE_BASE64` | Certificat de distribution Apple | pour un IPA signé |
| `IOS_CERTIFICATE_PASSWORD` | Mot de passe du certificat | idem |
| `IOS_PROVISIONING_PROFILE_BASE64` | Profil de provisionnement | idem |
| `IOS_TEAM_ID` | Identifiant d'équipe Apple | idem |
| `IOS_KEYCHAIN_PASSWORD` | Mot de passe du trousseau temporaire | idem |

Sans ces secrets, les flux produisent tout de même un **APK signé avec la clé de
débogage** et un **IPA non signé** — utilisable pour tester, pas pour publier.

### Les quatre secrets Android sont en place

La clé de signature a été créée, et les quatre secrets déposés. Elle vit **hors du
dépôt**, dans `%USERPROFILE%\assiette-signature`, et rien de ce qui s'y trouve n'a
jamais traversé une conversation.

| Fichier | Contenu |
| --- | --- |
| `assiette-release.jks` | la clé |
| `assiette-release.jks.base64` | la même, encodée, pour GitHub |
| `mot-de-passe.txt` | le mot de passe, commun au magasin et à la clé |
| `empreinte-sha256.txt` | l'empreinte SHA-256, à comparer avec ce que Play affiche |
| `LIRE-MOI.txt` | ce qu'il faut faire de ces fichiers |

```bash
python3 tools/creer_cle_signature.py       # rejoue les fichiers dérivés, ne recrée pas la clé
python3 tools/publier_cle_signature.py     # dépose les quatre secrets
```

Trois choix qui méritent d'être notés.

**Le mot de passe n'apparaît nulle part.** Il est tiré au hasard — 40 caractères,
environ 238 bits — écrit dans un fichier, et `keytool` le lit depuis ce fichier
(`-storepass:file`). La ligne de commande d'un processus est lisible par tout
autre processus de la machine : un mot de passe qu'on y passe est un mot de passe
rendu public. Le script ne l'affiche jamais, et `publier_cle_signature.py` envoie
les valeurs à GitHub par l'entrée standard, sans passer par `--body`.

**Le mot de passe du magasin et celui de la clé sont le même.** Ce n'est pas de la
paresse : le format PKCS#12, que `keytool` produit par défaut depuis Java 9,
n'accepte pas deux mots de passe distincts et **ignore silencieusement**
`-keypass`. En tenir deux laisserait croire à une séparation qui n'existe pas.

**La validité est de 10 000 jours** (jusqu'en 2054). Le Play Store exige une clé
valide au moins jusqu'au 22 octobre 2033 ; viser cette date de justesse obligerait
à demander une réinitialisation, qui n'est pas garantie d'aboutir.

Le dossier de signature est **hors du dépôt**, et `check_no_secrets.py` refuse de
toute façon les suffixes `.jks`, `.keystore`, `.p12` : une clé qui atterrirait dans
le dépôt public serait détectée avant d'être poussée.

Empreinte SHA-256 de la clé, à comparer le jour où Play affichera la sienne :

```
22:51:8E:30:0D:F1:23:80:6F:87:BA:09:86:05:BD:C1:
2E:4E:55:D5:AB:1F:86:CD:A8:58:6B:8F:E1:CF:B1:23
```

**À faire par toi :** copier `%USERPROFILE%\assiette-signature` sur un support que
tu gardes — clé USB, disque externe, ou gestionnaire de mots de passe. Une clé
perdue ne se remplace pas : le Play Store identifie une application par son nom de
paquet **et** sa clé, donc une clé perdue oblige à publier une nouvelle
application, et les personnes qui ont installé la première ne recevront plus de
mise à jour.

### Variables (onglet Variables)

| Variable | Rôle |
| --- | --- |
| `ANALYSIS_ENDPOINT` | URL de base des fonctions serveur, par exemple `https://<projet>.supabase.co/functions/v1` |
| `SUPABASE_URL` | URL du projet Supabase |
| `SUPABASE_ANON_KEY` | Clé publique du projet. **Publique par nature** : elle est visible dans l'application, sa sécurité repose sur les politiques d'accès en base. |

Aucun de ces éléments n'est un secret exploitable : ils sont destinés à être
embarqués dans l'application.

---

## 6. Coûts à prévoir

| Poste | Coût |
| --- | --- |
| Dépôt GitHub public, flux de compilation | gratuit (minutes illimitées sur dépôt public) |
| Supabase (fonctions et base) | offre gratuite suffisante au démarrage |
| Analyse par le modèle de vision | quelques centimes pour cent analyses ; c'est le seul poste variable |
| Compte Google Play | 25 $ une fois |
| Compte Apple Developer | 99 $ par an |

Aucun de ces montants n'est engagé tant que les comptes ne sont pas créés.

---

## 7. Prérequis de compilation, vérifiés

Ces trois points ne se devinent pas : chacun a fait échouer une compilation avant
d'être identifié. Ils valent pour toute machine, y compris les serveurs de
compilation.

### 7.1 Le NDK Android est obligatoire

`path_provider_android` dépend de `jni`, qui compile du C++ par CMake et produit
`libdartjni.so` pour chaque architecture. Sans le NDK, la compilation s'arrête sur
`Android sdkmanager did not install NDK`.

Flutter 3.47.4 exige la version `28.2.13676358`, déclarée dans
`packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt` du SDK. Le flux
Android lit cette valeur à la source et n'installe le NDK que s'il manque : il n'y
a donc aucune version recopiée à maintenir.

### 7.2 Cible iOS minimale : 15.5

Le greffon `mobile_scanner` déclare `platform = :ios, '15.5.0'` dans son podspec.
En dessous, `pod install` refuse de résoudre la dépendance. La valeur est fixée à
deux endroits, qui doivent rester d'accord : `app/ios/Podfile` (ligne `platform`)
et `app/ios/Runner.xcodeproj/project.pbxproj` (`IPHONEOS_DEPLOYMENT_TARGET`).

Le Podfile est versionné. Son absence n'est pas un cas normal : le flux iOS
s'arrête s'il manque, plutôt que de laisser Flutter en fabriquer un autre.

### 7.3 Java 21

Le projet a été validé avec Java 21, le JBR fourni par Android Studio. Le bytecode
d'AGP 9.1.0 est en Java 11, donc 17 suffirait, mais les flux utilisent 21 pour
rester identiques à l'environnement de développement.

### 7.4 `flutter test` sous Windows : deux obstacles d'environnement, tous deux levés

Sur le poste Windows, `flutter test` échouait d'abord en une seconde sur :

```
%PROGRAMFILES(X86)% environment variable not found.
  #1 VisualStudio._vswherePath (package:flutter_tools/src/windows/visual_studio.dart:264:7)
  #7 VisualStudio.clPath       (package:flutter_tools/src/windows/visual_studio.dart:194:12)
  #12 _setupHooks              (package:flutter_tools/src/isolated/native_assets/native_assets.dart:273:25)
```

Le message **accuse Visual Studio, mais la cause est autre** : les paquets
`objective_c` et `sqlite3` déclarent des *hooks* de ressources natives, et
`flutter_tools` appelle `VisualStudio.clPath`. Ce getter commence par lire la
variable d'environnement `PROGRAMFILES(X86)` et **lève un `throwToolExit` si elle
est absente** — avant même de chercher `vswhere.exe`. Or elle n'est pas exposée
dans ce shell.

Fournir la variable suffit à passer : `vswhere.exe` reste introuvable, mais le
SDK ignore explicitement ce cas (`on ProcessException`, `visual_studio.dart:369`).
Ce n'est donc pas l'absence de Visual Studio qui bloquait, c'est l'absence de la
variable.

Le premier obstacle franchi, un second apparaît, sans rapport avec le premier :

```
Unable to connect to flutter_tester process:
WebSocketException: Invalid WebSocket upgrade request
```

`flutter_tester` démarre puis ouvre un port d'écoute local ; le processus de test
doit s'y reconnecter. L'environnement définit `HTTP_PROXY` et `HTTPS_PROXY` sans
`NO_PROXY`, donc le trafic vers `127.0.0.1` part vers le proxy, qui répond `400`.

**Conséquence pratique : `flutter test` tourne en local.** Les deux réglages sont
posés par `tools/environnement_flutter.py`, que `tools/lancer_verifications_dart.py`
applique sans passer par `env` — qui avale la sortie dans ce bac à sable :

```bash
python tools/lancer_verifications_dart.py                     # format, analyse, tests
python tools/lancer_verifications_dart.py test                # les tests seuls
python tools/lancer_verifications_dart.py test test/data/mon_test.dart
```

`ci.yml` continue d'exécuter `flutter test` sur `ubuntu-latest`, où aucun des
deux réglages n'est nécessaire. Le chemin Linux reste la référence ; le chemin
Windows sert à boucler vite pendant le développement.

### 7.5 Avertissement de dépréciation Node 20

Les flux émettent un avertissement : `actions/checkout@v4` et
`actions/upload-artifact@v4` visent Node.js 20, que GitHub force désormais sur
Node.js 24. Les actions continuent de fonctionner — GitHub les met à niveau
automatiquement. À reprendre le jour où ces versions cesseront d'être acceptées.

### 7.6 Le Kotlin intégré d'AGP 9 divise l'écosystème des greffons

Le projet utilise **AGP 9.1.0**. Or AGP 9 fait du « Kotlin intégré » (*built-in
Kotlin*) le comportement par défaut : appliquer `org.jetbrains.kotlin.android`
provoque désormais un échec explicite —

> The 'org.jetbrains.kotlin.android' plugin is no longer required for Kotlin
> support since AGP 9.0

Le migrateur de Flutter réagit en écrivant `android.builtInKotlin=false` dans
`app/android/gradle.properties`, ce qui rétablit l'ancien fonctionnement. C'est
pourquoi ce fichier contient la ligne, avec le commentaire du gabarit.

Conséquence : **deux familles de greffons, mutuellement exclusives**, puisque le
drapeau est global au projet.

| Famille | Ce qu'elle fait | Exige |
| --- | --- | --- |
| `share_plus`, `mobile_scanner`, `file_picker` 10.x | appliquent `kotlin-android` **sans condition** | `builtInKotlin=false` |
| `file_picker` 11.x, `file_selector_android` 0.5.2+11 | ne l'appliquent plus, comptent sur le Kotlin intégré | `builtInKotlin=true` |

Le projet reste sur `builtInKotlin=false`, parce que `share_plus` et
`mobile_scanner` en dépendent. `file_picker` est donc **épinglé à `^10.3.10`**.

Mesuré, et non supposé :

- `file_picker 11.0.3` fait échouer `:app:compileReleaseJavaWithJavac` sur
  `cannot find symbol: class FilePickerPlugin` — ses sources Kotlin ne sont
  compilées par personne ;
- `file_selector_android 0.5.2+11` (paquet officiel de l'équipe Flutter) a le
  même défaut : ses sources Kotlin cohabitent avec le Java qui les appelle ;
- `file_picker 10.3.10` applique `org.jetbrains.kotlin.android` sans condition et
  compile ;
- `file_picker 10.3.11` est **retirée** par son auteur : `pub` la refuse avec
  `which doesn't match any versions`. D'où `^10.3.10`, et non `^10.3.11`.

Contrepartie assumée : la 10.x embarque `org.apache.tika:tika-core` (~300 Ko),
que la 11.0.3 a retiré. À reprendre le jour où Flutter basculera sur le Kotlin
intégré — le jour où `android.builtInKotlin` disparaîtra du gabarit.

---

## 8. La chaîne de garde

Sept contrôles tournent à chaque `push` : six dans `ci.yml` (travail « Analyse et
tests »), et `check_workflows.py` dans un travail séparé. Chacun lit une propriété
que **rien d'autre ne lit** : c'est ce qui justifie sa présence, et c'est aussi
pourquoi aucun ne doit être retiré sans être remplacé.

| Contrôle | Ce qu'il attrape |
| --- | --- |
| `tools/check_no_secrets.py` | un secret qui aurait été committé — le dépôt est public |
| `tools/check_prompt_sync.py` | un prompt modifié d'un côté et pas de l'autre |
| `tools/check_fins_de_ligne.py` | un blob CRLF dans l'index, ou une copie de travail hors `eol=lf` |
| `tools/check_ios.py` | 92 vérifications iOS : icônes, storyboard, `Info.plist`, cible, Podfile |
| `tools/check_adresses_du_depot.py` | une adresse GitHub du code qui désigne un autre dépôt |
| `tools/verifier_version_build.py` | une régression dans la logique qui décide de la version publiée |
| `tools/check_workflows.py` | YAML invalide, action non épinglée, `permissions` absentes, `run:` qui ne passe pas `bash -n`, script du dépôt appelé mais absent, un flux qui ne tire plus la version du même endroit que l'autre, et une compilation qui n'injecte pas `APP_VERSION` depuis la sortie du script de version |

### Le schéma local ne change que par une seule liste

La base SQLite de l'appareil est passée en **schéma v2** (portions nommées, suivi du
poids). Une base installée en v1 doit migrer **sans rien perdre** : c'est la
première fois que ce projet a des données utilisateur à préserver.

Trois règles, tenues par un test plutôt que par la vigilance :

1. **Une seule liste d'ajouts.** `_ajoutsVersion2` dans `app_database.dart` sert à
   la fois à `onCreate` (base neuve) et à `onUpgrade` (base existante). Deux listes
   séparées divergeraient au premier oubli, et une base neuve et une base migrée
   n'auraient plus la même forme.
2. **Aucun `DROP`, aucun `DELETE`.** Une migration qui recrée une table peut
   perdre ce qu'elle n'a pas pensé à recopier.
3. **La forme est comparée, pas supposée.** `app/test/data/migration_test.dart`
   construit une base v1 **remplie**, la migre, puis compare sa structure à celle
   d'une base neuve — colonnes et objets SQLite, triés. Un test qui ne vérifierait
   que « les données sont là » laisserait passer une colonne manquante.

Le schéma v1 du test est **recopié à la main**, volontairement : c'est un fait
historique, pas une dérivation du code courant. Le dériver ferait qu'une migration
cassée serait testée contre la forme cassée, et le test resterait vert.

Le test a été **falsifié** : remplacer `if (from < 2)` par `if (from < 1)` fait
tomber 4 des 7 cas. Un test de migration qui n'a jamais échoué ne prouve rien.

### La version publiée, décidée à un seul endroit

Le nom d'un artefact venait du tag Git, la version inscrite dans le binaire venait
de `app/pubspec.yaml`. Le tag `v0.1.1` a donc produit une IPA nommée `v0.1.1` dont
l'`Info.plist` déclarait `0.1.0`. Deux sources de vérité, et rien pour dire laquelle
croyait la personne qui installe le fichier.

`tools/version_build.sh` est le point unique qui décide, pour les deux plateformes :
le tag fait foi, sinon une version saisie à la main, sinon le pubspec. Il est
éprouvé hors GitHub, ce qui compte puisqu'il ne s'exécute en vrai que sur un tag —
donc sur une version qu'on ne peut pas rejouer sans en créer un autre.

```bash
python tools/verifier_version_build.py           # 11 cas
python tools/bancs/falsifier_version_build.py    # 6 mutations + 1 témoin négatif
```

Et, sur un binaire réellement produit, le seul contrôle qui lit la valeur
**inscrite** — tous les autres vérifient la valeur passée à la compilation :

```bash
python tools/verifier_version_binaire.py app-release-0.1.0+1-debug-key.apk
python tools/verifier_version_binaire.py Assiette-0.1.0+1-non-signee.ipa
```

Il lit `versionName`/`versionCode` dans l'APK (`aapt2 dump badging`) et
`CFBundleShortVersionString`/`CFBundleVersion` dans l'`Info.plist` de l'IPA, puis
refuse un fichier dont le nom annonce autre chose. Falsifié sur le vrai fichier
défectueux : confronté à `Assiette-v0.1.1-non-signee.ipa`, qui déclare `0.1.0`, il
répond `NOM ET CONTENU DIVERGENT` et sort en erreur.

Deux points valent d'être notés.

**Un refus ne vaut que s'il nomme sa cause.** Le contrôle exige le message, pas
seulement le code de sortie. Sans cela, le cas « pubspec absent » réussissait alors
que son garde-fou avait disparu du script : un garde-fou situé plus loin attrapait
le vide laissé derrière, et le cas ne distinguait donc rien.

**Une version qui n'est pas des chiffres séparés par des points est refusée.** Pour
iOS, Flutter retire *en silence* tout caractère hors `[0-9.]` avant d'écrire
`CFBundleShortVersionString` (`build_info.dart`, `validatedBuildNameForPlatform`) :
un tag `release-2.0` donnerait `2.0.0` sur iOS et `release-2.0` sur Android. Un
refus nommé vaut mieux qu'une divergence muette.

### Chaque contrôle a été falsifié

Un contrôle qui n'a jamais échoué ne prouve rien : il peut regarder au mauvais
endroit et compter zéro défaut aussi tranquillement qu'un contrôle juste. Les
bancs vivent dans `tools/bancs/` — **dans le dépôt**, pas dans un dossier
temporaire, pour qu'ils soient rejouables.

```bash
python3 tools/bancs/falsifier_fins_de_ligne.py         # 6 cas
python3 tools/bancs/falsifier_ios.py                   # 6 cas
python3 tools/bancs/falsifier_adresses.py              # 4 cas
python3 tools/bancs/falsifier_client_deepseek.py       # 2 cas — serveur (Deno)
python3 tools/bancs/falsifier_client_deepseek_dart.py  # 6 cas — application (Flutter)
python3 tools/bancs/falsifier_proxy_dart.py            # 6 cas — mode proxy (Flutter)
python3 tools/bancs/falsifier_version_build.py         # 6 cas — version publiée
python3 tools/bancs/falsifier_check_workflows.py       # 19 cas — validation des flux
```

`falsifier_check_workflows.py` éprouve le seul contrôle qui lit `.github/workflows`,
et qui n'en avait aucun. Trois de ses cas méritent d'être cités :

- une commande `flutter build` qui reçoit un `APP_ENV` mais **pas** d'`APP_VERSION` :
  l'écran des réglages annoncerait une version sans rapport avec le binaire ;
- une `APP_VERSION` **recopiée en dur** (`0.1.2`) : elle se désynchroniserait au
  premier oubli de mise à jour ;
- l'`APP_ENV` sur une commande et l'`APP_VERSION` sur la **suivante**, dans le même
  bloc `run:`. Un contrôle qui chercherait les deux chaînes dans le script entier
  passerait ; celui-ci les attribue à la bonne commande, et tombe.

Chaque banc inclut un **témoin négatif** — un `.bat` en CRLF conforme à son
attribut n'est pas signalé, citer `flutter/flutter` reste permis, reformuler un
commentaire ne déclenche rien. Sans lui, rien ne prouve que le contrôle
**distingue**, plutôt qu'il ne compte.

`tools/bancs/banc.py` est le harnais partagé. Sa méthode `muter()` **lève une
exception** quand son ancre ne correspond pas : une mutation qui ne mute pas est
une erreur du banc, pas un résultat. Sans cette garantie, un banc peut conclure
« non détecté » alors que la mutation n'a jamais eu lieu — ce qui est arrivé.

Le harnais connaît une seconde confusion, tout aussi trompeuse : **une mutation
qui casse la compilation** rend un code de sortie non nul sans qu'aucun test
n'ait échoué. Le banc des tests Flutter compte donc les tests réellement
exécutés et lève `MesureImpossible` si le total attendu n'est pas atteint, au
lieu d'annoncer un trou de couverture là où il n'y a qu'une mutation fautive.
Même chose si le rapport JSON ne contient aucun test nommé en échec.

Enfin, **un banc interrompu doit rendre le dépôt intact**. `SIGTERM` ne lève
aucune exception, et `KeyboardInterrupt` hérite de `BaseException` et non
d'`Exception` : ni l'un ni l'autre ne traversait un `except Exception`. Mesure :
un banc tué en pleine mutation a laissé `tools/version_build.sh` **amputé de son
garde-fou**, et comme le fichier n'était pas encore suivi par git, aucun
`git checkout` ne pouvait le rendre. Le harnais arme désormais une restauration
d'urgence : gestionnaire de signal, `atexit`, et capture de `BaseException`
autour des deux phases à risque.

### Réparer

```bash
python3 tools/normaliser_fins_de_ligne.py             # mesure, ne touche à rien
python3 tools/normaliser_fins_de_ligne.py --appliquer
```

### Lancer les vérifications Dart en local

```bash
python tools/lancer_verifications_dart.py                     # format, analyse, tests
python tools/lancer_verifications_dart.py test                # les tests seuls
python tools/lancer_verifications_dart.py test test/data/mon_test.dart
```

`tools/environnement_flutter.py` porte les deux réglages que la machine réclame,
et pourquoi (voir §7.4). Le script les applique sans passer par `env`, qui avale
la sortie dans ce bac à sable.

Il rejoue **exactement** les trois étapes Dart de `ci.yml`. Deux lanceurs
distincts finiraient par ne plus poser le même environnement, et celui qu'on
n'utilise pas est celui qui ment.


---

## 9. Publier une version

Une version se publie en trois gestes, et le troisième est celui qui compte.

### 1. Monter la version du projet

Dans `app/pubspec.yaml`, la ligne `version:`. Elle doit dire **la même chose que le
tag** qu'on s'apprête à poser. Le tag reste la source de vérité, mais un pubspec
qui le contredit fait diverger les compilations de branche et celles de tag, sans
que rien ne le signale.

### 2. Poser le tag, et le pousser

```bash
git tag -a v0.1.3 -m "Assiette v0.1.3"
git push origin v0.1.3
```

Le `push` du tag déclenche les trois flux — `ci.yml`, `android.yml`, `ios.yml` —
et c'est tout. Le numéro de compilation est `GITHUB_RUN_NUMBER` : Android exige un
`versionCode` strictement croissant à chaque envoi sur le Play Store, et reprendre
le numéro du pubspec ferait refuser le deuxième envoi d'un même tag.

### 3. Publier, après vérification

```bash
python tools/publier_une_version.py v0.1.3 --essai   # vérifie, ne publie rien
python tools/publier_une_version.py v0.1.3           # publie
```

Le script télécharge les artefacts du tag, **confronte le nom de chacun à la
version que le binaire déclare**, et refuse de publier si les deux divergent. La
vérification est avant la publication, et elle est bloquante : un binaire faux qui
n'est pas publié ne coûte rien, un binaire faux qui l'est coûte la confiance de la
personne qui l'installe.

Il rédige aussi les notes de version : ce qui a changé depuis le tag précédent, et
**ce qui a été contrôlé** dans chaque fichier. Un AAB n'est pas vérifiable de la
même façon — son manifeste est en protobuf, pas en binaire Android classique — et
le script l'écrit noir sur blanc plutôt que de laisser croire à un contrôle qui
n'a pas eu lieu.

Les fichiers restent dans `artefacts-a-publier/`, ignoré par git : un binaire
committé est un binaire que personne ne remplace.
