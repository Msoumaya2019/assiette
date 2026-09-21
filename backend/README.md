# Serveur — mode « service »

Ce dossier sert à une seule chose : **que la clé du fournisseur d'IA ne soit
jamais embarquée dans l'APK ou l'IPA**. Une clé écrite dans un binaire mobile se
retrouve en quelques minutes dans n'importe quel désassemblage.

L'application sait fonctionner sans ce dossier : en mode *personnel*, elle
demande sa propre clé à l'utilisateur et la range dans le trousseau du téléphone
(Keychain sur iOS, Keystore sur Android). Le serveur n'est nécessaire que pour
publier une application utilisable sans rien configurer.

## Ce qui s'y trouve

```
supabase/
  functions/
    analyze-meal/index.ts        photo de repas  -> aliments + poids estimés
    analyze-label/index.ts       photo d'étiquette -> valeurs pour 100 g / 100 ml
    _shared/
      deepseek.ts                client HTTP du fournisseur, mode JSON
      meal_prompt.ts             consigne système + version du prompt
      label_prompt.ts            idem, pour les étiquettes
      rate_limit.ts              limitation de débit de premier niveau
      http.ts                    en-têtes CORS et réponses JSON
  migrations/
    0001_init.sql                schéma, index, RLS et politiques
    0002_portions_et_suivi.sql   rattrapage : portions nommées, poids, mensurations
```

## Les deux fonctions

Les deux partagent le même fournisseur et le même modèle. Le modèle ne rend
**que des noms et des poids** : les valeurs nutritionnelles sont ensuite
résolues par l'application dans la table Ciqual ou Open Food Facts. Une valeur
numérique inventée par un modèle de langage serait indétectable pour
l'utilisateur, et fausse au moment précis où la précision compte.

### `analyze-meal`

| | |
|---|---|
| Entrée | `{ imageBase64, mimeType, secondImageBase64?, secondMimeType?, portionHint?, userHint? }` |
| Sortie | `{ foods: [{ name, estimatedWeightG, confidence }], overallConfidence, notes, isEstimate, promptVersion }` |
| Limite | 6 Mo par image, JPEG / PNG / WebP, 25 aliments au plus |
| Débit | 12 requêtes par minute et par adresse IP |

### `analyze-label`

| | |
|---|---|
| Entrée | `{ imageBase64, mimeType, secondImageBase64?, secondMimeType? }` |
| Sortie | valeurs pour 100 g / 100 ml, `basis`, nom, marque, `confidence` |
| Limite | identiques à `analyze-meal` |

Dans les deux cas, la réponse du modèle est **revalidée champ par champ** avant
d'être renvoyée : noms tronqués à 120 caractères, poids bornés à 5 000 g,
confiances ramenées entre 0 et 1. Le modèle n'est jamais cru sur parole.

## Secret requis

Un seul, côté serveur :

```bash
supabase secrets set DEEPSEEK_API_KEY=sk-...
```

Il n'est jamais écrit dans un fichier du dépôt. Voir `tools/check_no_secrets.py`,
exécuté à chaque poussée par le flux `CI`.

## Déploiement

```bash
supabase login
supabase link --project-ref <reference-du-projet>
supabase secrets set DEEPSEEK_API_KEY=sk-...
supabase db push                       # applique migrations/0001 puis 0002
supabase functions deploy analyze-meal --no-verify-jwt
supabase functions deploy analyze-label --no-verify-jwt
```

Les deux migrations sont **rejouables** : chaque table, colonne et index est
gardé, chaque politique précédée de son `drop`. Une exécution interrompue peut
donc être relancée sans être défaite à la main.

`--no-verify-jwt` est nécessaire tant que l'application fonctionne sans compte :
aucun jeton de session n'accompagne alors la requête. **À retirer dès que
l'authentification est active** — la limitation de débit actuelle ne repose que
sur l'adresse IP, ce qui ne suffit pas à protéger un service public.

## Branchement de l'application

`ANALYSIS_ENDPOINT` attend l'URL **de base** des fonctions, pas celle d'une
fonction en particulier : le nom de la fonction est ajouté par le code.

```bash
flutter build apk --release \
  --dart-define=APP_ENV=production \
  --dart-define=ANALYSIS_ENDPOINT=https://<projet>.supabase.co/functions/v1
```

Dès que cette valeur est renseignée, l'application démarre en mode service et
n'a plus besoin de clé personnelle. C'est ce que font les flux
`.github/workflows/android.yml` et `ios.yml`, à partir des variables de dépôt
`ANALYSIS_ENDPOINT`, `SUPABASE_URL` et `SUPABASE_ANON_KEY`.

## Base de données

### Les tables

`0001_init.sql` crée `profiles`, `meals`, `meal_items`, `meal_templates`,
`favorites` et `api_usage`. `0002_portions_et_suivi.sql` ajoute `portions`,
`weight_entries` et `body_measurements`, complète `meal_items` de huit colonnes
et `profiles` de l'objectif de poids.

Les **neuf** tables ont la sécurité au niveau des lignes activée, avec une
politique par table, `using` et `with check` : chacun ne lit et n'écrit que ses
propres lignes (`auth.uid() = user_id`).

### Le serveur était en retard, et rien ne le disait

Le schéma local est passé en version 2 le 21 septembre — portions nommées, suivi
du poids. Le serveur, lui, est resté en version 1. Il ne connaissait ni
`portions`, ni `pesees`, ni `mesures`, et `meal_items` lui manquait huit
colonnes.

Le retard n'était **visible nulle part** : les deux schémas restaient valides,
aucun test ne tombait, aucune erreur ne se déclenchait — parce que rien ne lit ce
schéma aujourd'hui. Le jour où la synchronisation aurait été branchée, tout le
suivi du poids et toutes les portions auraient été perdus **en silence**, chez
l'utilisateur, sur des données qu'il avait saisies.

`0002_portions_et_suivi.sql` comble ce retard. Et pour qu'il ne se rouvre pas,
`tools/check_migration_serveur.py` tient l'accord entre les deux schémas :

- chaque colonne locale doit avoir une **destination serveur** — les renommages
  (`poids_kg` vers `weight_kg`, `payload_json` vers `payload`) et les
  changements de table (`templates` vers `meal_templates`) sont déclarés une
  fois, dans le contrôle ;
- l'ensemble des tables locales est **clos** : en ajouter une fait échouer le
  contrôle tant qu'elle n'a pas été prise en compte ;
- l'ensemble des colonnes serveur **sans équivalent local** est clos aussi : un
  `user_id` ou un `total_carbs_g` dénormalisé sont normaux, un oubli ne l'est
  pas ;
- la table `settings` n'a **pas** d'équivalent, et c'est délibéré — son contenu
  est décomposé en colonnes de `profiles`. Le contrôle exige que cette
  décomposition soit réelle, sinon l'exception ne serait qu'un prétexte.

```bash
python3 tools/check_migration_serveur.py
python3 tools/bancs/falsifier_migration_serveur.py    # 12 cas
```

### Épreuve des migrations

Un contrôle de forme lit du texte : il établit que les deux schémas
**s'accordent**, pas que le SQL **s'exécute**. Une colonne mal nommée, un
`references` vers une table absente ou une parenthèse en trop passent une lecture
attentive et échouent sur la vraie base.

`tools/eprouver_migration_sur_postgres.mjs` exécute les deux migrations sur un
PostgreSQL complet compilé en WebAssembly (`@electric-sql/pglite`) : pas de
Docker, pas de service. Mesuré — **27 épreuves sur 27** :

- les deux migrations s'appliquent, **et se rejouent** sans erreur ;
- les neuf tables et les trois colonnes de rattrapage existent ;
- les trois tables ajoutées filtrent par utilisateur — deux lignes pour l'un,
  une pour l'autre ;
- une revendication **absente** refuse au lieu de lever, et une revendication
  **nulle** aussi : ce sont deux chemins différents dans la fonction de
  revendication ;
- un utilisateur ne peut pas écrire une ligne au nom d'un autre
  (`42501 — new row violates row-level security policy`) — c'est la moitié
  qu'on oublie, et une politique `for all` sans `with check` la laisserait
  ouverte ;
- le témoin : le propriétaire voit bien les trois lignes de chaque table, sans
  quoi un « 0 ligne » ne distinguerait pas « la politique refuse » de « la table
  est vide ».

Le paquet n'est pas vendoré dans le dépôt. En local :

```bash
NODE_PATH=<espace-node>/node_modules node tools/eprouver_migration_sur_postgres.mjs
```

Ce que cette épreuve **ne dit pas** : `auth.users`, `auth.uid()` et les droits
par défaut de Supabase n'existent pas dans PGlite. Ils sont remplacés par une
doublure écrite dans le script. On éprouve donc **nos** politiques, pas celles de
Supabase, et un essai contre le vrai projet reste nécessaire avant de s'y fier.

### Ce qui reste à savoir avant de brancher la synchronisation

Le schéma est prêt, mais trois points ne se règlent pas tout seuls :

- **Les portions n'ont pas de pierre tombale.** Le schéma local les supprime
  définitivement, et la table serveur fait de même — il n'y a donc rien à
  propager. Une portion supprimée sur un appareil reviendrait depuis un autre.
  Corriger cela demande une colonne `deleted_at` **des deux côtés**, donc une
  migration locale en version 3 ; ajouter la colonne côté serveur seule
  donnerait une colonne que le client ne remplit jamais.
- **`templates` et `favorites` non plus**, côté local. Le serveur a bien un
  `deleted_at` sur ces deux tables, mais le client ne le remplit pas : une
  suppression locale y serait définitive aussi.
- **Les préférences d'appareil ne se synchronisent pas**, volontairement : le
  thème, les rappels et le mode d'analyse restent sur le téléphone. Les
  synchroniser ferait changer le thème du téléphone de bureau parce qu'on a
  touché à celui de la cuisine.

La phase actuelle reste **locale** : tout vit dans SQLite sur le téléphone. Ce
schéma existe pour que l'ajout du compte et de la synchronisation ne demande pas
de réécrire le modèle de données.

## Limites connues

- **Limitation de débit en mémoire.** Les fonctions sont éphémères : ce compteur
  ne survit pas à un redémarrage et n'est pas partagé entre instances. Il arrête
  les boucles accidentelles, pas un attaquant déterminé. Une limite durable par
  utilisateur doit s'appuyer sur la table `api_usage`, une fois
  l'authentification en place.
- **Pas de facturation par utilisateur.** Rien ne relie aujourd'hui une
  consommation à un compte.
- **Aucune donnée de santé.** Les photos ne sont pas conservées côté serveur :
  elles sont transmises au fournisseur, analysées, puis oubliées.

## Coût

Le modèle utilisé est le moins cher du fournisseur qui accepte les images. Une
image réduite à 1 600 px représente environ un millier de jetons. Le palier
gratuit de Supabase couvre très largement l'usage d'une association ; le coût
variable se limite donc aux appels au modèle.
