# Publication — Assiette

Ce document décrit ce qui est déjà en place, ce qui reste à faire, et à quelles
conditions actuelles publier. Les exigences des magasins changent souvent :
elles ont été vérifiées le 18 septembre 2026, aux sources citées.

---

## 1. Ce qui est déjà prêt

| Élément | État |
| --- | --- |
| Code source complet, analysé sans avertissement | prêt |
| 142 tests de l'application, tous verts | prêt |
| 13 tests du serveur, tous verts | prêt |
| Dépôt public | https://github.com/Msoumaya2019/assiette |
| Flux `ci.yml` — analyse, 142 tests, 6 contrôles | **vert**, 3 exécutions |
| Flux Android — APK et AAB | **vert**, artefacts vérifiés |
| Flux iOS — IPA non signée | **vert**, artefact vérifié |
| Déclenchement par étiquette `v*` | **vert** |
| Icônes et écran de démarrage (Android et iOS) | prêt |
| Politique de confidentialité | `docs/confidentialite.md` |
| Attributions Ciqual et Open Food Facts | `app/assets/legal/ATTRIBUTION.md` |
| Clés d'API absentes du binaire (appel via serveur) | prêt |
| Signature release Android (clé d'envoi) | **à configurer** |
| Compte Google Play, compte Apple Developer | **à créer** |
| Projet Supabase (mode serveur) | **à créer** |
| Clé du fournisseur d'analyse (DeepSeek) | **fournie**, à placer |

### Artefacts vérifiés

Produits par `Android — APK et AAB` (7 min 22 s) et `iOS — build et IPA`
(8 min 4 s), puis **ouverts et contrôlés**, pas seulement lus dans le journal du
flux :

| Artefact | Taille | Vérification |
| --- | --- | --- |
| `app-release-…-debug-key.apk` | 82 227 529 octets | 531 entrées, intégrité saine, 18 bibliothèques natives, signature vérifiée (schéma v2, 1 signataire) |
| `app-release-…-debug-key.aab` | 70 368 198 octets | 549 entrées, intégrité saine, 18 bibliothèques natives |
| `Assiette-…-non-signee.ipa` | 15 841 456 octets | 133 entrées, intégrité saine, `Payload/Runner.app` complet |

Le contenu de l'IPA confirme la cible iOS relevée plus haut : `MinimumOSVersion`
vaut bien **15.5**, et l'identifiant `io.github.axox934.assiette` est identique
côté Android et côté iOS. Les deux textes de justification d'accès (appareil
photo, photothèque) sont présents.

L'APK et l'AAB portent `debug-key` dans leur nom parce qu'aucune clé de
signature release n'est encore configurée : ils sont installables, mais pas
publiables en l'état sur le Play Store.

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
encapsulés dans `tools/lancer_tests_flutter.py`, qui les pose et transmet la
cible :

```bash
python tools/lancer_tests_flutter.py                        # toute la suite
python tools/lancer_tests_flutter.py test/data/mon_test.dart
```

`ci.yml` continue d'exécuter `flutter test` sur `ubuntu-latest`, où aucun des
deux réglages n'est nécessaire. Le chemin Linux reste la référence ; le chemin
Windows sert à boucler vite pendant le développement.

### 7.5 Avertissement de dépréciation Node 20

Les flux émettent un avertissement : `actions/checkout@v4` et
`actions/upload-artifact@v4` visent Node.js 20, que GitHub force désormais sur
Node.js 24. Les actions continuent de fonctionner — GitHub les met à niveau
automatiquement. À reprendre le jour où ces versions cesseront d'être acceptées.

---

## 8. La chaîne de garde

Six contrôles tournent à chaque `push` dans `ci.yml`. Chacun lit une propriété
que **rien d'autre ne lit** : c'est ce qui justifie sa présence, et c'est aussi
pourquoi aucun ne doit être retiré sans être remplacé.

| Contrôle | Ce qu'il attrape |
| --- | --- |
| `tools/check_no_secrets.py` | un secret qui aurait été committé — le dépôt est public |
| `tools/check_prompt_sync.py` | un prompt modifié d'un côté et pas de l'autre |
| `tools/check_fins_de_ligne.py` | un blob CRLF dans l'index, ou une copie de travail hors `eol=lf` |
| `tools/check_ios.py` | 92 vérifications iOS : icônes, storyboard, `Info.plist`, cible, Podfile |
| `tools/check_adresses_du_depot.py` | une adresse GitHub du code qui désigne un autre dépôt |
| `tools/check_workflows.py` | YAML invalide, action non épinglée, `permissions` absentes, `run:` qui ne passe pas `bash -n` |

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
```

Chaque banc inclut un **témoin négatif** — un `.bat` en CRLF conforme à son
attribut n'est pas signalé, citer `flutter/flutter` reste permis. Sans lui, rien
ne prouve que le contrôle **distingue**, plutôt qu'il ne compte.

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

### Réparer

```bash
python3 tools/normaliser_fins_de_ligne.py             # mesure, ne touche à rien
python3 tools/normaliser_fins_de_ligne.py --appliquer
```

### Lancer les tests Flutter en local

```bash
python tools/lancer_tests_flutter.py                        # toute la suite
python tools/lancer_tests_flutter.py test/data/mon_test.dart
```

`tools/environnement_flutter.py` porte les deux réglages que la machine réclame,
et pourquoi (voir §7.4). Le script les applique sans passer par `env`, qui avale
la sortie dans ce bac à sable.

