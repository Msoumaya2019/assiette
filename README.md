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
| **Poids** | Suivi personnel : courbe de poids, objectif, mensurations — ouvert depuis l'accueil |
| **Réglages** | Mode d'analyse, objectifs, thème clair/sombre, rappels, sauvegarde et restauration, effacement des données |

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

### Portions nommées : « pour 1 gâteau » au lieu de « pour 100 g »

Un aliment se lit souvent par unité, pas au gramme. L'application permet donc de
déclarer, **pour un aliment donné**, ce que vaut une unité chez soi :

```
1 gâteau = 65 g        →  l'écran affiche « pour 1 gâteau (65 g) »
                       →  les valeurs affichées deviennent celles d'un gâteau
                       →  les boutons + et − avancent d'un gâteau
```

Ce que cela **ne** change pas, et c'est délibéré : le stockage reste au gramme et
au pour-100 g. La portion n'est qu'une **unité d'affichage** appliquée par-dessus.
Corriger « 1 gâteau = 65 g » en « 1 gâteau = 70 g » ne touche donc aucune valeur
déjà enregistrée, et aucun arrondi ne s'accumule.

La portion est retenue **par aliment** et reproposée automatiquement lors des
recherches, des scans, des favoris et des lectures d'étiquette. Quand la source
annonce déjà une portion exploitable (`2 biscuits (25 g)`), elle est reprise — et
le nombre de biscuits en est **déduit** (12,5 g chacun), jamais supposé. Une
mention ambiguë (`une part`, `125 g`) n'est pas interprétée : l'application
préfère ne rien proposer plutôt que d'inventer un poids.

Un aliment non reconnu reste à zéro : la portion change l'unité de lecture, jamais
la valeur nutritionnelle.

Un piège, corrigé depuis. L'étiquette et le nombre étaient produits par **deux
fonctions séparées**, et rien ne les obligeait à parler de la même unité : la fiche
produit, les résultats de recherche et les favoris annonçaient donc « pour 1 pot
(125 g) » sous le chiffre des 100 g — soit 12 g annoncés pour un pot qui en
contient 15. Les deux viennent maintenant du **même appel**
(`apercuDePortion()`), qui rend les valeurs et leur unité ensemble : l'étiquette ne
peut plus désigner une autre unité que celle des valeurs. Les binaires publiés
`v0.1.3` et `v0.1.4` portent l'ancien affichage.

### Suivi du poids

Un écran dédié, ouvert depuis l'accueil, tient une **courbe de poids**, un
**objectif** et des **mensurations** (tour de taille, hanches, poitrine, bras,
cuisse, cou). L'objectif apparaît en pointillé sur la courbe.

Ce suivi est **personnel** : l'application enregistre ce que l'utilisateur saisit
et le lui rend en graphique. Elle ne propose aucune cible, ne suggère aucune
valeur, ne calcule aucun indice et ne formule aucun conseil. Aucune donnée de
poids ou de mensuration ne quitte l'appareil, sauf si l'utilisateur exporte
lui-même sa sauvegarde.

### Sauvegarde

Les réglages permettent d'**exporter** l'historique dans un fichier JSON lisible
par un humain, puis de le partager (stockage en ligne, courriel, ordinateur) ; et
de le **restaurer** ensuite, au choix :

- **Fusionner** — ajoute ce qui manque et **n'efface jamais rien** : le pire
  résultat possible est « rien n'a changé » ;
- **Remplacer** — efface d'abord les données de l'appareil, puis réinscrit le
  fichier.

Ce qui n'est **pas** dans le fichier, et pourquoi :

| Absent | Raison |
|---|---|
| Les photos | Une photo pèse quelques centaines de kilo-octets ; deux cents repas feraient un fichier inutilisable. Les chemins sont conservés, et la restauration **annonce** le nombre de photos non retrouvées au lieu de laisser des références mortes. |
| La clé du fournisseur d'analyse | Elle vit dans le trousseau du système, pas dans la base. Un fichier de sauvegarde est un fichier en clair : c'est ce qui le rend partageable sans risque. |

Un repas supprimé reste supprimé après restauration : la suppression est
conservée sous forme de *pierre tombale*, sans quoi l'historique ferait
réapparaître ce que l'utilisateur avait effacé.

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

L'unité **affichée** peut être une portion nommée (« pour 1 gâteau (65 g) »), mais
c'est une conversion d'affichage : le gramme reste la seule unité stockée. Il n'y a
donc jamais deux vérités à réconcilier, et changer une portion ne réécrit rien.

L'incertitude est propagée : chaque aliment porte un indice de confiance, et
l'application affiche une **fourchette** (`≈ 74 g — estimation 68–82 g`) dont la
largeur dépend de la confiance. En dessous de 0,65, le repas est marqué « à vérifier ».

## Structure du dépôt

```
app/                        Application Flutter (Android + iOS)
  lib/
    core/                   Configuration, thème, formatage, erreurs
    models/                 Valeurs nutritionnelles, aliments, repas, portions, suivi du poids, objectifs, réglages, arbitrage et synchronisation
    data/
      vision/               Fournisseurs d'analyse d'image + prompts
      local/                Base SQLite
      distant/              Correspondance des noms et des types avec le serveur,
                            et les colonnes dont la valeur reste sur l'appareil
      ciqual_repository.dart, openfoodfacts_repository.dart
    services/               Calcul nutritionnel, images, trousseau, notifications, sauvegarde, synchronisation
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
supabase db push                            # applique migrations/0001, 0002, 0003
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
| `ci.yml` | Analyse, tests, neuf contrôles — dont les migrations exécutées sur un vrai PostgreSQL | ubuntu |
| `android.yml` | `app-release.apk`, `app-release.aab` | ubuntu |
| `ios.yml` | IPA non signé (installable via eSign / Sideloadly) ou IPA signé | macOS |

Les fichiers produits sont téléchargeables dans la section **Artifacts** de
l'exécution. Un tag `v*` déclenche les trois flux.

Signature Android en CI — les quatre secrets sont **déjà en place** :

| Secret | Contenu |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Keystore encodé en base64 |
| `ANDROID_KEYSTORE_PASSWORD` | Mot de passe du keystore |
| `ANDROID_KEY_ALIAS` | Alias de la clé |
| `ANDROID_KEY_PASSWORD` | Mot de passe de la clé |

La clé vit **hors du dépôt**, dans `%USERPROFILE%\assiette-signature`. Elle a été
créée sans que son mot de passe apparaisse jamais sur une ligne de commande :

```bash
python tools/creer_cle_signature.py       # rejoue les fichiers dérivés, ne recrée pas la clé
python tools/publier_cle_signature.py     # dépose les quatre secrets
```

**Ce dossier doit être sauvegardé hors de cette machine.** Le Play Store identifie
une application par son nom de paquet *et* sa clé : une clé perdue oblige à
publier une nouvelle application, et les personnes qui ont installé la première ne
recevront plus de mise à jour.

Sans ces secrets, la CI produit une APK signée avec la clé de débogage et l'indique
explicitement dans le journal.

Signature iOS — secrets supplémentaires, à ajouter seulement le jour où un compte
Apple Developer existe : `IOS_CERTIFICATE_BASE64`, `IOS_CERTIFICATE_PASSWORD`,
`IOS_PROVISIONING_PROFILE_BASE64`, `KEYCHAIN_PASSWORD`.

### Publier une version

```bash
python tools/publier_une_version.py v0.1.3 --essai   # vérifie, ne publie rien
python tools/publier_une_version.py v0.1.3           # publie
```

Le script confronte le nom de chaque artefact à la version que le binaire déclare,
et **refuse de publier** si les deux divergent — le contrôle est avant la
publication, et il est bloquant. Détail dans `docs/publication.md` §9.

## Intégration continue

Avant chaque compilation, la CI exécute sept contrôles :

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
- `tools/check_migration_serveur.py` — tient l'accord entre le schéma SQLite de
  l'appareil et le schéma Supabase : chaque colonne locale doit avoir une
  destination serveur, et les deux ensembles sont clos. La correspondance des
  noms n'est pas recopiée ici : il la **lit** dans
  `app/lib/data/distant/correspondance_distant.dart`, où le transport la lira
  aussi. Une seule déclaration, un seul endroit à corriger.
- `tools/verifier_version_build.py` — éprouve la logique qui décide de la version
  publiée, laquelle ne tourne sinon que sur un tag.

Puis `dart format --set-exit-if-changed`, `flutter analyze` et `flutter test`, et,
dans un travail séparé, `tools/check_workflows.py` — qui valide la structure des
flux de travail, la présence des scripts qu'ils appellent, et le fait que
`android.yml` et `ios.yml` tirent la version du même endroit.

Un troisième travail, `migrations`, exécute **toutes** les migrations Supabase sur un
vrai PostgreSQL compilé en WebAssembly (`tools/eprouver_migration_sur_postgres.mjs`) :
sans Docker et sans service, il vérifie qu'elles s'appliquent, qu'elles se
**rejouent**, que les politiques RLS filtrent par utilisateur — y compris du côté
écriture — et qu'une migration neuve oubliée de la liste de l'épreuve fait échouer
celle-ci au lieu de n'être jamais ouverte. C'est le seul contrôle qui lit du SQL
**exécuté** plutôt que du SQL relu.

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
python tools/lancer_verifications_dart.py         # format, analyse, tests
python tools/lancer_verifications_dart.py format  # une seule étape
```

Ce lanceur rejoue exactement les trois étapes Dart de `ci.yml`, dans le même
environnement. Sous Windows, `dart` n'est pas dans le `PATH` (`bin/dart` est un
script shell que Git Bash n'exécute pas), et `flutter` réclame deux variables
dont une dont le nom contient des parenthèses — que `export` refuse. Le pourquoi
est documenté dans `docs/publication.md` §7.4. La CI, elle, exécute les trois
commandes directement sur `ubuntu-latest`.

Les contrôles et les scripts qui décident de la version publiée sont éprouvés hors
CI, sur cette machine :

```bash
python tools/verifier_version_build.py    # 11 cas sur tools/version_build.sh
python tools/check_migration_serveur.py   # accord des schémas local et serveur
python tools/lancer_bancs.py              # les dix-sept bancs de falsification
```

L'épreuve des migrations, elle, demande Node et le paquet `@electric-sql/pglite`,
qui n'est pas vendoré dans le dépôt :

```bash
NODE_PATH=<espace-node>/node_modules node tools/eprouver_migration_sur_postgres.mjs
```

Le banc qui l'éprouve, `falsifier_epreuve_migrations.py`, cherche Node et PGlite
lui-même et **s'arrête en le disant** s'il ne les trouve pas : un banc qui ne peut
pas mesurer doit le dire, pas rendre « non détecté ».

**Un banc mesure le dépôt : ne rien y modifier pendant qu'il tourne.** Une campagne
lancée en arrière-plan pendant que l'on édite un fichier suivi produit un rouge qui
n'existe pas — et le risque n'est pas le rouge, c'est de « corriger » ce qui n'est pas
cassé. Deux défauts du harnais partagé `tools/bancs/banc.py` sont nés de là, et sont
détaillés dans `docs/publication.md` : un repli de nettoyage qui utilisait `rename` là
où il faut `replace` (`os.rename` échoue si la cible existe, donc le témoin restait dans
l'arbre et le passage suivant refusait de démarrer), et une mesure d'index qui lisait
`git status` — lequel confond l'index et la copie de travail.

Un banc de falsification retire un garde-fou à la fois et vérifie que le contrôle
tombe. Un contrôle qui n'a jamais échoué ne prouve rien : il peut regarder au
mauvais endroit et compter zéro défaut tout aussi tranquillement qu'un contrôle
juste. `docs/publication.md` §8 liste les bancs.

`lancer_bancs.py` lit chaque code de sortie **directement**, sans tube : lire
`$?` après un `| tail` rend le code du tube, pas celui de la commande, ce qui a
déjà fait annoncer trois bancs verts alors que l'un d'eux avait planté. Sa liste
de bancs est **close et vérifiée dans les deux sens** : un banc écrit mais non
déclaré serait ignoré en silence, et le rapport annoncerait « tous verts » sur un
ensemble incomplet.

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
- recherche Ciqual (accents, ligatures, classement, appariement approximatif) ;
- **sauvegarde et restauration** : aller-retour sans perte de valeurs ni de
  provenance, total de glucides identique, suppression conservée après
  restauration, fusion qui n'écrase ni ne ressuscite rien, clé sensible absente du
  fichier, photo disparue retirée et annoncée, et sept refus de fichier dont
  chacun nomme sa cause ;
- **portions nommées** : pluriel et singulier français (`gâteau`/`gâteaux`, `jus`
  invariant), nombre d'unités déduit du poids et non l'inverse, poids par unité
  lu dans une étiquette (`2 biscuits (25 g)` → 12,5 g), mentions ambiguës
  refusées, portion retenue qui prime sur celle de la source ;
- **migration de schéma** : une base v1 remplie migre sans perte jusqu'au schéma
  courant, les pierres tombales restent mortes, les nouvelles tables existent et
  sont vides, et la base migrée est **structurellement identique** à une base neuve
  (colonnes et objets SQLite comparés). Une base **v2** est éprouvée séparément :
  c'est le seul chemin où le palier 2 → 3 est joué seul ;
- **suivi du poids** : une pesée par jour retenue, variation, bornes de la courbe
  élargies pour contenir l'objectif, mensurations par type, et refus des valeurs
  nulles ou négatives ;
- **règle d'arbitrage des conflits** : la version la plus récente l'emporte, une
  suppression l'emporte à date égale, l'empreinte du contenu tranche ensuite. Le
  test central n'énumère pas des cas mais vérifie une **propriété** : le verdict
  est le même quel que soit le côté depuis lequel on appelle la règle, donc deux
  appareils convergent. Aucune règle ne regarde « de quel côté je suis » — c'est
  exactement ce qui rend l'accord possible ;
- **plan de synchronisation** : ce qu'il faut envoyer et ce qu'il faut écrire,
  pour un ensemble de lignes. Le test central vérifie là encore une propriété —
  le plan est le même, en miroir, quel que soit le côté — plus l'idempotence
  (une fois le plan appliqué des deux côtés, le plan suivant est vide) et le
  refus d'une clé en double, qui rendrait la ligne gagnante dépendante de l'ordre
  des lectures. Et **l'empreinte de contenu** qui le fait tenir : non ambiguë par
  construction, insensible à l'ordre des clés, normalisant les nombres (`1` et
  `1.0` sont la même valeur), et **refusant** un type qu'elle ne sait pas
  représenter plutôt que de retomber sur un `toString()` instable. Ce socle est
  éprouvé sans serveur ; le transport vers Supabase reste à écrire ;
- **lecture et écriture locales** : la couche qui fait le pont entre ce plan et
  SQLite. Les colonnes n'y sont **pas recopiées** — elles sont lues dans le
  schéma (`PRAGMA table_info`), si bien qu'une colonne ajoutée plus tard entre
  dans le contenu d'elle-même. Le contrôle par colonne a été **renforcé après
  falsification** : il portait sur les clés présentes dans le contenu, donc une
  colonne *absente* lui échappait — exactement le défaut qu'il devait attraper.
  Il vérifie désormais la présence, **puis** la participation, pour chaque
  colonne du schéma ;
- **le service qui fait converger deux appareils** : lire, comparer, écrire,
  table par table, sur un **transport** dont le contrat tient en trois méthodes.
  Les tests ne simulent pas un appareil : ils en ouvrent **deux**, sur deux bases
  distinctes, avec un faux serveur en mémoire, et vérifient qu'ils convergent —
  modification, suppression, aliment ajouté puis retiré, et qu'un second passage
  ne fait plus rien. Trois propriétés y sont tenues par des tests dédiés : le
  service ne **redate jamais** une ligne (redater ferait de chaque passage une
  modification, et les deux appareils se renverraient la même ligne sans fin) ;
  une version que l'appareil **gagne** n'est pas écrasée par celle qu'il a
  battue ; et une table que le serveur refuse n'empêche pas les cinq autres de
  converger. L'écart d'horloge entre l'appareil et le serveur est **mesuré** —
  au milieu de l'aller-retour — et signalé, jamais appliqué aux dates. Le
  transport réel vers Supabase reste à écrire : le remplacer ne changera aucun
  de ces tests ;
- **la correspondance des noms** entre schéma local et schéma serveur, déclarée
  **une seule fois** (`app/lib/data/distant/correspondance_distant.dart`) et lue
  par le contrôle qui tient l'accord des deux schémas. Les tests tiennent ce qui
  se vérifie sans lire de fichier : le nom serveur d'une colonne renommée ou
  non, la clé qui reconnaît une ligne d'un appareil à l'autre, et le fait qu'une
  clé ne peut pas être une colonne que le serveur remplit lui-même ;
- **les deux pièges de type**, déclarés eux aussi une seule fois, et confrontés
  aux **migrations réelles** par un test qui lit les `.sql`. Il y en a **deux**,
  pas un : le serveur porte `is_estimate` en `boolean` et le local en entier,
  mais il porte aussi `eaten_at`, `created_at` et `mesure_le` en `timestamptz`
  alors que le local compte en millisecondes entières. `true` et `1` ne font pas
  la même empreinte, et une date ISO ne fait pas la même empreinte qu'un entier :
  sans conversion, l'arbitrage trancherait toujours dans le même sens et chaque
  passage réécrirait la même ligne, sans erreur et sans fin. La confrontation est
  faite **dans les deux sens** — rien de déclaré qui ne soit du bon type, et
  aucune colonne datée ou booléenne du serveur oubliée — et un garde-fou vérifie
  que les migrations ont réellement été lues, sans quoi un lecteur aveugle
  rendrait tout le reste vert ;
- **la conversion des horodatages** elle-même, dont dépend toute la convergence :
  une date devient un ISO-8601 **en UTC**, marqué d'un `Z` (sans lui, le serveur
  lirait la date dans le fuseau de sa session, et deux appareils dans deux
  fuseaux dateraient différemment la même modification) ; une date **absente
  reste absente** et ne devient jamais 1970 — une pierre tombale nulle et une
  date nulle sont deux choses différentes, et les confondre ferait d'une ligne
  jamais supprimée une ligne supprimée en 1970, donc gagnante partout ; une
  chaîne vide vaut une absence, parce que PostgREST en rend une pour une colonne
  nulle ; et une date **illisible lève** au lieu de rendre `null`, parce que
  « date inconnue » est une valeur, et qu'une valeur fausse qui se propage ne se
  signale jamais ;
- **l'interface, pilotée comme un utilisateur la pilote** — l'éditeur de quantité
  avec une portion (ce qui s'affiche, le pas des boutons, et le fait que ce qui
  est **transmis** reste des grammes), l'écran de suivi du poids de bout en bout
  (saisie → enregistrement → relecture → affichage, y compris la suppression et
  l'objectif), et le fait qu'une carte accepte un bouton plein en fin de ligne.

Ces tests d'interface ont trouvé **deux défauts qu'aucun test de modèle ne pouvait
voir** : un bouton pleine largeur placé dans l'en-tête d'une carte faisait tomber
le rendu dès la première pesée, et la liste des types de mensuration débordait sur
un téléphone de 360 points. Les deux sont corrigés, et tenus par un test dédié.

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

`tools/lancer_verifications_dart.py` et `tools/environnement_flutter.py` posent
les deux derniers réglages ; `docs/publication.md` §7.4 détaille le diagnostic. Sur
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
| Sauvegarde : export JSON et restauration (fusion ou remplacement) | Écrit, testé |
| Portions nommées (« pour 1 gâteau »), retenues par aliment | Écrit, testé |
| Suivi du poids : courbe, objectif, mensurations | Écrit, testé |
| Base locale en schéma v3 (migrations v1 → v3 et v2 → v3 éprouvées) | Écrit, testé |
| Notifications (rappels de repas, résumé du soir) | Écrit, testé |
| Compte et synchronisation | Socle éprouvé (arbitrage, plan, empreinte, lecture/écriture locales, service de convergence à deux appareils, correspondance des noms et des types, conversion des horodatages, colonnes
retenues sur l'appareil) ; transport vers Supabase à écrire |
| APK et AAB signés, IPA non signée | Produits et vérifiés — release `v0.1.5` (les `v0.1.3` et `v0.1.4` portent un affichage fautif des glucides par portion, ne pas les installer) |
| Envoi sur l'App Store / le Play Store | Non entamé — demande un compte Google Play et un compte Apple Developer |
