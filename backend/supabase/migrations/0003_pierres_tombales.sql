-- ---------------------------------------------------------------------------
-- 0003 — Pierres tombales la ou il en manquait
--
-- Ce que cette migration repare
-- -----------------------------
--
-- `0002` a mis le schema serveur au niveau du schema local tel qu'il etait
-- alors. Le schema local a avance d'une version, et `0003` le suit.
--
-- La version 3 du schema local a converti trois suppressions **definitives** en
-- suppressions **logiques** : `portions`, `templates` et `favorites`. La raison
-- tient en une phrase : une suppression definitive ne se propage pas.
--
-- Concretement, sans pierre tombale : effacer un modele de repas sur un
-- telephone le laisserait en place sur les autres ; le prochain echange le
-- ramenerait meme sur celui ou on venait de l'effacer. L'utilisateur efface,
-- l'application lui repond que c'est fait, et la donnee revient. C'est le pire
-- genre de defaut — il ne se voit qu'apres coup, et il donne l'impression que
-- l'application ne tient pas ce qu'elle promet.
--
-- C'est le raisonnement qui avait deja mene aux pierres tombales de `meals`,
-- `pesees` et `mesures`. Il n'avait simplement pas ete applique a ces trois-la.
--
-- `meal_templates.deleted_at` et `favorites.deleted_at` existaient **deja**
-- depuis `0001` : cote serveur, ces deux tables etaient prets. C'est le client
-- qui ne remplissait pas la colonne. Le controle `tools/check_migration_serveur.py`
-- a signale exactement cela — deux colonnes serveur declarees « sans equivalent
-- local » qui ne l'etaient plus.
--
-- Rejouable : `if not exists` sur chaque ajout, et la reprise des donnees est
-- bornee par `where updated_at is null`, donc sans effet au deuxieme passage.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. `portions.deleted_at`
--
-- La table a une cle primaire `(user_id, cle)` : retablir une portion effacee,
-- c'est reecrire la meme ligne. Une suppression logique suffit donc, et il n'y
-- a pas de ligne fantome a nettoyer — l'ecriture de la portion ecrase la pierre
-- tombale, exactement comme `writePortion` le fait cote client.
--
-- Le commentaire de `0002` annoncait l'inverse (« pas de `deleted_at` : le
-- schema local n'en a pas non plus »). Il etait juste quand il a ete ecrit, et
-- il ne l'est plus : il a ete corrige la-bas, sans toucher au DDL, qui reste
-- l'histoire de cette migration-la.
-- ---------------------------------------------------------------------------

alter table public.portions
  add column if not exists deleted_at timestamptz;

-- ---------------------------------------------------------------------------
-- 2. `favorites.updated_at`
--
-- Sans horodatage de modification, deux appareils ne peuvent pas arbitrer entre
-- deux versions d'un meme favori : le plus recent gagne, mais « recent » n'est
-- pas mesurable. `created_at` ne dit que la naissance.
--
-- La colonne est **remplie depuis `created_at`** plutot que laissee au
-- `default now()` des autres tables. Un favori jamais modifie a bien ete
-- modifie pour la derniere fois quand il a ete cree ; lui donner l'heure de la
-- migration le ferait passer pour plus recent qu'il ne l'est, et il gagnerait
-- des arbitrages qu'il devrait perdre.
--
-- La colonne reste **nullable**, et c'est deliberе : la colonne locale l'est
-- aussi (`ALTER TABLE ... ADD COLUMN updated_at INTEGER` ne peut pas poser un
-- `NOT NULL` sans valeur par defaut, et un zero vaudrait « 1970 »). Le client
-- remplit le trou depuis `created_at` a la lecture. Un `not null` ici
-- rejetterait une ecriture que le client tient pour valide — une contrainte
-- serveur que le client n'applique pas transforme une donnee acceptee en echec
-- de synchronisation opaque.
-- ---------------------------------------------------------------------------

alter table public.favorites
  add column if not exists updated_at timestamptz;

update public.favorites
   set updated_at = created_at
 where updated_at is null;

-- ---------------------------------------------------------------------------
-- 3. Politiques
--
-- Aucune n'est ajoutee, et c'est volontaire : les politiques de `0002` sont des
-- `for all using (auth.uid() = user_id) with check (auth.uid() = user_id)`.
-- Elles portent sur la **ligne**, pas sur une liste de colonnes, donc elles
-- couvrent deja `deleted_at` et `updated_at` sans qu'on y touche.
--
-- En ajouter une ici serait une politique de plus a maintenir pour un droit
-- qui existe deja.
-- ---------------------------------------------------------------------------
