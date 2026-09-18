# Publication — Assiette

Ce document décrit ce qui est déjà en place, ce qui reste à faire, et à quelles
conditions actuelles publier. Les exigences des magasins changent souvent :
elles ont été vérifiées le 18 septembre 2026, aux sources citées.

---

## 1. Ce qui est déjà prêt

| Élément | État |
| --- | --- |
| Code source complet, analysé sans avertissement | prêt |
| 136 tests automatiques, tous verts | prêt |
| APK et AAB produits par `flutter build` | prêt |
| Icônes et écran de démarrage (Android et iOS) | prêt |
| Politique de confidentialité | `docs/confidentialite.md` |
| Attributions Ciqual et Open Food Facts | `app/assets/legal/ATTRIBUTION.md` |
| Clés d'API absentes du binaire (appel via serveur) | prêt |
| Flux GitHub Actions : analyse, tests, APK, AAB, iOS | écrit, **non encore exécuté** |
| Compte Google Play, compte Apple Developer | **à créer** |
| Clé du fournisseur d'analyse (DeepSeek) | **à fournir** |

---

## 2. Actions qui ne peuvent être faites que par toi

Ces étapes engagent une identité ou une carte bancaire : elles ne peuvent pas
être automatisées.

### 2.1 Autoriser l'outil en ligne de commande GitHub

**ACTION REQUISE DE TA PART**

Pourquoi : les flux de compilation continue sont écrits mais n'ont jamais
tourné. Tant qu'ils n'ont pas tourné, on ne sait pas s'ils fonctionnent, et le
dépôt public ne peut pas être créé.

Étape 1 : dans un terminal, lance `gh auth login`, choisis « GitHub.com », puis
« HTTPS », puis « Login with a web browser ». Colle le code affiché sur la page
qui s'ouvre et autorise l'accès.

Ensuite, je créerai le dépôt public, je pousserai le code et je lancerai les
trois flux jusqu'à ce qu'ils passent au vert.

### 2.2 Fournir la clé du service d'analyse

**ACTION REQUISE DE TA PART**

Pourquoi : l'analyse d'une photo par le modèle de vision coûte de l'argent et
exige une clé qui t'appartient. Cette clé ne doit jamais se trouver dans
l'application : elle se place dans le coffre de secrets du serveur.

Étape 1 : crée un compte sur `platform.deepseek.com`, ajoute un moyen de
paiement, puis crée une clé d'API et garde-la de côté. Ne me l'envoie pas dans
la conversation : nous la saisirons directement dans le coffre de secrets.

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
