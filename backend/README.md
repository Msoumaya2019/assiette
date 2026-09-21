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
    0003_pierres_tombales.sql    rattrapage : suppressions propageables
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
supabase db push                       # applique migrations/0001, 0002 puis 0003
supabase functions deploy analyze-meal --no-verify-jwt
supabase functions deploy analyze-label --no-verify-jwt
```

Les trois migrations sont **rejouables** : chaque table, colonne et index est
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
et `profiles` de l'objectif de poids. `0003_pierres_tombales.sql` ajoute
`portions.deleted_at` et `favorites.updated_at`, et reprend les favoris
existants.

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

### Le contrôle a attrapé le retard suivant, tout seul

Le schéma local est ensuite passé en version 3 : `portions`, `templates` et
`favorites` ont reçu des **pierres tombales**, parce qu'une suppression
définitive ne se propage pas — effacer un modèle de repas sur un téléphone
l'aurait laissé sur les autres, et le prochain échange l'aurait ramené sur
celui-là même.

Le serveur, encore une fois, ne le savait pas. Et cette fois personne n'a eu à
s'en apercevoir :

```
Echec de l'accord entre le schema local et le schema serveur :
  - colonne locale `favorites.updated_at` sans destination : `favorites.updated_at`
    n'existe pas cote serveur — une synchronisation la perdrait en silence
  - colonne locale `portions.deleted_at` sans destination : `portions.deleted_at`
    n'existe pas cote serveur — une synchronisation la perdrait en silence
  - SERVEUR_SEUL declare `favorites.deleted_at`, qui est en fait alimentee par le
    local (ou n'existe plus)
  - SERVEUR_SEUL declare `meal_templates.deleted_at`, qui est en fait alimentee
    par le local (ou n'existe plus)
```

Quatre défauts, dans **les deux sens** : deux colonnes locales sans destination,
et deux déclarations devenues fausses. Le contrôle écrit pour fermer le premier
retard a fermé le second sans qu'on lui demande rien.

`0003_pierres_tombales.sql` les corrige. Deux remarques sur ce qu'il fait :

- `meal_templates.deleted_at` et `favorites.deleted_at` existaient **déjà**
  depuis `0001` : côté serveur, ces tables étaient prêtes. C'est le client qui ne
  remplissait pas la colonne. Le contrôle a signalé exactement cela.
- `favorites.updated_at` est **rempli depuis `created_at`**, pas laissé au
  `default now()` des autres tables. Un favori jamais modifié a bien été modifié
  pour la dernière fois quand il a été créé ; lui donner l'heure de la migration
  le ferait passer pour plus récent qu'il n'est, et il gagnerait des arbitrages
  qu'il devrait perdre. La colonne reste **nullable**, comme la colonne locale.

### Épreuve des migrations

Un contrôle de forme lit du texte : il établit que les deux schémas
**s'accordent**, pas que le SQL **s'exécute**. Une colonne mal nommée, un
`references` vers une table absente ou une parenthèse en trop passent une lecture
attentive et échouent sur la vraie base.

`tools/eprouver_migration_sur_postgres.mjs` exécute **toutes** les migrations du
dossier sur un PostgreSQL complet compilé en WebAssembly
(`@electric-sql/pglite`) : pas de Docker, pas de service. Mesuré — **35 épreuves
sur 35** :

- toutes les migrations s'appliquent, dans l'ordre, **et se rejouent** sans
  erreur ;
- les neuf tables, les trois colonnes de rattrapage et les quatre colonnes de
  `0003` existent ;
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
  est vide » ;
- `0003` s'applique sur une base **qui porte déjà des données** — c'est le cas
  réel, et le seul qui puisse observer la reprise des favoris. Sur une base
  vide, un `update` faux, ou même absent, passerait inaperçu ;
- `favorites.updated_at` y vaut bien `created_at`, et **non** `now()` : la ligne
  de reprise porte une date éloignée de l'heure courante, sans quoi les deux
  résultats seraient indistinguables.

Le script **découvre** les migrations sur le disque mais exige de les retrouver
dans une liste déclarée, `MIGRATIONS_ATTENDUES`. Une migration écrite et oubliée
là fait échouer l'épreuve en la nommant, au lieu de n'être jamais ouverte : sans
ce garde-fou, l'épreuve serait restée verte sur un ensemble incomplet — le même
défaut qu'un validateur qui annonçait « Politiques : 0 » sur un fichier qui en
portait six.

Le paquet n'est pas vendoré dans le dépôt. En local :

```bash
NODE_PATH=<espace-node>/node_modules node tools/eprouver_migration_sur_postgres.mjs
python3 tools/bancs/falsifier_epreuve_migrations.py    # 6 cas
```

Ce que cette épreuve **ne dit pas** : `auth.users`, `auth.uid()` et les droits
par défaut de Supabase n'existent pas dans PGlite. Ils sont remplacés par une
doublure écrite dans le script. On éprouve donc **nos** politiques, pas celles de
Supabase, et un essai contre le vrai projet reste nécessaire avant de s'y fier.

### Ce qui reste à savoir avant de brancher la synchronisation

Les pierres tombales sont en place des deux côtés : une suppression locale peut
désormais se propager. Trois points restent ouverts :

- **L'arbitrage n'est pas décidé.** `meals`, `pesees`, `mesures`, `templates`,
  `favorites` et `portions` portent tous un horodatage de modification, mais
  aucune règle n'existe encore pour trancher entre deux versions divergentes.
  « Le plus récent gagne » est une réponse, pas la seule — et une suppression
  doit l'emporter sur une modification, sinon la donnée revient.
- **`meal_items` n'a pas de pierre tombale**, et c'est délibéré : ses lignes sont
  réécrites en bloc à chaque enregistrement, donc leur cycle de vie est celui de
  leur repas. Une suppression du repas les emporte des deux côtés. Il faudra que
  la synchronisation respecte cette règle, et non qu'elle traite `meal_items`
  comme une table autonome.
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
