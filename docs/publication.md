# Publication — Assiette

Ce document décrit ce qui est déjà en place, ce qui reste à faire, et à quelles
conditions actuelles publier. Les exigences des magasins changent souvent :
elles ont été vérifiées le 18 septembre 2026, aux sources citées.

---

## 1. Ce qui est déjà prêt

| Élément | État |
| --- | --- |
| Code source complet, analysé sans avertissement | prêt |
| 540 tests de l'application, tous verts | prêt |
| 18 tests du serveur, tous verts | prêt |
| Dépôt public | https://github.com/Msoumaya2019/assiette |
| Flux `ci.yml` — analyse, 540 tests, 9 contrôles | **vert** |
| Flux `ci.yml` — migrations Supabase exécutées sur un vrai PostgreSQL | **vert** (35 épreuves) |
| Flux Android — APK et AAB | **vert**, artefacts signés et vérifiés |
| Flux iOS — IPA non signée | **vert**, artefact vérifié |
| Déclenchement par étiquette `v*` | **vert** (`v0.1.0`, `v0.1.1`, `v0.1.2`, `v0.1.3`, `v0.1.4`, `v0.1.5`) |
| Dernière version publiée | **`v0.1.5`** — APK signé, AAB signé, IPA (unité des valeurs remise d'accord avec la portion affichée) |
| Version à **ne pas** installer | `v0.1.3` — l'écran de suivi du poids y tombe dès la première pesée. Ses notes portent l'avertissement. |
| Version au chiffre trompeur | `v0.1.4` — utilisable, mais trois écrans annoncent « pour 1 pot (125 g) » sous le chiffre des 100 g. Corrigé en `v0.1.5` ; voir §8. |
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
| `v0.1.4` | `app-release-0.1.4+8-signe.apk` | déclare `0.1.4` / `8`, 84 381 057 octets, signé avec la clé de release, **et contient le correctif** (voir ci-dessous) |
| `v0.1.4` | `app-release-0.1.4+8-signe.aab` | 72 263 838 octets, version non lisible dans un AAB — non vérifiée, et le script l'écrit |
| `v0.1.4` | `Assiette-0.1.4+7-non-signee.ipa` | déclare `0.1.4` / `7`, 17 057 982 octets |
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

### Un binaire vérifié par son contenu, pas seulement par son nom

Le contrôle de version lit la valeur **inscrite** dans le binaire. Il ne dit pas
que le binaire contient le **code** qu'on croit. La différence compte : `v0.1.3` a
été publiée avec un écran de suivi du poids qui tombait dès la première pesée, et
aucun contrôle de version n'aurait pu le voir.

`v0.1.4` corrige ce défaut. Le correctif se prouve sur le fichier livré : le commit
correctif a renommé un libellé d'accessibilité en `Ajouter 1 <unité>` (l'ancienne
forme, `Ajouter une <unité>`, supposait un genre que l'unité n'a pas forcément).
Cette chaîne n'existe que dans le code corrigé, et se cherche donc dans le
`libapp.so` de l'APK :

| Binaire | `Ajouter 1 ` | `Ajouter une ` |
| --- | --- | --- |
| `v0.1.3` | absent | 3 occurrences |
| `v0.1.4` | **1 occurrence** | 2 occurrences — les deux autres libellés, inchangés |

Deux APK de `84 381 057` octets exactement, donc de taille identique, et pourtant
d'empreintes différentes : la taille ne prouve rien, et n'aurait pas dû servir
d'indice. C'est le contenu qui tranche.

**Une release fautive ne se réécrit pas, mais elle se signale.** Ses fichiers
restent en ligne tels quels ; ses **notes**, elles, gagnent un avertissement en
tête, qui renvoie à la version corrigée. Laisser un binaire cassé en
téléchargement sans rien dire coûterait la confiance de la personne qui
l'installe. `tools/annoter_release.py` fait cet ajout, et retire un
avertissement déjà présent avant d'en écrire un — sans quoi le relancer les
empilerait.

### Le correctif de `v0.1.5`, prouvé dans les deux binaires

Le changement de `v0.1.5` est **arithmétique** : il ne pose aucun nouveau littéral
dans le code, et un témoin de chaîne ne pouvait donc rien prouver. La sonde utile
était ailleurs — **le nom de la fonction**, qui survit à la compilation AOT :

| Sonde | `App.framework/App` (IPA) | `lib/arm64-v8a/libapp.so` (APK) |
| --- | --- | --- |
| `referenceDePortion` — l'accesseur supprimé | 0 | 0 |
| `apercuDePortion` — la fonction qui le remplace | **1** | **1** |

Témoin de contrôle : `Flutter`, 20 fois dans l'un et 28 fois dans l'autre. Sans lui,
un zéro partout se lirait « absent » alors qu'il se lirait « fichier non lu ».

Deux mesures ont dû être **localisées** avant d'être conclues, et les deux pièges
sont propres à Flutter :

- **`_CodeSignature` apparaît 6 fois dans un IPA non signé**, ce qui contredit la
  règle « 0 attendu ». Les six appartiennent à trois **cadres** livrés déjà signés
  par le moteur — `objective_c.framework`, `Flutter.framework`, `App.framework` —,
  et une signature de cadre ne signe pas l'application. Ce qui tranche est
  `Payload/Runner.app/_CodeSignature/` : **absente**. Compter la sous-chaîne dans
  toute l'archive répond à la mauvaise question.
- **`App.framework/App` commence par `bebafeca`** lu en petit-boutiste, et l'on
  conclut à un fichier corrompu. C'est la même valeur que `cafebabe` lue en
  **grand-boutiste** : un binaire **universel**, ici à une seule architecture
  (arm64, 10 008 144 octets). La magie d'un fat se lit en grand-boutiste.

La version inscrite est bien celle du tag — `0.1.5` / `8` dans l'IPA, `0.1.5+9` dans
l'APK —, et l'application n'est pas signée : `embedded.mobileprovision` est absent.

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

La liste des actions nommées s'allonge au fil des exécutions —
`actions/setup-node@v4` et `actions/setup-python@v5` y figurent désormais aussi.

**Ce que cet avertissement ne dit pas, et qui a failli être écrit à tort.**
L'ajout de la tâche `migrations` a d'abord été accompagné d'un commentaire
affirmant qu'épingler `node-version: "22"` faisait disparaître l'avertissement.
C'est faux, et la mesure le dit : il apparaît dans **toutes** les tâches, y
compris « Analyse et tests » et « Serveur », qui n'ont aucun Node installé par ce
moyen. Il porte sur le **moteur des actions**, pas sur l'interpréteur du travail.
Épingler Node reste utile — pour que le verdict ne dépende pas du Node livré par
l'exécuteur — mais ce n'est pas la même raison, et confondre les deux ferait
chercher une correction qui n'existe pas de ce côté.

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

### 7.7 Un échec de CI qui n'accuse pas ce dépôt

Le 21 septembre, la tâche « Analyse et tests » est tombée sur l'étape des tests,
avec ce message :

```
Unhandled exception:
Bad state: Hash of downloaded file libsqlite3.x64.linux.so is bef140a1…,
expected 4b986901….
  Building assets for package:sqlite3 failed.
```

Rien dans ce message ne parle de ce dépôt, et c'est normal : il n'y était pour
rien. Le paquet `sqlite3` — dont `sqflite_common_ffi` dépend pour les tests —
télécharge une bibliothèque native précompilée depuis une *release* GitHub, puis
**vérifie son empreinte SHA-256**. L'empreinte attendue est inscrite dans le
paquet, et l'exécuteur a reçu autre chose que le binaire : page d'erreur d'un
proxy, téléchargement tronqué, incident de CDN.

Mesure faite pour trancher entre « le serveur a changé » et « la récupération a
échoué » — le fichier servi aujourd'hui :

```
$ sha256sum libsqlite3.x64.linux.so
4b98690121dbd05d5a4df3375d0e9ed7a339d8b26ca2e573bd663976b9b0f9af
```

C'est exactement l'empreinte attendue. L'asset n'a donc pas changé : le paquet
avait raison, et c'est bien la récupération qui a échoué. Relancer la tâche en
échec (`gh run rerun <id> --failed`) est passé au vert du premier coup.

**À retenir :** cet échec est passager et n'appelle aucune correction de code. Le
vérifier avant de chercher un bug — un message qui nomme un fichier que ce dépôt
ne contient pas ne parle pas de ce dépôt.

> Piège de lecture, rencontré au même moment : `gh run watch … | tail -3; echo $?`
> rend le code de sortie de `tail`, pas celui de `gh`. Le verdict affiché était
> « 0 » alors que la tâche venait d'échouer. C'est le même piège que celui décrit
> plus bas pour `lancer_bancs.py` : **après un tube, `$?` n'est pas le code de la
> commande.**

---

## 8. La chaîne de garde

Neuf contrôles tournent à chaque `push` : sept dans `ci.yml` (travail « Analyse et
tests »), `check_workflows.py` dans un travail séparé, et l'épreuve des migrations
dans un troisième. Chacun lit une propriété que **rien d'autre ne lit** : c'est ce
qui justifie sa présence, et c'est aussi pourquoi aucun ne doit être retiré sans
être remplacé.

| Contrôle | Ce qu'il attrape |
| --- | --- |
| `tools/check_no_secrets.py` | un secret qui aurait été committé — le dépôt est public |
| `tools/check_prompt_sync.py` | un prompt modifié d'un côté et pas de l'autre |
| `tools/check_fins_de_ligne.py` | un blob CRLF dans l'index, ou une copie de travail hors `eol=lf` |
| `tools/check_ios.py` | 92 vérifications iOS : icônes, storyboard, `Info.plist`, cible, Podfile |
| `tools/check_adresses_du_depot.py` | une adresse GitHub du code qui désigne un autre dépôt |
| `tools/check_migration_serveur.py` | une colonne du schéma local sans destination côté serveur, une table ajoutée d'un côté seulement, une politique RLS sans son `drop` |
| `tools/verifier_version_build.py` | une régression dans la logique qui décide de la version publiée |
| `tools/check_workflows.py` | YAML invalide, action non épinglée, `permissions` absentes, `run:` qui ne passe pas `bash -n`, script du dépôt appelé mais absent, un flux qui ne tire plus la version du même endroit que l'autre, et une compilation qui n'injecte pas `APP_VERSION` depuis la sortie du script de version |
| `tools/eprouver_migration_sur_postgres.mjs` | du SQL qui ne s'exécute pas : colonne mal nommée, `references` vers une table absente, parenthèse en trop — une politique RLS qui laisserait écrire au nom d'un autre, une reprise de données fausse, et une migration écrite mais oubliée de la liste de l'épreuve |

### Le schéma local ne change que par paliers

La base SQLite de l'appareil est passée en **schéma v2** (portions nommées, suivi du
poids), puis en **v3** (pierres tombales sur `portions`, `templates` et `favorites`).
Une base installée en v1 doit migrer **sans rien perdre**, et elle doit pouvoir le
faire en traversant les deux paliers : c'est la première fois que ce projet a des
données utilisateur à préserver.

Quatre règles, tenues par un test plutôt que par la vigilance :

1. **Une seule liste d'ajouts par palier.** `_ajoutsVersion2` et `_ajoutsVersion3`
   servent à la fois à `onCreate` (base neuve) et à `onUpgrade` (base existante),
   appliquées dans l'ordre. Deux listes séparées par chemin divergeraient au premier
   oubli, et une base neuve et une base migrée n'auraient plus la même forme.
2. **Aucun `DROP`, aucun `DELETE`.** Une migration qui recrée une table peut
   perdre ce qu'elle n'a pas pensé à recopier.
3. **La forme est comparée, pas supposée.** `app/test/data/migration_test.dart`
   construit une base v1 **remplie**, la migre, puis compare sa structure à celle
   d'une base neuve — colonnes et objets SQLite, triés. Un test qui ne vérifierait
   que « les données sont là » laisserait passer une colonne manquante.
4. **Chaque palier est traversé seul.** Une base v1 traverse 1→2 puis 2→3 dans le
   même appel ; cela n'exerce donc jamais le palier 2→3 **isolément**. Un ordre
   égaré d'une liste à l'autre passerait inaperçu, et ne casserait que les appareils
   restés en version 2 — ceux qu'on ne peut pas remettre à zéro. Le banc construit
   donc une base réellement en v2, et lui fait rejoindre le schéma courant.

Les schémas v1 et v2 du test sont **recopiés à la main**, volontairement : ce sont
des faits historiques, pas une dérivation du code courant. Les dériver ferait qu'une
migration cassée serait testée contre la forme cassée, et le test resterait vert.

Le test a été **falsifié** : remplacer `if (from < 2)` par `if (from < 1)` fait
tomber 4 des 7 cas. Un test de migration qui n'a jamais échoué ne prouve rien.

### Le schéma serveur, remis d'accord — deux fois

La même vérité est écrite à deux endroits qui ne peuvent pas se lire :
`app_database.dart` décrit ce que l'application stocke, `backend/supabase/migrations/`
ce que le serveur acceptera. Rien ne les reliait.

Le 21 septembre, la comparaison a été faite à la main, et le serveur était **en
retard de deux versions** : il ne connaissait ni les portions nommées, ni les
pesées, ni les mensurations, et `meal_items` lui manquait huit colonnes. Aucune
erreur ne se déclenchait — parce que rien ne lit ce schéma aujourd'hui. Le jour où
la synchronisation aurait été branchée, tout le suivi du poids aurait été perdu
**en silence**, chez l'utilisateur, sur des données qu'il avait saisies.

`0002_portions_et_suivi.sql` comble le retard. `tools/check_migration_serveur.py`
tient l'accord, dans les deux sens : chaque colonne locale doit avoir une
destination serveur, et l'ensemble des colonnes serveur sans équivalent local est
**déclaré une à une** — un `user_id` ou un `total_carbs_g` dénormalisé sont
normaux, un oubli ne l'est pas. Les deux ensembles sont clos : une table ajoutée
d'un côté fait échouer le contrôle tant qu'elle n'a pas été prise en compte.

**Puis le schéma local est passé en v3**, et le serveur a repris du retard. Cette
fois, personne n'a eu à s'en apercevoir : le contrôle a signalé quatre défauts de
lui-même, dans **les deux sens** — deux colonnes locales sans destination
(`favorites.updated_at`, `portions.deleted_at`) et deux déclarations devenues
fausses (`meal_templates.deleted_at`, `favorites.deleted_at`, que le local alimente
désormais). Un contrôle écrit pour fermer un retard a fermé le suivant sans qu'on
lui demande rien. `0003_pierres_tombales.sql` les corrige.

Trois détails de lecture, tous mesurés en écrivant ce contrôle :

**Un `create table` se lit ligne à ligne, un `alter table … add column` s'écrit sur
plusieurs lignes.** Aplatir le fichier avant d'extraire les colonnes d'un bloc ne
rend que la première — mesuré : `meals` ne donnait qu'une colonne sur dix-neuf. Les
deux lectures coexistent, chacune sur la forme de texte qui lui convient.

**Un commentaire qui cite une colonne la déclare présente.** Le fichier de migration
*documente* ce qu'il ajoute : un lecteur qui garde les commentaires trouve
`portion_label` dans la phrase qui l'explique. Le retrait des commentaires est donc
éprouvé **dans les deux sens** — colonne retirée avec le commentaire qui la nomme :
le contrôle tombe ; le même état, retrait désactivé : il reste vert sur un fichier
fautif. Le second temps est le seul qui établisse que ce retrait porte quelque
chose.

**Un commentaire de migration peut devenir faux sans que le DDL change.** Le
commentaire de `0002` annonçait « pas de `deleted_at` : le schéma local n'en a pas
non plus ». Il était juste quand il a été écrit. Il a été corrigé sur place, et
seulement lui : un commentaire n'est pas du DDL, le corriger ne change rien à ce
qu'une migration déjà appliquée a fait. Le DDL, lui, est de l'histoire et ne bouge
plus.

### Le contrôle qui était vert en n'ayant rien mesuré

Un validateur de syntaxe écrit plus tôt annonçait, sur `0001_init.sql` :

```
Politiques : 0 | tables : 6
[OK] forme rejouable : chaque politique a son drop
```

Le fichier porte **six** politiques. Le motif de lecture exigeait un retour à la
ligne entre le nom de la politique et `on` ; aucune des six n'en a. Le lecteur en
voyait donc zéro, la boucle de vérification ne s'exécutait pas, et le verdict était
**vert en n'ayant rien mesuré** — depuis le premier jour.

Le contrôle écrit ici ne se contente pas de corriger le motif. Chaque lecteur est
double d'un **comptage brut indépendant** — le nombre d'occurrences du texte
`create policy`, sans motif élaboré — et si le lecteur voit moins que le comptage
brut, le contrôle échoue. C'est le comptage brut qui l'emporte. Le banc reproduit
l'aveuglement historique, motif fautif remis en place, et exige que le contrôle
tombe malgré tout.

### La correspondance des noms, déclarée une seule fois

Les deux schémas ne se ressemblent pas : `templates` s'appelle `meal_templates`
côté serveur, `pesees` s'appelle `weight_entries`, `mesures` s'appelle
`body_measurements` ; `poids_kg` devient `weight_kg`, `payload_json` devient
`payload`, `mesure_le` devient `measured_at` ; et l'identifiant du téléphone
devient `client_id`, le serveur gardant le sien. Rien de tout cela ne se déduit :
il faut le déclarer.

Cette déclaration vivait dans `tools/check_migration_serveur.py`, c'est-à-dire
dans le contrôle — alors que son lecteur naturel est le **transport**, qui doit
traduire dans les deux sens. Deux copies auraient suivi deux chemins. Elle est
donc désormais déclarée en Dart, dans
`app/lib/data/distant/correspondance_distant.dart`, et le contrôle la **lit**.
Un seul endroit porte la vérité ; le contrôle tient son accord avec les
migrations, dans les deux sens.

Le lecteur ajouté a sa propre faiblesse, et elle est instructive. Il refuse de
conclure sous un **plancher** — même discipline que le comptage brut des
politiques : un lecteur qui ne trouve rien rend un vert qui ne prouve rien. Mais
un plancher posé **à la valeur exacte** fait pire que ne rien faire : retirer
*une* entrée de la déclaration le déclenchait, et il sortait avant que le
contrôle d'accord ne voie la colonne perdue. Deux cas du banc sont d'abord
passés « non détectés » pour cette seule raison. Le plancher a donc reçu une
**marge** : assez large pour qu'une entrée retirée atteigne le contrôle, assez
étroite pour qu'un lecteur cassé le fasse tomber. Un garde-fou qui se substitue
au contrôle qu'il protège n'est pas un garde-fou de plus, c'est un garde-fou de
moins.

### Une migration neuve ne peut plus passer inaperçue

L'épreuve PGlite listait ses migrations **en dur**, dans deux boucles. Une
migration écrite plus tard aurait donc été silencieusement non éprouvée, et le
script aurait rendu un vert sur un ensemble incomplet — exactement le défaut du
validateur qui annonçait « Politiques : 0 ».

Le script **découvre** désormais les fichiers sur le disque et exige de les
retrouver dans une liste déclarée, `MIGRATIONS_ATTENDUES`. Un fichier présent et
non déclaré, ou déclaré et absent, fait échouer l'épreuve en le nommant.

Et ce garde-fou est lui-même éprouvé, dans les deux sens : le banc crée une
migration non déclarée (l'épreuve tombe), puis le même oubli avec le garde-fou
rendu inatteignable (l'épreuve reste verte). Le second temps est le seul qui
établisse que c'est bien le garde-fou qui porte quelque chose.

### Un nombre et son unité peuvent se contredire

Trois écrans — la fiche produit après un scan, les résultats de recherche, les
favoris — annonçaient « 12 g de glucides pour 1 pot (125 g) ». Le pot en contient
15 : le nombre affiché était celui des **100 g**, sous l'unité du pot. Un
cinquième de moins que la réalité, et sous une étiquette qui affirmait le
contraire.

L'intention était juste, et écrite dans le code : « la référence affichée suit la
portion retenue pour ce produit ». Seule la référence avait suivi ; le nombre,
non. La fonction qui produisait l'étiquette était séparée de celle qui produisait
les valeurs, et rien ne les obligeait à parler de la même unité.

La correction ne recalcule pas les trois affichages : elle rend la divergence
**impossible**. `referenceDePortion()` a disparu, remplacée par
`apercuDePortion()`, qui rend les valeurs **et** leur unité dans le même appel —
obtenir l'étiquette oblige désormais à obtenir les valeurs qui vont avec. Le test
correspondant vérifie les deux ensemble, parce que pris séparément chacun des deux
était correct : c'est le seul contrôle qui aurait attrapé ce défaut.

Deux choses valent d'être dites. Ce n'est **pas** une régression : le défaut est
apparu avec les portions nommées, dans le commit `1ef04dc`, et les 325 tests
étaient verts. Et il est dans les binaires publiés — `git tag --contains 1ef04dc`
rend `v0.1.3` et `v0.1.4`. **La version `v0.1.4` affichait donc cette unité
trompeuse sur les trois écrans** — c'est elle qui porte l'avertissement dans ses
notes. La correction est publiée en `v0.1.5`, et prouvée dans ses deux binaires (§1).

### La règle d'arbitrage, décidée et éprouvée

Deux appareils modifient la même ligne hors ligne. Il fallait décider laquelle garder —
et la vraie question n'était pas « laquelle est la bonne », mais **comment garantir que
les deux appareils prennent la même décision**. Deux appareils qui se croient chacun
vainqueur ne convergent jamais : ils s'échangent leurs versions à chaque
synchronisation, indéfiniment.

La règle vit dans `app/lib/models/arbitrage.dart` :

1. la modification la plus récente gagne (`updated_at`) ;
2. à date égale, **la suppression gagne** ;
3. sinon, la plus grande empreinte de contenu gagne ;
4. empreintes égales : les versions sont identiques, il n'y a rien à faire.

**Aucune des trois premières règles ne regarde quel côté est « le mien ».** C'est
exactement ce qui fait converger : la décision ne dépend que de la paire, donc inverser
les deux côtés inverse le verdict. L'écriture la plus naturelle — « en cas d'égalité, je
garde ma version » — passe tous les autres cas et **ne converge pas** : c'est le premier
cas du banc de falsification, et c'est celui qui compte.

Trois décisions de méthode valent d'être notées :

- **La règle vit d'un seul côté, volontairement.** C'est le client qui connaît les deux
  versions, décide, puis pousse la gagnante. Un serveur qui appliquerait la même règle
  serait une seconde implémentation à tenir d'accord avec la première — exactement le
  genre d'accord qui se défait en silence.
- **« La suppression gagne » ne vaut qu'à date égale.** Une pierre tombale ancienne ne
  bat pas une modification plus récente ; c'est le cas que les tests distinguent
  explicitement, parce que la formulation courte — « la suppression gagne » — serait
  fausse.
- **Une date inconnue (zéro) perd contre toute date connue**, sans cas particulier : une
  sauvegarde écrite avant que la colonne existe n'en porte pas. Deux dates inconnues ne
  se départagent pas par la date, et retombent sur l'empreinte.

### Le plan de synchronisation, et ce qu'il ajoute à la règle

La règle d'arbitrage tranche pour **une** ligne. `app/lib/models/synchronisation.dart`
tranche pour **un ensemble**, et c'est là que se posent trois questions qui n'existent pas
à l'échelle d'une ligne :

- une ligne présente **d'un seul côté** n'est pas un arbitrage, c'est une insertion.
  L'oublier fait disparaître une donnée sans aucune erreur ;
- l'**ordre** du plan ne doit pas dépendre de l'ordre des lectures SQL, qui n'est garanti
  par rien. Les listes du plan sont donc triées par clé ;
- une **clé en double** rendrait la ligne gagnante dépendante de celle qui a été lue en
  dernier. C'est refusé, en nommant la clé et le côté fautif.

Le plan est **symétrique** comme la règle : appelé avec `(locales: a, distantes: b)`, il
rend en `aPousser` exactement les clés qu'il rend en `aAppliquer` appelé avec
`(locales: b, distantes: a)`. Les tests ne vérifient pas des exemples mais cette
**propriété**, sur toutes les paires d'un jeu d'états — plus deux conséquences : aucune clé
n'est à la fois poussée et appliquée, et les deux appareils finissent avec la même version.
Un quatrième vérifie l'**idempotence** : une fois le plan appliqué des deux côtés, le plan
suivant est vide. Sans cette dernière, deux appareils pourraient s'échanger la même ligne
indéfiniment.

#### L'empreinte de contenu, et pourquoi ce n'est pas la clé

Le départage à date égale a besoin d'une empreinte du **contenu**. L'écriture la plus
tentante est d'utiliser la **clé** : elle est stable, disponible, et « suffit » en
apparence. Elle est fausse — deux contenus différents d'une même ligne partagent leur clé,
donc deux modifications simultanées seraient déclarées identiques et **cesseraient de
circuler**. Le banc de falsification remplace précisément l'empreinte de contenu par la clé,
et c'est un cas qu'il détecte.

`app/lib/models/empreinte.dart` produit cette empreinte. Trois propriétés la rendent
utilisable :

- **non ambiguë par construction** : chaque champ est précédé de sa longueur
  (`<n>:<valeur>`), et chaque valeur porte une étiquette de type. Sans les longueurs,
  `{'a': 'bc'}` et `{'ab': 'c'}` rendraient la même empreinte — deux lignes différentes
  déclarées identiques ;
- **insensible à l'ordre des clés**, mais sensible à l'ordre des **listes** : l'ordre
  d'insertion d'une `Map` n'est pas une information, celui d'une liste en est une ;
- **les nombres sont normalisés** : `1` et `1.0` rendent la même chose. Le cas est réel —
  la même valeur lue depuis SQLite (`REAL`) et depuis JSON peut arriver entière ou
  flottante, et les séparer ferait passer une ligne inchangée pour modifiée, que la
  synchronisation pousserait sans fin.

Elle **refuse** un type qu'elle ne sait pas représenter, au lieu de retomber sur
`toString()`. Le `toString()` par défaut d'un objet contient son adresse mémoire :
l'empreinte changerait d'une exécution à l'autre, et la modification fantôme serait
attribuée à l'utilisateur.

#### Pourquoi pas de hachage

Un hachage bornerait la taille, au prix d'une dépendance (`crypto`) pour un besoin qui tient
en quelques lignes, et il rendrait l'empreinte **opaque** : devant deux empreintes
différentes, on ne saurait pas dire ce qui diffère. La forme canonique se lit, se compare et
se journalise. Le projet évite déjà les dépendances qui ne gagnent pas leur place.

#### Ce que le plan ne fait pas

Il ne lit ni le réseau, ni la base, ni l'heure. C'est ce qui permet de l'éprouver sans
serveur — et c'est délibéré : la partie qui peut se tromper en silence est tenue par des
tests avant qu'un serveur existe. Il ne **compose** pas non plus les agrégats : un repas et
ses aliments sont une seule ligne, parce que `saveMeal` réécrit les aliments en bloc et
horodate le repas dans le même geste.

### Faire converger deux appareils, et ce que cela ajoute

Le plan dit quoi faire ; le service le fait.
`app/lib/services/synchronisation_service.dart` lit chaque table, demande le plan,
applique les versions distantes gagnantes **en une transaction**, puis pousse les versions
locales gagnantes. Le transport qu'il appelle n'est qu'un contrat de trois méthodes —
l'heure du serveur, lire une table, écrire une table — si bien que l'épreuve se fait
contre un faux serveur en mémoire, sans réseau et sans compte.

Ce que cette épreuve ajoute au plan, et qu'aucun test sur une seule base ne pouvait voir :

- **deux appareils, deux bases, un serveur.** Les tests ouvrent deux bases SQLite
  distinctes et les font dialoguer. Deux appareils qui se recopient l'un l'autre ne
  prouvent rien : il faut qu'ils diffèrent, puis qu'ils convergent ;
- **l'ordre des échanges ne décide pas.** La modification la plus récente l'emporte, que
  l'appareil qui la porte soit synchronisé en premier ou en dernier ;
- **un second passage ne fait plus rien.** Après convergence, le plan est vide des deux
  côtés — c'est la seule preuve que la boucle s'arrête ;
- **rien n'est redaté.** Une ligne transporte sa date ; le service ne la remplace jamais.
  Redater ferait de chaque passage une modification, et les deux appareils se renverraient
  la même ligne sans fin ;
- **une version gagnée n'est pas écrasée.** Appliquer tout ce que le serveur envoie, au
  lieu des seules versions qu'il gagne, détruit la modification locale dans l'intervalle —
  et le rapport annoncerait zéro ligne appliquée alors qu'il en aurait écrit ;
- **une table en panne n'emporte pas les autres.** Un refus du serveur sur une table
  laisse les cinq autres converger, et le rapport nomme celle qui a échoué. Comme tout est
  idempotent, le passage suivant répare ce qui manque.

### Ce qui n'est pas prouvé

L'épreuve PGlite établit que le SQL s'exécute et que les politiques filtrent. Elle
ne dit rien des droits par défaut de Supabase, qui n'y sont pas reproduits, ni des
extensions, ni de Realtime. Un essai contre le vrai projet reste nécessaire avant
de s'y fier — la marche à suivre est dans `backend/README.md`.

La règle d'arbitrage **ne corrige pas une horloge fausse**. Un appareil avancé de trois
jours gagne pendant trois jours. Le remède est un horodatage venu du serveur, pas une
règle de plus dans le client : une garde « la date est dans le futur » ne supprimerait pas
la divergence, elle déplacerait seulement la perte sur l'appareil juste. Ce que le service
fait désormais, c'est **mesurer** l'écart entre l'horloge de l'appareil et celle du
serveur — au milieu de l'aller-retour — et le **signaler**, sans jamais l'appliquer aux
dates. Une horloge fausse est donc visible ; elle n'est pas encore corrigée.

La règle d'arbitrage est **appelée**, et la chaîne qui l'appelle est éprouvée de bout en
bout : le planificateur (`app/lib/models/synchronisation.dart`) décide ligne par ligne, la
couche locale (`app/lib/data/local/synchronisation_locale.dart`) lit et écrit les tables
réelles, et le service (`app/lib/services/synchronisation_service.dart`) fait converger
**deux appareils** contre un faux serveur en mémoire. Les deux pièges de **type** qui
auraient fait boucler la synchronisation sans fin — `boolean` contre entier, `timestamptz`
contre millisecondes — sont désormais déclarés une seule fois et confrontés aux migrations
réelles par un test qui les lit, dans les deux sens ; la conversion des horodatages est
écrite et éprouvée, et un banc vérifie qu'elle tombe bien sur chacune de ses six fautes,
y compris la plus discrète : les millisecondes tenues pour des secondes, où tout converge
encore — les deux côtés étant d'accord — mais où les dates sont fausses d'un facteur mille.
Enfin, les colonnes dont la valeur **ne quitte pas l'appareil** sont nommées une à une :
`meals.photo_path` porte un chemin absolu dans le dossier de documents du téléphone, et le
transporter effacerait la photo de l'autre appareil sans la moindre erreur. La lecture ne
l'émet plus, l'écriture la relit pour la remettre, et un banc séparé éprouve les deux
moitiés.

Le **transport** est écrit, et c'est la dernière pièce qui manquait à la chaîne : `package:http`
plutôt que le client Supabase, pour que le client soit injectable et que toute la mécanique
s'éprouve contre un faux serveur, sans réseau. Les quatre points qui restaient à écrire le
sont : le **deuxième passage** sur les repas (`meal_items.meal_id` désigne l'`uuid` que le
serveur génère lui-même — il faut insérer le repas, **relire son `uuid`**, puis rattacher les
aliments) ; l'échappement du plafond de **mille lignes** que PostgREST applique à une lecture,
par l'en-tête `Range` ; le **découpage en lots** ; et l'authentification par jeton, avec les
politiques RLS qui filtrent déjà par utilisateur. Les trois familles de conversion y sont
appliquées dans les deux sens.

Ce transport n'est pas encore **branché**. Le projet Supabase, lui, existe désormais — mais ses
tables pas encore : aucun canal privilégié n'existe sur cette machine, et la clé publique ne
peut pas exécuter de DDL. C'est l'action qui reste. Ce que les tests établissent, c'est qu'on
envoie ce qu'on croit envoyer — pas que PostgREST en fait ce qu'on croit. Un banc séparé, de
vingt-deux cas, tient ces règles : il fait tomber chacune des vingt et une fautes qu'il
fabrique, et pas la reformulation d'un commentaire.

Deux défauts réels ont été trouvés en écrivant ces tests, tous les deux silencieux, et tous les
deux invisibles à un faux serveur écrit trop gentiment : l'en-tête `Date` était cherché en
minuscules alors que les passerelles l'envoient avec sa majuscule — l'écart d'horloge
disparaissait donc **sans un mot**, puisque le service avale cet échec ; et `meals.photo_path`,
retenue sur l'appareil, **revenait** du serveur — une clé de plus dans le contenu d'un côté et
pas de l'autre, donc deux empreintes qui diffèrent à jamais, un arbitrage qui désigne un
gagnant à chaque passage, et la même ligne réécrite sans fin.

Le premier de ces deux défauts reposait sur une supposition — « l'en-tête est là même sur une
erreur ». Elle méritait d'être mesurée contre le vrai projet, avec la clé publique seule :

```text
GET  /rest/v1/        -> 401  {"message":"Invalid API key","hint":"Only the `service_role`
                               API key can be used for this endpoint."}
GET  /rest/v1/meals   -> 404  {"code":"PGRST205","message":"Could not find the table
                               'public.meals' in the schema cache"}
POST /auth/v1/token   -> 400  {"code":400,"error_code":"invalid_credentials",
                               "msg":"Invalid login credentials"}
```

La route racine de PostgREST **refuse la clé publique** : elle exige le rôle `service_role`. La
sonde d'horloge ne peut donc pas espérer un `200` — et pourtant elle fonctionne, parce qu'elle
lit l'en-tête `Date` sans exiger un code de succès. Ce qui avait été écrit comme une précaution
s'est révélé être la condition même du bon fonctionnement : un `_verifier` ajouté là aurait
transformé chaque synchronisation en « session refusée ». C'est le seul endroit du transport où
un code d'erreur est accepté, et le test qui le couvre envoie délibérément un `401`.

La troisième ligne est la mesure qui décide de la forme du client d'authentification : le
serveur répond **`400`**, pas `401`, sur des identifiants invalides — et le discriminant utile
est `error_code`, pas le code HTTP.

### Le client d'authentification

C'est la pièce que le transport annonçait sans la contenir : le transport **reçoit** un jeton, il
ne sait pas en obtenir un. `client_authentification.dart` fait cela — deux requêtes,
`grant_type=password` et `grant_type=refresh_token` — et rien d'autre.

Trois avertissements de la spécification officielle ont changé la conception, et le troisième a
été écrit puis **retiré** :

- **les erreurs sont incohérentes.** Le document le dit lui-même : « Error responses are somewhat
  inconsistent. Avoid using the `msg` and HTTP status code to identify errors. HTTP 400 and 422 are
  used interchangeably in many apps. » Le discriminant retenu est donc `error_code`, et le statut
  ne sert que de repli ;
- **`apikey` est exigé sur chaque point d'entrée**, pas seulement sur celui des jetons ;
- **un `5xx` peut servir du non-JSON**, et la spécification demande de regarder le `Content-Type`
  avant de décoder. Un contrôle explicite du type a donc été écrit — puis **retiré**. La lecture du
  corps ne lève jamais, donc le résultat était *identique* avec et sans lui : aucun test ne pouvait
  les distinguer, et une règle qu'aucune mesure ne sépare est un passif, parce qu'elle coûte une
  branche à relire et fait croire à une protection. L'avertissement est satisfait autrement, et plus
  sûrement : on ne décode que ce qui se décode, une panne qui n'annonce rien reste une panne
  réessayable, et le banc le mesure.

Deux refus qui se ressemblent ne mènent pas au même geste, et le code a deux types distincts pour
le dire : `invalid_credentials` devient « Adresse ou mot de passe incorrect », tandis qu'un jeton de
rafraîchissement mort devient « Session refusée — reconnectez-vous ». Les confondre enverrait
quelqu'un qui **est** en train de se connecter vers un écran où il est déjà.

Le même `401` est d'ailleurs lu différemment selon l'opération : sur un rafraîchissement il dit
exactement quoi faire, sur une connexion il ne dit rien de tel. C'est un cas du banc, et il tombe.

La session porte aussi **l'adresse du compte** — et ce point a d'abord été écrit dans l'autre sens.
Le raisonnement d'alors était : « elle n'est pas nécessaire à la synchronisation ». C'était vrai, et
c'était répondre à côté : la question n'est pas ce dont la synchronisation a besoin, mais ce qu'un
écran doit pouvoir dire. Une section « Compte » qui ne saurait pas *de quel compte* il s'agit ne
servirait à rien, et le seul autre identifiant disponible est un `uuid`, qui ne dit rien à personne.
La spécification ne classe pas `email` parmi les champs obligatoires de `user` : le champ est donc
**facultatif**, et une adresse absente — ou vide — se lit comme une absence. Refuser la session
entière pour une étiquette manquante priverait l'utilisateur de la synchronisation sans qu'il puisse
rien y faire.

Le banc fait tomber **23 fautes** et laisse passer une reformulation de commentaire. Un cas y a été
ajouté après coup : la rupture de connexion (`ClientException`) n'était couverte par aucun test,
donc la branche qui la traduit pouvait disparaître sans que rien ne tombe — c'est exactement ce que
le banc vérifie maintenant.

### La session dans le trousseau

Le jeton de rafraîchissement est ce qui permet de rouvrir une session **sans mot de passe** au
lancement suivant : c'est lui, et lui seul, qui doit survivre à la fermeture de l'application. Il va
donc dans le trousseau du système — Keychain sur iOS, Keystore sur Android — à côté de la clé
d'analyse du fournisseur, dans le seul fichier du projet qui y touche.

La session y est rangée en **une seule écriture**, sous une seule clé, encodée en JSON. Un
enregistrement en plusieurs morceaux pourrait laisser une session à moitié écrite — et une session à
moitié écrite ne se distingue pas d'une session valide tant qu'on n'a pas essayé de s'en servir. Un
cas du banc le mesure : la mutation qui écrit deux fois fait tomber le test qui compte les écritures.

Un contenu illisible se lit comme une **absence**, jamais comme une erreur. Le trousseau peut
contenir ce qu'une version précédente y a laissé, ou ce qui a été tronqué ; faire tomber
l'application au démarrage serait le pire moment pour découvrir une incompatibilité de format. La
session illisible devient donc « pas de session », donc « se reconnecter » — et le banc fabrique les
quatre formes de contenu douteux : pas du JSON, pas un objet, un champ absent, un champ de mauvais
type.

L'adresse du projet et la clé publique, elles, **ne sont pas** dans le trousseau : elles viennent de
la configuration de compilation, et la clé publique est publique par conception. Les y ranger leur
donnerait l'apparence d'un secret et ferait croire que leur fuite serait grave — alors que la
protection repose sur les politiques RLS, pas sur leur confidentialité.

**Deux règles écrites puis retirées, pour la même raison.** Le contrôle du type de contenu dans le
client d'authentification, et le contrôle d'écriture vide avant décodage ici. Dans les deux cas, le
résultat était *identique* avec et sans la règle, donc aucun test ne pouvait les distinguer.
`jsonDecode` refuse déjà le vide et les espaces ; le `catch` couvre tout ce qui n'est pas lisible,
d'un seul geste. Ce n'est pas une coquetterie : une branche qu'aucune mesure ne sépare est une
branche qu'on relira sans pouvoir savoir si elle sert encore, et qui fait croire à une protection.

L'adresse du compte est rangée **avec** les jetons, dans le même trousseau — le même endroit protégé,
et jamais la base locale. Le test de relecture s'appelle « une session rangée se relit à
l'identique » : il porte donc sur *tous* les champs, et l'adresse y a été ajoutée le jour où elle a
existé. Sans cette assertion, retirer l'adresse de l'écriture n'aurait fait tomber aucun test : la
session serait restée valide, et l'écran aurait seulement cessé de savoir de quel compte il s'agit —
après un redémarrage, c'est-à-dire au pire moment pour le comprendre. Un cas du banc mesure cela.

Le banc du trousseau fait tomber **10 fautes** et laisse passer une reformulation de commentaire. Ce
qu'il **ne peut pas** établir : que le vrai trousseau — Keychain, Keystore — se comporte comme le
faux stockage en mémoire des tests. Cela demande un appareil, et cela reste à faire.

Dans une **liste** de résultats, les aliments qui portent une portion connue sont
désormais chiffrés par portion, les autres pour 100 g : deux bases dans la même
liste. C'est la conséquence assumée de la demande initiale (« pas toujours
100 g »), et l'étiquette dit toujours sur quoi porte le chiffre — mais comparer
deux produits y demande de la lire. Revenir à une base unique pour les seules
listes reste un choix ouvert.

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
python3 tools/bancs/falsifier_fins_de_ligne.py         # 5 cas
python3 tools/bancs/falsifier_ios.py                   # 6 cas
python3 tools/bancs/falsifier_adresses.py              # 4 cas
python3 tools/bancs/falsifier_client_deepseek.py       # 2 cas — serveur (Deno)
python3 tools/bancs/falsifier_client_deepseek_dart.py  # 6 cas — application (Flutter)
python3 tools/bancs/falsifier_proxy_dart.py            # 6 cas — mode proxy (Flutter)
python3 tools/bancs/falsifier_arbitrage_dart.py        # 5 cas — règle d'arbitrage (Flutter)
python3 tools/bancs/falsifier_synchronisation_dart.py  # 7 cas — plan de synchronisation (Flutter)
python3 tools/bancs/falsifier_synchronisation_locale_dart.py  # 7 cas — lecture/écriture locales (Flutter)
python3 tools/bancs/falsifier_synchronisation_service_dart.py  # 7 cas — convergence de deux appareils (Flutter)
python3 tools/bancs/falsifier_correspondance_types_dart.py     # 10 cas — types déclarés contre les migrations (Flutter)
python3 tools/bancs/falsifier_dates_distantes_dart.py          # 7 cas — conversion des horodatages (Flutter)
python3 tools/bancs/falsifier_colonnes_locales_dart.py         # 7 cas — colonnes propres à l'appareil (Flutter)
python3 tools/bancs/falsifier_transport_supabase_dart.py       # 22 cas — le transport réel, vers Supabase (Flutter)
python3 tools/bancs/falsifier_client_authentification_dart.py  # 24 cas — le client d'authentification (Flutter)
python3 tools/bancs/falsifier_secure_store_dart.py             # 11 cas — la session dans le trousseau (Flutter)
python3 tools/bancs/falsifier_version_build.py         # 7 cas — version publiée
python3 tools/bancs/falsifier_check_workflows.py       # 19 cas — validation des flux
python3 tools/bancs/falsifier_migration_serveur.py     # 18 cas — accord des deux schémas
python3 tools/bancs/falsifier_epreuve_migrations.py    # 6 cas — épreuve PostgreSQL
```

Chaque banc passe par `tools/bancs/banc_flutter.py`, qui lit le rapport **JSON** de `flutter test` et
ne retient que les tests qui n'ont pas réussi. Deux pièges y sont fermés, et tous les deux ont
mordu : les noms des tests **réussis** figurent aussi dans la sortie, donc chercher un nom dans le
texte brut conclurait « détecté » sans qu'aucun test ne tombe ; et une mutation qui casse la
compilation rend un code de sortie non nul **sans aucun test en échec**, ce qui se lirait « non
détecté » sur une mutation jamais mesurée. Quand le total ne correspond pas, le banc refuse de
conclure — et il rapporte désormais **le message du compilateur**, sans quoi il fallait reproduire
la mutation à la main pour savoir ce qui était reproché.

Un mot sur le nombre de tests annoncé dans ce document : c'est celui que l'exécuteur **imprime**
(`540 tests`), et non le nombre de déclarations `test(` présentes dans les fichiers. Mesure faite
à cinq commits : 456 déclarations pour 462 annoncés, puis 492 pour 498, puis 518 pour 524, puis
532 pour 538, puis 534 pour 540 — l'écart est petit et constant.

Ce paragraphe attribuait cet écart aux `setUpAll`/`tearDownAll`, « que l'exécuteur compte comme des
tests ». **La mesure le contredit**, et c'est écrit ici plutôt que corrigé en silence : il y a
**10** `setUpAll(` et **0** `tearDownAll(` dans `app/test/`, alors que l'écart vaut 6. La cause
n'est donc pas établie. Compter les déclarations n'est d'ailleurs pas une base solide : le total
change selon qu'on inclut `testWidgets(` — 481 `test(` seuls, 534 avec `testWidgets(` — et un
`test(` apparaît dans un commentaire. Il y en a exactement **un** — `poids_screen_test.dart`, à la
ligne du commentaire qui explique que les tests de widgets n'ont pas cette contrainte — donc un
compte brut rend 482 là où un compte en début de ligne rend 481. Ce qui compte reste inchangé : le nombre cité est
celui que l'exécuteur **imprime**, parce que c'est le seul qu'un lecteur et la CI puissent vérifier
de la même façon.

`falsifier_migration_serveur.py` couvre les deux côtés et les deux sens. Il
mutationne le schéma local (colonne ou table ajoutée sans destination), le schéma
serveur (colonne retirée, table renommée, colonne non déclarée), les politiques
(une politique privée de son `drop`), et — depuis que la correspondance est
déclarée en Dart et **lue** par le contrôle — la déclaration elle-même. Trois de
ses cas méritent d'être cités :

- **l'aveuglement historique, reproduit.** Le motif fautif qui rendait le
  validateur aveugle aux six politiques de `0001` est remis en place, et le banc
  exige que le contrôle tombe **malgré tout** — c'est le comptage brut qui l'y
  oblige ;
- **le retrait des commentaires, éprouvé dans les deux sens.** Colonne retirée avec
  le commentaire qui la nomme : le contrôle tombe. Le même état, retrait
  désactivé : il reste **vert sur un fichier fautif**, et c'est ce second temps qui
  établit que ce retrait porte quelque chose ;
- **le plancher de lecture, et ce qu'il ne doit pas faire.** Trois cas visent la
  déclaration : retirer un renommage, oublier une table entièrement serveur, et
  rendre le lecteur aveugle. Les deux premiers ont d'abord été **non détectés** —
  non parce que la faute échappait au contrôle, mais parce que les planchers de
  lecture, posés **à la valeur exacte** (14 renommages, 7 tables), se déclenchaient
  avant lui et sortaient avec un message qui ne nommait pas la colonne perdue. Un
  plancher exact se substitue au contrôle au lieu de le compléter : il a fallu lui
  donner une **marge**, assez large pour qu'une entrée retirée atteigne le contrôle
  d'accord, assez étroite pour qu'un lecteur cassé le fasse tomber. Le troisième
  cas est ce qui établit que le plancher sert encore à quelque chose ;
- **les colonnes retenues sur l'appareil.** Trois cas de plus : une exclusion qui
  nomme une colonne que le schéma local ne connaît pas, une déclaration vidée, et
  une reformulation en témoin négatif. Le contrôle refuse les deux premières et se
  tait sur la troisième. Il ne peut pas, en revanche, savoir qu'une colonne
  **devait** être retenue : c'est un jugement sur la nature de la valeur, pas un
  fait de structure. Ce jugement-là appartient au fichier de tests Dart, et c'est
  le banc suivant qui l'éprouve.

`falsifier_epreuve_migrations.py` éprouve l'épreuve PGlite. C'est le premier banc
qui n'éprouve pas un script Python : le harnais a reçu un paramètre d'interpréteur,
et ce banc cherche Node et PGlite là où l'espace de travail isolé les range — en le
disant s'il ne les trouve pas, plutôt que de conclure « non détecté » sur des cas
qu'il n'a pas mesurés. Trois de ses cas méritent d'être cités :

- **une migration non déclarée.** Le fichier existe, l'épreuve ne le connaît pas :
  elle tombe en le nommant ;
- **le même oubli, garde-fou désactivé.** L'épreuve applique alors la migration
  inconnue sans broncher et rend un **vert sur un ensemble incomplet**. C'est ce
  second temps qui établit que le garde-fou porte quelque chose ;
- **la reprise des favoris retirée de `0003`.** Rien ne casse : la colonne existe
  et vaut `NULL`. Seule la comparaison avec `created_at` peut le voir — et elle le
  voit.

`falsifier_arbitrage_dart.py` éprouve la règle d'arbitrage. Son premier cas est celui
qui compte, parce qu'il décrit l'erreur qu'on écrirait sans y penser :

- **à date égale, « je garde ma version ».** Cette écriture passe tous les autres cas et
  **ne converge pas** : chaque appareil se croit vainqueur et les deux s'échangent leurs
  versions indéfiniment. C'est le test de symétrie qui la détecte, et lui seul ;
- la suppression perdante à date égale — une ligne supprimée peut alors revenir ;
- la comparaison des dates inversée — chaque synchronisation ramène le passé ;
- une date inconnue tenue pour la plus récente — une ligne relue d'une sauvegarde
  ancienne écraserait toutes les modifications réelles ;
- et un **témoin négatif** : un commentaire reformulé ne fait rien tomber.

`falsifier_synchronisation_dart.py` éprouve le plan de synchronisation, c'est-à-dire la
couche qui appelle la règle. Il remet en place les six fautes qu'on écrirait naturellement,
et la plus instructive est celle-ci :

- **l'empreinte prise sur la clé de la ligne.** La clé est stable, disponible, et « suffit »
  en apparence. Elle déclare identiques deux contenus qui diffèrent dès que les dates sont
  égales : les modifications **cessent de circuler**, sans erreur et sans trace ;
- une ligne présente **d'un seul côté** oubliée — elle n'existe plus que sur un appareil ;
- le **plan non trié**, donc dépendant de l'ordre des lectures SQL ;
- les **côtés inversés** dans l'appel à l'arbitrage — l'appareil écrit systématiquement la
  version perdante ;
- une **clé en double acceptée** — la ligne gagnante devient celle qui a été lue en dernier ;
- et un **témoin négatif** : un commentaire reformulé ne fait rien tomber.

`falsifier_synchronisation_locale_dart.py` éprouve la couche qui **lit et écrit
réellement** les lignes dans SQLite — celle qui relie le plan au disque. Sa
première faute est la plus instructive, parce qu'elle a d'abord échappé au
contrôle :

- **une colonne oubliée dans le contenu.** `notes` n'entre plus dans le contenu
  d'un repas. Deux repas qui ne diffèrent que par leurs notes deviennent
  identiques à date égale, et la modification cesse de circuler — sans erreur.
  Le contrôle par colonne devait le voir, et ne le voyait pas : il itérait sur
  les clés **présentes**, donc la colonne absente lui échappait, et écrire dans
  une clé absente *ajoutait* une entrée au contenu — l'empreinte changeait, le
  contrôle passait, pour la mauvaise raison. Il vérifie maintenant que la colonne
  est là **puis** que la changer change l'empreinte. C'est le banc qui a révélé
  ce défaut, pas la relecture ;
- **les colonnes de service dans le contenu** — redondantes, la date étant déjà
  comparée et la suppression déjà tranchée ;
- **les aliments d'un repas non lus** — le contenu d'un repas devient aveugle à
  tout changement d'aliment à date égale ;
- **la colonne de lien répétée dans l'aliment** (`meal_id`) — une valeur dérivée
  du parent ferait dépendre l'empreinte d'une donnée qui n'appartient pas à la
  ligne ;
- **une table à pierre tombale non déclarée** — une donnée entière ne serait
  jamais synchronisée ;
- **une date absente tenue pour la plus récente** — or c'est ce que porte une
  ligne relue d'une sauvegarde ancienne : elle écraserait toutes les
  modifications réelles ;
- et un **témoin négatif** : un commentaire reformulé ne fait rien tomber.

Ce banc a aussi mis au jour un **défaut du harnais partagé** `banc_flutter.py` :
un test peut échouer autrement que par un `expect` — `result` vaut alors `error`
et non `failure`. Ne compter que `failure` faisait passer le total **sous** le
total attendu, et le banc déclarait « la mesure n'a pas pu tourner » sur une
faute pourtant attrapée, en invitant à corriger la mutation — c'est-à-dire à
retirer la faute que le contrôle venait de détecter. `error` compte désormais
comme un échec.

Deux autres défauts du même harnais ont été trouvés plus tard, tous deux dans
`banc.py`, et tous deux de la même famille : **le banc accuse le dépôt d'un
désordre qu'il a lui-même causé.**

- **Le repli de nettoyage ne repliait pas.** Quand `unlink()` échoue — un
  handle Windows encore ouvert sur un fichier que le contrôle vient de lire —,
  le harnais déplace le témoin hors de l'arbre. Il utilisait `rename`, et
  `os.rename` **échoue si la cible existe** (`FileExistsError`, WinError 183).
  Un premier reste dans `%TEMP%` suffisait donc à faire lever tous les replis
  suivants, et le témoin restait dans `tools/`. Le passage **d'après** refusait
  alors de démarrer sur « le contrôle échoue déjà avant toute mutation », en
  accusant un fichier que le banc fabrique lui-même. Mesure : deux passages
  consécutifs, le second rouge. Le remède — `replace`, qui écrase la cible — a
  été vérifié directement sur la même cible déjà présente : `rename` lève
  `WinError 183`, `replace` aboutit. Après correction, trois passages
  consécutifs sont verts et ne laissent aucun reste.
- **La mesure de l'index mesurait aussi l'arbre.** Le banc des fins de ligne
  vérifie que la campagne rend l'index tel qu'elle l'a trouvé, et lisait pour
  cela `git status --short` — qui confond l'index, que la campagne touche, et la
  copie de travail, qu'un auteur modifie **pendant** que le banc tourne. Une
  campagne où `docs/publication.md` a été édité en parallèle a rendu « index
  reconstruit : DIVERGENT » alors que l'index était intact. Le repère pris avant
  et après ne protège pas de cela : il protège d'une modification **déjà
  présente**, pas d'une modification **concurrente**. La mesure porte désormais
  sur `git diff --cached`, qui ne voit que l'index ; la copie de travail est
  **observée** et signalée, sans verdict. Vérifié par sonde : en désactivant la
  reconstruction de l'index, le banc rend bien `DIVERGENT`, avec la ligne
  exacte.

La leçon commune vaut d'être écrite : **un banc mesure le dépôt, donc il ne faut
pas modifier le dépôt pendant qu'il tourne.** Une campagne lancée en arrière-plan
pendant que l'on édite la documentation produit un rouge qui n'existe pas — et
le risque n'est pas le rouge, c'est de « corriger » ce qui n'est pas cassé.

`falsifier_synchronisation_service_dart.py` éprouve la couche qui **fait
converger deux appareils**. C'est le seul banc du dépôt dont les tests ouvrent
deux bases distinctes et les font dialoguer par un faux serveur en mémoire :
sans cela, on ne saurait pas si deux appareils convergent — on saurait seulement
qu'un appareil se recopie lui-même. Ses fautes sont celles qu'on écrirait
naturellement :

- **redater la ligne appliquée.** La ligne transporte sa date ; la refabriquer
  avec l'horloge locale fait de chaque passage une modification. Chaque appareil
  trouve alors l'autre plus récent, et les deux se renvoient la même ligne **sans
  fin**. Le défaut ne se voit ni sur un appareil seul, ni au premier échange : il
  faut deux appareils et un troisième passage ;
- **recopier le serveur au lieu d'arbitrer.** Écrire tout ce qui arrive écrase la
  version que l'appareil venait de gagner. Elle est renvoyée juste après, donc
  l'état final est juste — c'est ce qui rend la faute discrète. Ce qui est faux,
  c'est l'intervalle : une application qui s'arrête là perd la modification. Le
  rapport, lui, annonce zéro ligne appliquée alors qu'il en a écrit ;
- **laisser une table en panne emporter les autres** — le refus du serveur sur
  une table fait tomber la synchronisation entière ;
- **mesurer l'écart d'horloge après l'aller-retour** au lieu du milieu, ce qui
  compte le temps de la requête comme une avance de l'appareil ;
- **tenir un écart inconnu pour nul** — un serveur qui ne sait pas donner l'heure
  ferait afficher une horloge juste ;
- **visiter une table sans cycle de vie**, c'est-à-dire transporter des réglages
  qui ne portent ni date ni pierre tombale ;
- et un **témoin négatif** : un commentaire reformulé ne fait rien tomber.

`falsifier_correspondance_types_dart.py` éprouve la confrontation des **types**
déclarés aux migrations réelles. `check_migration_serveur.py` tient l'accord des
noms ; il ne dit rien des types, et c'est là que se cache une boucle silencieuse :
le serveur porte `eaten_at` en `timestamptz` et `is_estimate` en `boolean`, le
local les porte en entier. Sans conversion, les deux côtés ne décrivent jamais la
même chose — l'arbitrage tranche toujours dans le même sens, chaque passage
réécrit la même ligne, sans erreur et sans fin. Ses cas :

- **une date oubliée dans la déclaration** (`eaten_at`) et **un booléen oublié**
  (`meal_items.is_estimate`, arrivé par un `alter table`, pas par un
  `create table`) — la synchronisation ne convergerait jamais ;
- **une colonne déclarée datée à tort** et **une déclarée booléenne à tort** —
  l'autre sens de l'accord ;
- **le serveur change de type, la déclaration ne bouge pas.** C'est le cas qui
  compte le plus : il est le seul à prouver que le test lit réellement les
  fichiers `.sql`. Sans lui, un test qui se comparerait à lui-même serait vert
  sur tous les autres cas en ne mesurant rien ;
- **le lecteur des migrations devient aveugle** — six `create table if not
  exists` redeviennent `create table`, la lecture ne trouve plus rien, et le
  garde-fou « les migrations ont bien été lues » doit le dire. Sans ce cas, un
  lecteur aveugle rendrait tous les autres tests verts ;
- et un **témoin négatif** : un commentaire SQL reformulé ne fait rien tomber.

`falsifier_dates_distantes_dart.py` éprouve la conversion des horodatages, sur
laquelle repose toute la convergence : deux erreurs y font diverger les
empreintes sans jamais lever. Ses six fautes sont celles qu'on écrirait
naturellement — la marque `Z` qui disparaît (`toIso8601String()` sur une date
locale n'en pose pas, et le serveur lirait alors la date dans le fuseau de sa
session), une **absence tenue pour 1970** (une pierre tombale nulle et une date
nulle sont deux choses différentes : les confondre ferait d'une ligne jamais
supprimée une ligne supprimée en 1970, donc gagnante partout), la **chaîne vide
non reconnue** — PostgREST en rend une pour une colonne nulle —, une **date
cassée rendue nulle** au lieu de lever (« date inconnue » est une valeur, et une
valeur fausse qui se propage ne se signale jamais), un **type inattendu rendu
nul** par l'autre sortie, et les **millisecondes tenues pour des secondes** — où
tout converge encore, les deux côtés étant d'accord, mais les dates sont fausses
d'un facteur mille.

Ce banc prend une précaution qui mérite d'être dite : **aucun de ses cas ne
repose sur le fuseau de la machine**. La mutation évidente — remplacer `toUtc()`
par `toLocal()` — serait détectée à Paris et **invisible** sur un exécuteur en
UTC : le banc serait vert en local et rouge en intégration continue. Les
mutations retenues sont déterministes partout.

`falsifier_colonnes_locales_dart.py` éprouve la retenue des **colonnes propres à
l'appareil**, dont le premier membre est `meals.photo_path`. La valeur est un
chemin absolu dans le dossier de documents du téléphone : le transporter
n'échouerait pas — le chemin arriverait, il serait valide, l'image manquerait —
et l'écriture locale, qui remplace la ligne, effacerait la photo de l'appareil
qui reçoit. Ses six fautes se répartissent sur les deux moitiés de la décision :

- côté déclaration, **l'exclusion retirée** et **l'exclusion qui nomme une
  colonne inconnue** : dans les deux cas `photo_path` redevient une colonne
  ordinaire, sans que rien ne le dise ;
- côté lecture, **la colonne remise dans le contenu** et **la table qui n'est
  plus transmise** à la lecture — le second cas est le seul qui établit que ce
  paramètre sert à quelque chose ;
- côté écriture, **la préservation retirée** et **la relecture qui vise une autre
  ligne** : le second ferait hériter un repas inconnu localement de la photo du
  premier repas venu.

Ce banc est le seul à falsifier cette retenue, et il y a une raison mesurée à
cela : `falsifier_synchronisation_locale_dart.py` vise
`test/data/synchronisation_locale_test.dart`, dont les deux listes ont été
retirées de `photo_path` **par décision**. Sa couverture de cette exclusion est
donc nulle, et une mutation qui la retirerait ne ferait tomber aucun de ses
tests. Une mutation qui ne peut pas être détectée n'a rien à faire dans un banc —
le fichier de tests de cette famille a donc été **séparé**, précisément pour
qu'un banc puisse l'épingler. La mesure qui l'a imposé : ce fichier portait
exactement 21 tests, le compte épinglé par le banc voisin, et y ajouter les cinq
cas écrits d'abord aurait fait échouer ce banc — qui aurait alors eu l'air
d'accuser le dépôt.

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
