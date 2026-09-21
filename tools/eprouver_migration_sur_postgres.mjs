/**
 * Eprouve les migrations Supabase sur un vrai PostgreSQL, sans Docker.
 *
 * ## Pourquoi
 *
 * `tools/check_migration_serveur.py` lit du texte : il etablit que les deux
 * schemas s'accordent, pas que le SQL s'execute. Une colonne mal nommee, un
 * `references` vers une table absente, une parenthese en trop : tout cela passe
 * un controle de forme et echoue sur la vraie base.
 *
 * `@electric-sql/pglite` est un PostgreSQL complet compile en WebAssembly, qui
 * tourne dans Node. Pas de Docker, pas de service. Il execute du vrai SQL :
 * roles, `GRANT`, `enable row level security`, politiques, transactions.
 *
 * ## Ce que ce script etablit
 *
 *   1. **toutes** les migrations du dossier s'appliquent, dans l'ordre, et
 *      **toutes** se rejouent — appliquees deux fois, sans erreur ;
 *   2. une migration ecrite mais absente de `MIGRATIONS_ATTENDUES` fait
 *      **echouer** l'epreuve, avec le nom du fichier oublie. Sans cela, une
 *      migration neuve serait silencieusement non eprouvee ;
 *   3. les trois tables ajoutees filtrent par utilisateur ;
 *   4. elles refusent une ecriture au nom d'un autre ;
 *   5. une revendication absente **refuse** au lieu de lever ;
 *   6. `0003` s'applique sur une base **qui porte deja des donnees**, et
 *      `favorites.updated_at` y est rempli depuis `created_at` — et non depuis
 *      `now()`, ce que rien d'autre ne distinguerait.
 *
 * ## Ce qu'il n'etablit pas
 *
 * `auth.users`, `auth.uid()` et les droits par defaut de Supabase n'existent pas
 * dans PGlite : ils sont remplaces par une doublure, ecrite plus bas. On eprouve
 * donc **nos** politiques, pas celles de Supabase. Les extensions, Realtime et
 * les performances ne se verifient pas ici. Un essai contre le vrai projet reste
 * necessaire avant de s'y fier.
 *
 * ## Dependance
 *
 * Le paquet n'est pas dans le depot : il vit dans l'espace de travail Node
 * isole. Lancer avec `NODE_PATH` pose sur ses `node_modules` — la marche a
 * suivre est dans `backend/README.md`.
 *
 * Usage :
 *   NODE_PATH=<espace-node>/node_modules node tools/eprouver_migration_sur_postgres.mjs
 */

import { readFileSync, readdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// `NODE_PATH` est un mecanisme de resolution **CommonJS** : un `import` de
// module ES ne le consulte pas, et echoue en ERR_MODULE_NOT_FOUND alors que le
// paquet est bien installe. Mesure faite. On passe donc par `createRequire`,
// dont la resolution le respecte.
const require = createRequire(import.meta.url);

let PGlite;
try {
  ({ PGlite } = require('@electric-sql/pglite'));
} catch (erreur) {
  console.error(
    'PGlite est introuvable. Le paquet ne vit pas dans ce depot : il est ' +
      "installe dans l'espace de travail Node isole.\n" +
      'Marche a suivre : backend/README.md, section « Epreuve des migrations ».\n' +
      `Cause : ${erreur.message}`,
  );
  process.exit(2);
}

const ICI = dirname(fileURLToPath(import.meta.url));
const MIGRATIONS = join(ICI, '..', 'backend', 'supabase', 'migrations');

/**
 * Les migrations que cette epreuve doit couvrir, **declarees a la main**.
 *
 * Elles sont lues sur le disque, pas prises dans cette liste : c'est le disque
 * qui fait foi. Cette liste existe pour l'autre moitie du controle — une
 * migration ecrite mais oubliee ici serait **silencieusement non eprouvee**, et
 * l'epreuve resterait verte en n'ayant pas regarde le fichier neuf. C'est
 * exactement le defaut que ce depot a deja rencontre ailleurs (un validateur
 * qui annoncait « Politiques : 0 » sur un fichier qui en portait six).
 *
 * Ecrire une migration sans l'ajouter ici fait donc echouer l'epreuve, avec le
 * nom du fichier oublie.
 */
const MIGRATIONS_ATTENDUES = [
  '0001_init.sql',
  '0002_portions_et_suivi.sql',
  '0003_pierres_tombales.sql',
];

const UA = '11111111-1111-1111-1111-111111111111';
const UB = '22222222-2222-2222-2222-222222222222';

const surDisque = readdirSync(MIGRATIONS)
  .filter((nom) => nom.endsWith('.sql'))
  .sort();

const resultats = [];
const noter = (nom, ok, detail) => {
  resultats.push({ nom, ok });
  console.log(`${ok ? 'OK  ' : 'ECHEC'}  ${nom}${detail ? `  ${detail}` : ''}`);
};

// Le controle d'exhaustivite, avant toute autre chose : sans lui, l'epreuve
// pourrait passer en entier sans avoir jamais ouvert la derniere migration.
const oubliees = surDisque.filter((nom) => !MIGRATIONS_ATTENDUES.includes(nom));
const fantomes = MIGRATIONS_ATTENDUES.filter((nom) => !surDisque.includes(nom));
if (oubliees.length || fantomes.length) {
  for (const nom of oubliees) {
    console.error(
      `La migration ${nom} existe mais n'est pas dans MIGRATIONS_ATTENDUES : ` +
        "elle ne serait pas eprouvee. L'ajouter a la liste.",
    );
  }
  for (const nom of fantomes) {
    console.error(
      `MIGRATIONS_ATTENDUES annonce ${nom}, qui n'existe pas sur le disque.`,
    );
  }
  process.exit(2);
}


// ---------------------------------------------------------------------------
// La doublure de Supabase
//
// Trois pieges, tous mesures ailleurs et evites ici :
//
//   - un accent grave dans un commentaire SQL ferme le gabarit JavaScript qui
//     le contient : l'erreur annoncee est « SyntaxError: Unexpected strict mode
//     reserved word », a une ligne qui ne ressemble pas au probleme. Aucun
//     accent grave dans ce qui suit ;
//   - `current_setting(nom, true)` rend une **chaine vide**, pas NULL, quand le
//     reglage n'existe pas. Or la conversion d'une chaine vide en jsonb est une
//     erreur de syntaxe : sans les deux `nullif`, une revendication absente fait
//     **lever** la politique au lieu de la faire refuser ;
//   - un schema cree par CREATE SCHEMA n'accorde rien a PUBLIC : sans les grant
//     explicites, l'appel echoue en 42501, ce qui n'est pas un refus de
//     politique et se lirait comme un resultat.
// ---------------------------------------------------------------------------

const DOUBLURE = `
  create role authenticated;
  create role anon;

  create schema auth;

  create table auth.users (
    id    uuid primary key,
    email text
  );

  create function auth.uid() returns uuid
  language sql stable
  as $$
    select nullif(
      nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub',
      ''
    )::uuid
  $$;

  grant usage on schema auth to authenticated, anon;
  grant execute on function auth.uid() to authenticated, anon;

  -- Ce que Supabase pose pour tout le monde : les tables creees ensuite dans
  -- le schema public recoivent leurs droits automatiquement. La doublure doit le
  -- reproduire, sinon on mesurerait un refus de droit en croyant mesurer une
  -- politique.
  alter default privileges in schema public
    grant all on tables to authenticated;
  grant usage on schema public to authenticated, anon;

  insert into auth.users (id, email) values
    ('${UA}', 'a@example.test'),
    ('${UB}', 'b@example.test');
`;

const db = new PGlite();

/** Applique un fichier de migration. Rend le nombre d'instructions lues. */
async function appliquer(nom, base = db) {
  const sql = readFileSync(join(MIGRATIONS, nom), 'utf8');
  await base.exec(sql);
  return sql.split('\n').length;
}

/** Joue une fonction dans une transaction annulee, sous un role et des revendications. */
async function dansTransaction(claims, travail) {
  let valeur;
  try {
    await db.transaction(async (tx) => {
      await tx.exec('set local role authenticated');
      if (claims !== null) {
        await tx.exec(`set local request.jwt.claims = '${JSON.stringify(claims)}'`);
      }
      valeur = await travail(tx);
      throw new Error('rollback-volontaire');
    });
  } catch (erreur) {
    if (erreur.message !== 'rollback-volontaire') throw erreur;
  }
  return valeur;
}

// ---------------------------------------------------------------------------

await db.exec(DOUBLURE);

// --- 1. Les migrations s'appliquent, et se rejouent ------------------------

for (const nom of surDisque) {
  try {
    const lignes = await appliquer(nom);
    noter(`${nom} s'applique`, true, `${lignes} lignes`);
  } catch (erreur) {
    noter(`${nom} s'applique`, false, erreur.message);
  }
}

for (const nom of surDisque) {
  try {
    await appliquer(nom);
    noter(`${nom} se rejoue sans erreur`, true);
  } catch (erreur) {
    noter(`${nom} se rejoue sans erreur`, false, erreur.message);
  }
}

// --- 2. Les tables attendues existent -------------------------------------

{
  const attendues = [
    'profiles',
    'meals',
    'meal_items',
    'meal_templates',
    'favorites',
    'api_usage',
    'portions',
    'weight_entries',
    'body_measurements',
  ];
  const r = await db.query(
    `select table_name from information_schema.tables
     where table_schema = 'public' order by table_name`,
  );
  const presentes = r.rows.map((ligne) => ligne.table_name);
  const manquantes = attendues.filter((nom) => !presentes.includes(nom));
  noter(
    `les ${attendues.length} tables existent`,
    manquantes.length === 0,
    manquantes.length ? `manquantes : ${manquantes.join(', ')}` : `${presentes.length} au total`,
  );
}

{
  // La colonne ajoutee par la migration de rattrapage, et celle de `profiles`.
  const r = await db.query(
    `select table_name, column_name from information_schema.columns
     where table_schema = 'public'
       and column_name in ('portion_label', 'portion_grams', 'goal_weight_kg')
     order by table_name, column_name`,
  );
  const trouvees = r.rows.map((ligne) => `${ligne.table_name}.${ligne.column_name}`);
  noter(
    'les colonnes de rattrapage existent',
    trouvees.length === 3,
    trouvees.join(', '),
  );
}

{
  // Les colonnes de `0003`. Elles sont nommees une a une : un `deleted_at`
  // ajoute a la mauvaise table satisferait un simple comptage.
  const attendues = [
    'favorites.deleted_at',
    'favorites.updated_at',
    'meal_templates.deleted_at',
    'portions.deleted_at',
  ];
  const r = await db.query(
    `select table_name || '.' || column_name as nom
       from information_schema.columns
      where table_schema = 'public'
        and column_name in ('deleted_at', 'updated_at')
        and table_name in ('favorites', 'meal_templates', 'portions')
      order by nom`,
  );
  const presentes = r.rows.map((ligne) => ligne.nom);
  const manquantes = attendues.filter((nom) => !presentes.includes(nom));
  noter(
    'les pierres tombales de 0003 existent',
    manquantes.length === 0,
    manquantes.length ? `manquantes : ${manquantes.join(', ')}` : presentes.join(', '),
  );
}

// --- 3. Les donnees de l'epreuve ------------------------------------------

await db.exec(`
  insert into public.portions (user_id, cle, label, grams) values
    ('${UA}', 'nom:gateau', 'gateau', 65),
    ('${UA}', 'nom:part', 'part', 120),
    ('${UB}', 'nom:gateau', 'gateau', 80);

  insert into public.weight_entries (user_id, client_id, measured_at, weight_kg) values
    ('${UA}', 'p1', '2026-09-01T07:00:00Z', 74.2),
    ('${UA}', 'p2', '2026-09-08T07:00:00Z', 73.6),
    ('${UB}', 'p1', '2026-09-01T07:00:00Z', 61.0);

  insert into public.body_measurements (user_id, client_id, measured_at, kind, value_cm) values
    ('${UA}', 'm1', '2026-09-01T07:00:00Z', 'taille', 84),
    ('${UA}', 'm2', '2026-09-01T07:00:00Z', 'hanches', 96),
    ('${UB}', 'm1', '2026-09-01T07:00:00Z', 'taille', 70);
`);

// --- 4. Le temoin : le proprietaire voit tout ------------------------------
//
// Sans lui, un « 0 ligne » ne distinguerait pas « la politique refuse » de
// « la table est vide ».

for (const table of ['portions', 'weight_entries', 'body_measurements']) {
  const r = await db.query(`select count(*)::int as n from public.${table}`);
  noter(
    `temoin : le proprietaire voit les 3 lignes de ${table}`,
    r.rows[0].n === 3,
    `${r.rows[0].n} ligne(s)`,
  );
}

// --- 5. Chaque table filtre par utilisateur --------------------------------

for (const table of ['portions', 'weight_entries', 'body_measurements']) {
  const compte = (claims) =>
    dansTransaction(claims, async (tx) => {
      const r = await tx.query(`select count(*)::int as n from public.${table}`);
      return r.rows[0].n;
    });

  const a = await compte({ sub: UA });
  noter(`${table} : A voit ses 2 lignes`, a === 2, `${a} ligne(s)`);

  const b = await compte({ sub: UB });
  noter(`${table} : B voit sa ligne`, b === 1, `${b} ligne(s)`);

  // Le repli ferme, et il ne doit pas lever.
  let leve = false;
  let sans = null;
  try {
    sans = await compte(null);
  } catch (erreur) {
    leve = true;
    sans = `${erreur.code ?? '?'} — ${erreur.message}`;
  }
  noter(
    `${table} : sans revendication, 0 ligne sans exception`,
    !leve && sans === 0,
    leve ? `a leve : ${sans}` : `${sans} ligne(s)`,
  );

  // La revendication presente mais nulle : un autre chemin dans la fonction.
  const nulle = await compte({ sub: null });
  noter(`${table} : revendication nulle, 0 ligne`, nulle === 0, `${nulle} ligne(s)`);
}

// --- 6. Le cote ecriture : `with check` -----------------------------------
//
// Une politique `for all` sans `with check` laisserait un utilisateur ecrire une
// ligne au nom d'un autre. C'est la moitie qu'on oublie.

{
  let refus = 'non-tente';
  try {
    await dansTransaction({ sub: UA }, async (tx) => {
      await tx.exec(
        `insert into public.weight_entries (user_id, client_id, measured_at, weight_kg)
         values ('${UB}', 'intrusion', '2026-09-10T07:00:00Z', 99)`,
      );
    });
    refus = 'accepte';
  } catch (erreur) {
    refus = `${erreur.code ?? '?'} — ${erreur.message}`;
  }
  noter(
    'A ne peut pas ecrire une pesee au nom de B',
    refus !== 'accepte',
    refus,
  );
}

{
  let verdict = 'non-tente';
  try {
    const r = await dansTransaction({ sub: UA }, async (tx) => {
      await tx.exec(
        `insert into public.weight_entries (user_id, client_id, measured_at, weight_kg)
         values ('${UA}', 'legitime', '2026-09-10T07:00:00Z', 73.1)`,
      );
      const compte = await tx.query(
        `select count(*)::int as n from public.weight_entries`,
      );
      return compte.rows[0].n;
    });
    verdict = `${r} ligne(s) vues apres ecriture`;
    noter('A peut ecrire sa propre pesee', r === 3, verdict);
  } catch (erreur) {
    noter('A peut ecrire sa propre pesee', false, `${erreur.code ?? '?'} — ${erreur.message}`);
  }
}

// --- 7. Rien n'a ete ecrit durablement ------------------------------------

for (const table of ['portions', 'weight_entries', 'body_measurements']) {
  const r = await db.query(`select count(*)::int as n from public.${table}`);
  noter(
    `rollback : ${table} est reste a 3 lignes`,
    r.rows[0].n === 3,
    `${r.rows[0].n} ligne(s)`,
  );
}

// --- 8. Le compte de politiques -------------------------------------------

{
  const r = await db.query(
    `select count(*)::int as n from pg_policies where schemaname = 'public'`,
  );
  noter(
    'les 9 politiques sont en place',
    r.rows[0].n === 9,
    `${r.rows[0].n} politique(s)`,
  );
}

// --- 9. La migration 0003 sur une base qui porte deja des donnees ----------
//
// C'est le cas reel : `0002` tourne, l'utilisateur a des favoris, et `0003`
// arrive. Le premier scenario applique les trois migrations a la suite sur une
// base **vide**, ce qui ne prouve rien sur ce point — la reprise des donnees
// n'a alors aucune ligne a reprendre, et un `update` faux, ou meme absent,
// passerait inapercu.
//
// PGlite rend une base neuve en une ligne, donc le cas se mesure.

{
  const avant = new PGlite();
  await avant.exec(DOUBLURE);
  await appliquer('0001_init.sql', avant);
  await appliquer('0002_portions_et_suivi.sql', avant);

  // Un favori et une portion anterieurs a `0003`. Le favori porte un
  // `created_at` **eloigne de l'heure courante** : c'est ce qui permet de
  // distinguer « rempli depuis `created_at` » de « rempli par `default now()` »,
  // deux resultats que rien d'autre ne separerait.
  await avant.exec(`
    insert into public.favorites (user_id, client_id, kind, label, payload, created_at)
    values ('${UA}', 'fav-ancien', 'food', 'Riz', '{"name":"Riz"}', '2026-01-02T03:04:05Z');

    insert into public.portions (user_id, cle, label, grams)
    values ('${UA}', 'nom:gateau', 'gateau', 65);
  `);

  try {
    await appliquer('0003_pierres_tombales.sql', avant);
    noter("0003 s'applique sur une base qui porte deja des donnees", true);
  } catch (erreur) {
    noter(
      "0003 s'applique sur une base qui porte deja des donnees",
      false,
      erreur.message,
    );
  }

  const favoris = await avant.query(
    `select created_at, updated_at from public.favorites where client_id = 'fav-ancien'`,
  );
  const ligne = favoris.rows[0];
  const rempliDepuisCreation =
    Boolean(ligne) &&
    ligne.updated_at !== null &&
    new Date(ligne.updated_at).getTime() === new Date(ligne.created_at).getTime();
  noter(
    'favorites.updated_at est rempli depuis created_at, pas depuis now()',
    rempliDepuisCreation,
    ligne
      ? `created_at=${new Date(ligne.created_at).toISOString()} ` +
        `updated_at=${ligne.updated_at === null ? 'NULL' : new Date(ligne.updated_at).toISOString()}`
      : 'aucune ligne',
  );

  const portions = await avant.query(
    `select grams, deleted_at from public.portions where cle = 'nom:gateau'`,
  );
  noter(
    'une portion anterieure reste vivante',
    portions.rows.length === 1 && portions.rows[0].deleted_at === null,
    portions.rows.length
      ? `grams=${portions.rows[0].grams} deleted_at=${portions.rows[0].deleted_at}`
      : 'aucune ligne',
  );

  try {
    await avant.exec(
      `update public.portions set deleted_at = now() where cle = 'nom:gateau'`,
    );
    const effacee = await avant.query(
      `select deleted_at from public.portions where cle = 'nom:gateau'`,
    );
    noter(
      "la pierre tombale d'une portion s'ecrit",
      effacee.rows[0].deleted_at !== null,
      String(effacee.rows[0].deleted_at),
    );

    // Redefinir la portion efface sa pierre tombale : c'est le geste par lequel
    // l'utilisateur revient sur sa suppression, et `writePortion` l'ecrit ainsi.
    // Le serveur doit l'accepter par la meme porte, la cle primaire etant
    // `(user_id, cle)`.
    await avant.exec(`
      insert into public.portions (user_id, cle, label, grams, deleted_at)
      values ('${UA}', 'nom:gateau', 'gateau', 70, null)
      on conflict (user_id, cle) do update
        set label = excluded.label,
            grams = excluded.grams,
            deleted_at = null;
    `);
    const revelee = await avant.query(
      `select grams, deleted_at from public.portions where cle = 'nom:gateau'`,
    );
    noter(
      'redefinir une portion efface sa pierre tombale',
      revelee.rows[0].deleted_at === null &&
        Number(revelee.rows[0].grams) === 70,
      `grams=${revelee.rows[0].grams} deleted_at=${revelee.rows[0].deleted_at}`,
    );
  } catch (erreur) {
    noter(
      "la pierre tombale d'une portion s'ecrit",
      false,
      `${erreur.code ?? '?'} — ${erreur.message}`,
    );
  }

  await avant.close();
}

// ---------------------------------------------------------------------------

const echecs = resultats.filter((r) => !r.ok);
console.log(`\n${resultats.length - echecs.length}/${resultats.length} epreuves concluantes.`);
process.exit(echecs.length === 0 ? 0 : 1);
