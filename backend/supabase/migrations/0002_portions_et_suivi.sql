-- ---------------------------------------------------------------------------
-- Rattrapage du schema serveur sur le schema local
--
-- `0001_init.sql` decrit l'application telle qu'elle etait avant deux ajouts :
-- les portions nommees (« 1 gateau = 65 g ») et le suivi du poids. Le schema
-- local, lui, est passe en version 2 et a gagne `meal_items.portion_label`,
-- `meal_items.portion_grams`, et les tables `portions`, `pesees`, `mesures`.
--
-- Le serveur etait donc en retard. Ce retard n'etait pas visible : rien ne lit
-- ce schema aujourd'hui, et aucune erreur ne se declenche. Il aurait produit
-- une perte silencieuse le jour ou la synchronisation serait branchee — les
-- portions et tout le suivi du poids n'auraient eu aucune colonne ou atterrir.
-- C'est precisement le genre de defaut qui ne se decouvre qu'apres coup, chez
-- l'utilisateur, et sur des donnees qu'il a saisies.
--
-- Le fichier est rejouable : chaque table, colonne et index est garde, chaque
-- politique est precedee de son `drop`.
--
-- ## Ce qui n'est pas traduit ici, et pourquoi
--
-- Les noms suivent la convention de `0001` — anglais, `snake_case` — la ou le
-- local est en francais. La correspondance est declaree une fois pour toutes
-- dans `tools/bancs/banc_migration_serveur.py`, qui refuse toute colonne locale
-- sans colonne serveur correspondante. Deux consequences :
--
--   - une colonne ajoutee au schema local fait echouer ce banc tant qu'elle n'a
--     pas de destination ici : l'oubli devient une erreur, pas une devinette ;
--   - la table `settings` n'a **pas** d'equivalent, et c'est deliberé : son
--     contenu est decompose en colonnes de `profiles` (les objectifs, le
--     theme, l'onboarding). Les autres cles sont des preferences d'appareil qui
--     n'ont rien a faire sur un serveur.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. Colonnes de `meal_items` ajoutees localement depuis `0001`
--
-- Les huit manquaient. `portion_size` porte l'identifiant de la taille de
-- portion (« small », « medium », « large ») ; il est renomme par rapport au
-- local (`portion`) parce que, voisin de `portion_label` et `portion_grams`,
-- `portion` se lirait comme l'objet portion entiere.
-- ---------------------------------------------------------------------------

alter table public.meal_items
  add column if not exists starch_100g numeric not null default 0;
alter table public.meal_items
  add column if not exists sat_fat_100g numeric not null default 0;
alter table public.meal_items add column if not exists brand text;
alter table public.meal_items add column if not exists image_url text;
alter table public.meal_items add column if not exists portion_size text;
alter table public.meal_items
  add column if not exists is_estimate boolean not null default false;

-- Les deux colonnes de la portion nommee. Nullables ensemble : une portion
-- dont une seule des deux serait renseignee est ecartee a la lecture locale
-- (`Portion.depuisJson` exige les deux), donc la moitie d'une portion ne
-- signifie rien.
alter table public.meal_items add column if not exists portion_label text;
alter table public.meal_items add column if not exists portion_grams numeric;

-- ---------------------------------------------------------------------------
-- 2. Portion retenue pour un aliment, d'un repas a l'autre
--
-- La cle est celle du local : la reference de source quand elle existe
-- (« openfoodfacts:3017620422003 »), le nom normalise sinon (« nom:gateau »).
-- Elle est globale sur l'appareil ; ici elle est prefixee par `user_id`, ce qui
-- est la seule difference — deux personnes peuvent nommer leur portion
-- « gateau » sans se voir.
--
-- Pas de `deleted_at` : le schema local n'en a pas non plus, la suppression y
-- est definitive. Ajouter ici une pierre tombale que le client ne remplit pas
-- donnerait une colonne toujours nulle, donc une suppression qui ne se propage
-- jamais. C'est une limite reelle de la synchronisation des portions, et elle
-- est notee dans `backend/README.md` plutot que masquee par une colonne morte.
-- ---------------------------------------------------------------------------

create table if not exists public.portions (
  user_id    uuid not null references auth.users (id) on delete cascade,
  cle        text not null,
  label      text not null,
  -- Strictement positif : `Portion.estValide` refuse deja un poids d'unite nul
  -- ou negatif cote client, et `writePortion` n'ecrit rien dans ce cas. La
  -- borne serveur ne fait donc que redire une regle deja tenue par le client —
  -- elle ne peut pas rejeter une ecriture que le client aurait acceptee.
  grams      numeric not null check (grams > 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, cle)
);

-- ---------------------------------------------------------------------------
-- 3. Suivi du poids
--
-- Donnees de sante, et c'est ce qui dicte le reste : elles ne quittent
-- l'appareil que si l'utilisateur active la synchronisation, et la politique
-- plus bas garantit qu'elles ne sont lisibles que par lui.
--
-- `measured_at` est un `timestamptz` alors que le local stocke un entier de
-- millisecondes : c'est la convention de `0001` (`meals.eaten_at` fait deja ce
-- passage), et la conversion se fait a la frontiere de la synchronisation.
--
-- Aucune borne sur `weight_kg`. Le schema local n'en pose pas, et une
-- contrainte serveur que le client n'applique pas transformerait une saisie
-- acceptee par l'application en echec de synchronisation opaque. Le controle
-- d'un poids aberrant appartient a l'ecran, qui peut le dire a l'utilisateur.
-- ---------------------------------------------------------------------------

create table if not exists public.weight_entries (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  client_id   text not null,
  measured_at timestamptz not null,
  weight_kg   numeric not null,
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  unique (user_id, client_id)
);

create index if not exists weight_entries_user_measured_idx
  on public.weight_entries (user_id, measured_at desc);

-- ---------------------------------------------------------------------------
-- 4. Mensurations
--
-- `kind` porte les valeurs de `TypeMesure` : taille, hanches, poitrine, bras,
-- cuisse, cou. **Aucune contrainte `check` sur cette colonne**, et c'est
-- deliberé : le modele local declare qu'un type inconnu relu depuis une base
-- plus recente est *ignore* au lieu de faire echouer la lecture, pour qu'une
-- version ancienne de l'application continue de fonctionner sur des donnees
-- plus recentes. Une enumeration figee ici inverserait cette regle — le
-- serveur refuserait ce que l'application suivante ecrira, et le refus
-- arriverait au moment d'une synchronisation, pas d'une saisie.
-- ---------------------------------------------------------------------------

create table if not exists public.body_measurements (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  client_id   text not null,
  measured_at timestamptz not null,
  kind        text not null,
  value_cm    numeric not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  unique (user_id, client_id)
);

create index if not exists body_measurements_user_measured_idx
  on public.body_measurements (user_id, measured_at desc);

-- ---------------------------------------------------------------------------
-- 5. Objectif de poids
--
-- Le local le range dans `settings`, sous la cle `objectif_poids`, avec les
-- autres objectifs. Ceux-ci vivent deja dans `profiles` (`goal_carbs_g`,
-- `goal_kcal`…) : l'objectif de poids y manquait simplement parce qu'il a ete
-- ajoute apres la redaction de `0001`. Il rejoint donc ses voisins.
--
-- C'est ce qui rend l'absence de table `settings` ici legitime : son contenu
-- est decompose en colonnes, pas abandonne.
-- ---------------------------------------------------------------------------

alter table public.profiles add column if not exists goal_weight_kg numeric;

-- ---------------------------------------------------------------------------
-- 6. Row Level Security
--
-- Meme regle que pour les six tables de `0001` : une politique par table, et
-- `auth.uid() = user_id` des deux cotes — `using` pour ce qui se lit, `with
-- check` pour ce qui s'ecrit. Oublier le second laisserait un utilisateur
-- ecrire une ligne au nom d'un autre.
-- ---------------------------------------------------------------------------

alter table public.portions enable row level security;
alter table public.weight_entries enable row level security;
alter table public.body_measurements enable row level security;

drop policy if exists "portions_owner" on public.portions;
create policy "portions_owner" on public.portions
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "weight_entries_owner" on public.weight_entries;
create policy "weight_entries_owner" on public.weight_entries
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "body_measurements_owner" on public.body_measurements;
create policy "body_measurements_owner" on public.body_measurements
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
