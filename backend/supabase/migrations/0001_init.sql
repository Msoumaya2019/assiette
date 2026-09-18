-- ---------------------------------------------------------------------------
-- Schema Supabase — synchronisation, compte et quota d'API
--
-- L'application fonctionne d'abord en local (SQLite). Ce schema n'est utile
-- qu'a partir du moment ou l'utilisateur active la synchronisation.
-- Chaque table est protegee par RLS : un utilisateur ne voit que ses lignes.
-- ---------------------------------------------------------------------------

-- Profil applicatif, cree automatiquement a l'inscription.
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  locale text not null default 'fr',
  unit_system text not null default 'metric' check (unit_system in ('metric', 'imperial')),
  theme_mode text not null default 'system' check (theme_mode in ('system', 'light', 'dark')),
  goal_carbs_g numeric,
  goal_kcal numeric,
  goal_protein_g numeric,
  goal_fat_g numeric,
  goal_fiber_g numeric,
  onboarding_done boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Repas enregistres.
create table if not exists public.meals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  client_id text not null,
  name text not null default 'Repas',
  eaten_at timestamptz not null default now(),
  source text not null default 'photo' check (source in ('photo', 'search', 'barcode', 'label', 'manual', 'template')),
  notes text,
  photo_path text,
  -- Valeurs agregees, denormalisees pour accelerer le tableau de bord.
  total_kcal numeric not null default 0,
  total_carbs_g numeric not null default 0,
  total_sugars_g numeric not null default 0,
  total_protein_g numeric not null default 0,
  total_fat_g numeric not null default 0,
  total_fiber_g numeric not null default 0,
  total_salt_g numeric not null default 0,
  is_estimate boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, client_id)
);

create index if not exists meals_user_eaten_at_idx on public.meals (user_id, eaten_at desc);

-- Aliments d'un repas, avec leurs valeurs pour 100 g (jamais les totaux seuls,
-- afin que la modification de portion reste recalculable a tout moment).
create table if not exists public.meal_items (
  id uuid primary key default gen_random_uuid(),
  meal_id uuid not null references public.meals (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  client_id text not null,
  name text not null,
  quantity_g numeric not null check (quantity_g >= 0),
  kcal_100g numeric not null default 0,
  carbs_100g numeric not null default 0,
  sugars_100g numeric not null default 0,
  protein_100g numeric not null default 0,
  fat_100g numeric not null default 0,
  fiber_100g numeric not null default 0,
  salt_100g numeric not null default 0,
  source text not null default 'manual' check (source in ('ciqual', 'openfoodfacts', 'label', 'manual', 'ai')),
  source_ref text,
  confidence numeric,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, client_id)
);

create index if not exists meal_items_meal_idx on public.meal_items (meal_id);

-- Repas personnalises reutilisables ("Mon petit-dejeuner").
create table if not exists public.meal_templates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  client_id text not null,
  name text not null,
  items jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, client_id)
);

-- Favoris : aliment Ciqual, produit Open Food Facts ou repas personnalise.
create table if not exists public.favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  client_id text not null,
  kind text not null check (kind in ('food', 'product', 'template')),
  label text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, client_id)
);

-- Compteur d'usage : sert a plafonner les appels a l'IA par utilisateur.
create table if not exists public.api_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null default current_date,
  feature text not null,
  call_count integer not null default 0,
  primary key (user_id, day, feature)
);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.meals enable row level security;
alter table public.meal_items enable row level security;
alter table public.meal_templates enable row level security;
alter table public.favorites enable row level security;
alter table public.api_usage enable row level security;

drop policy if exists "profiles_self" on public.profiles;
create policy "profiles_self" on public.profiles
  for all using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "meals_owner" on public.meals;
create policy "meals_owner" on public.meals
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "meal_items_owner" on public.meal_items;
create policy "meal_items_owner" on public.meal_items
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "meal_templates_owner" on public.meal_templates;
create policy "meal_templates_owner" on public.meal_templates
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "favorites_owner" on public.favorites;
create policy "favorites_owner" on public.favorites
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "api_usage_owner" on public.api_usage;
create policy "api_usage_owner" on public.api_usage
  for select using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Creation automatique du profil a l'inscription
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', null))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Incrementation atomique du compteur d'usage (appelee par les Edge Functions)
-- ---------------------------------------------------------------------------

create or replace function public.increment_usage(p_user uuid, p_feature text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  new_count integer;
begin
  insert into public.api_usage (user_id, day, feature, call_count)
  values (p_user, current_date, p_feature, 1)
  on conflict (user_id, day, feature)
  do update set call_count = public.api_usage.call_count + 1
  returning call_count into new_count;
  return new_count;
end;
$$;
