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
supabase db push                       # applique migrations/0001_init.sql
supabase functions deploy analyze-meal --no-verify-jwt
supabase functions deploy analyze-label --no-verify-jwt
```

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

`0001_init.sql` crée `profiles`, `meals`, `meal_items`, `meal_templates`,
`favorites` et `api_usage`. Les six tables ont la sécurité au niveau des lignes
activée, avec une politique par table : chacun ne voit que ses propres lignes
(`auth.uid() = user_id`).

Ce schéma est **prêt mais non utilisé** : la phase actuelle est locale, tout vit
dans SQLite sur le téléphone. Il existe pour que l'ajout du compte et de la
synchronisation ne demande pas de réécrire le modèle de données.

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
