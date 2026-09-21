import 'dart:io';

import 'package:assiette/data/local/app_database.dart';
import 'package:assiette/models/meal.dart';
import 'package:assiette/models/portion.dart';
import 'package:assiette/models/suivi_poids.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Le schema tel qu'il etait en **version 1**.
///
/// Recopie ici volontairement : c'est un fait historique, qui ne changera plus.
/// Le reconstruire a partir du code courant rendrait le test incapable de
/// detecter une migration cassee — il comparerait le code a lui-meme, et
/// passerait toujours.
const List<String> _schemaVersion1 = [
  '''
    CREATE TABLE meals (
      id TEXT PRIMARY KEY,
      eaten_at INTEGER NOT NULL,
      name TEXT NOT NULL,
      source TEXT NOT NULL,
      notes TEXT,
      photo_path TEXT,
      is_estimate INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      deleted_at INTEGER
    )
  ''',
  'CREATE INDEX idx_meals_eaten_at ON meals (eaten_at DESC)',
  '''
    CREATE TABLE meal_items (
      id TEXT PRIMARY KEY,
      meal_id TEXT NOT NULL REFERENCES meals (id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      quantity_g REAL NOT NULL,
      kcal_100g REAL NOT NULL DEFAULT 0,
      carbs_100g REAL NOT NULL DEFAULT 0,
      sugars_100g REAL NOT NULL DEFAULT 0,
      starch_100g REAL NOT NULL DEFAULT 0,
      protein_100g REAL NOT NULL DEFAULT 0,
      fat_100g REAL NOT NULL DEFAULT 0,
      sat_fat_100g REAL NOT NULL DEFAULT 0,
      fiber_100g REAL NOT NULL DEFAULT 0,
      salt_100g REAL NOT NULL DEFAULT 0,
      source TEXT NOT NULL,
      source_ref TEXT,
      brand TEXT,
      image_url TEXT,
      confidence REAL,
      portion TEXT,
      is_estimate INTEGER NOT NULL DEFAULT 0,
      sort_order INTEGER NOT NULL DEFAULT 0
    )
  ''',
  'CREATE INDEX idx_meal_items_meal ON meal_items (meal_id)',
  '''
    CREATE TABLE templates (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      items_json TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''',
  '''
    CREATE TABLE favorites (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      label TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )
  ''',
  'CREATE INDEX idx_favorites_kind ON favorites (kind)',
  '''
    CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''',
];

/// Structure d'une base : tables, colonnes et index.
///
/// Les colonnes sont comparees **en liste triee**, pas le texte des
/// `CREATE TABLE` : `ALTER TABLE ADD COLUMN` et une creation directe produisent
/// un SQL different pour un resultat identique. Comparer le texte ferait
/// echouer le test sur une difference d'ecriture, pas de structure.
Future<Map<String, Object?>> structureDe(Database db) async {
  final objets = await db.rawQuery(
    "SELECT name, type FROM sqlite_master "
    "WHERE name NOT LIKE 'sqlite_%' ORDER BY name",
  );

  final resultat = <String, Object?>{};
  for (final objet in objets) {
    final nom = objet['name'] as String;
    if (objet['type'] == 'table') {
      final colonnes = await db.rawQuery('PRAGMA table_info($nom)');
      resultat['table:$nom'] =
          colonnes.map((colonne) => colonne['name'] as String).toList()..sort();
    } else {
      resultat['${objet['type']}:$nom'] = true;
    }
  }
  return resultat;
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory repertoire;
  late String chemin;

  setUp(() async {
    repertoire = await Directory.systemTemp.createTemp('assiette-migration');
    chemin = p.join(repertoire.path, 'assiette.db');
  });

  tearDown(() async {
    try {
      if (repertoire.existsSync()) {
        await repertoire.delete(recursive: true);
      }
    } on FileSystemException {
      // Windows garde le fichier verrouille tant qu'une connexion vit. Un
      // nettoyage impossible ne doit pas masquer l'echec du test lui-meme en
      // ajoutant une seconde erreur par-dessus.
    }
  });

  /// Fabrique une base en version 1, remplie, et la referme.
  Future<void> baseEnVersion1() async {
    final db = await databaseFactoryFfi.openDatabase(
      chemin,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
          for (final ordre in _schemaVersion1) {
            await database.execute(ordre);
          }
        },
      ),
    );

    await db.insert('meals', {
      'id': 'repas-1',
      'eaten_at': DateTime(2026, 9, 10, 12).millisecondsSinceEpoch,
      'name': 'Dejeuner ancien',
      'source': 'photo',
      'notes': 'Saisi avant la mise a jour',
      'photo_path': null,
      'is_estimate': 1,
      'created_at': 1000,
      'updated_at': 2000,
      'deleted_at': null,
    });

    await db.insert('meal_items', {
      'id': 'item-1',
      'meal_id': 'repas-1',
      'name': 'Riz blanc cuit',
      'quantity_g': 150.0,
      'kcal_100g': 130.0,
      'carbs_100g': 28.0,
      'sugars_100g': 0.1,
      'starch_100g': 27.0,
      'protein_100g': 2.7,
      'fat_100g': 0.3,
      'sat_fat_100g': 0.1,
      'fiber_100g': 0.4,
      'salt_100g': 0.01,
      'source': 'ciqual',
      'source_ref': '9100',
      'brand': null,
      'image_url': null,
      'confidence': 0.8,
      'portion': 'medium',
      'is_estimate': 0,
      'sort_order': 0,
    });

    // Un repas supprime : sa pierre tombale doit survivre a la migration.
    await db.insert('meals', {
      'id': 'repas-supprime',
      'eaten_at': DateTime(2026, 9, 9, 20).millisecondsSinceEpoch,
      'name': 'Repas efface',
      'source': 'manual',
      'notes': null,
      'photo_path': null,
      'is_estimate': 0,
      'created_at': 500,
      'updated_at': 600,
      'deleted_at': 700,
    });

    await db.insert('settings', {'key': 'theme_mode', 'value': 'dark'});
    await db.insert('settings', {
      'key': 'daily_goals',
      'value':
          '{"carbsG":180.0,"kcal":null,"proteinG":null,"fatG":null,'
          '"fiberG":null}',
    });

    await db.insert('templates', {
      'id': 'modele-1',
      'name': 'Petit dejeuner',
      'items_json': '[]',
      'created_at': 10,
      'updated_at': 20,
    });

    await db.insert('favorites', {
      'id': 'favori-1',
      'kind': 'food',
      'label': 'Riz',
      'payload_json': '{"name":"Riz"}',
      'created_at': 30,
    });

    await db.close();
  }

  group('Migration de la version 1 vers la version 2', () {
    test('les donnees existantes survivent a la migration', () async {
      await baseEnVersion1();

      final base = AppDatabase(factory: databaseFactoryFfi, customPath: chemin);
      await base.open();
      addTearDown(base.close);

      final repas = await base.mealById('repas-1');
      expect(repas, isNotNull, reason: 'le repas doit avoir survecu');
      expect(repas!.name, 'Dejeuner ancien');
      expect(repas.notes, 'Saisi avant la mise a jour');
      expect(repas.items, hasLength(1));

      final item = repas.items.single;
      expect(item.food.name, 'Riz blanc cuit');
      expect(item.quantityG, 150);
      expect(item.food.per100g.carbs, 28);
      expect(item.food.per100g.salt, 0.01);
      expect(item.food.sourceRef, '9100');
      expect(item.confidence, 0.8);
      expect(item.portionSize, PortionSize.medium);

      // La colonne ajoutee est nulle pour les lignes anterieures : aucune
      // portion inventee, aucune erreur de lecture.
      expect(item.portion, isNull);
    });

    test('la pierre tombale reste une pierre tombale', () async {
      await baseEnVersion1();

      final base = AppDatabase(factory: databaseFactoryFfi, customPath: chemin);
      await base.open();
      addTearDown(base.close);

      // Un repas supprime avant la mise a jour ne doit pas ressusciter : c'est
      // le risque le plus grave d'une migration, et le plus discret.
      expect(await base.mealById('repas-supprime'), isNull);
      expect((await base.recentMeals()).map((m) => m.id), ['repas-1']);

      final enregistres = await base.mealsPourSauvegarde();
      final supprime = enregistres.firstWhere(
        (e) => e.meal.id == 'repas-supprime',
      );
      expect(supprime.estSupprime, isTrue);
      expect(supprime.deletedAt, 700);
    });

    test('reglages, modeles et favoris sont conserves', () async {
      await baseEnVersion1();

      final base = AppDatabase(factory: databaseFactoryFfi, customPath: chemin);
      await base.open();
      addTearDown(base.close);

      expect(await base.readSetting('theme_mode'), 'dark');
      expect((await base.readGoals()).carbsG, 180);
      expect((await base.templates()).single.name, 'Petit dejeuner');
      expect((await base.favorites()).single.label, 'Riz');
    });

    test('les tables nouvelles sont vides, pas absentes', () async {
      await baseEnVersion1();

      final base = AppDatabase(factory: databaseFactoryFfi, customPath: chemin);
      await base.open();
      addTearDown(base.close);

      expect(await base.pesees(), isEmpty);
      expect(await base.mesures(), isEmpty);
      expect(await base.portionsPourSauvegarde(), isEmpty);
      expect(await base.readPortion('peu-importe'), isNull);

      // Les tables existent : une lecture ne doit pas lever d'exception.
      final tables = await base.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final noms = tables.map((t) => t['name'] as String).toSet();
      expect(noms, containsAll(['portions', 'pesees', 'mesures']));
    });

    test('la base migree a exactement la structure d\'une base neuve', () async {
      await baseEnVersion1();

      final migree = AppDatabase(
        factory: databaseFactoryFfi,
        customPath: chemin,
      );
      await migree.open();
      addTearDown(migree.close);

      final neuve = AppDatabase(
        factory: databaseFactoryFfi,
        customPath: p.join(repertoire.path, 'neuve.db'),
      );
      await neuve.open();
      addTearDown(neuve.close);

      // Le controle qui compte : `_onCreate` et `_onUpgrade` doivent produire
      // la meme structure. Deux chemins ecrits a la main divergent un jour, et
      // la divergence ne se verrait que sur les appareils deja installes.
      expect(
        await structureDe(migree.db),
        await structureDe(neuve.db),
        reason: 'creation et migration doivent donner le meme schema',
      );
    });

    test('la migration ne rejoue pas sur une base deja en version 2', () async {
      await baseEnVersion1();

      final premier = AppDatabase(
        factory: databaseFactoryFfi,
        customPath: chemin,
      );
      await premier.open();
      await premier.savePesee(
        Pesee(id: 'p1', le: DateTime(2026, 9, 12), poidsKg: 70),
      );
      await premier.close();

      // Rouvrir ne doit rien rejouer : un `ALTER TABLE` rejoue leverait
      // « duplicate column name », et la base deviendrait inouvrable.
      final second = AppDatabase(
        factory: databaseFactoryFfi,
        customPath: chemin,
      );
      await second.open();
      addTearDown(second.close);

      expect((await second.pesees()).single.id, 'p1');
    });

    test('les nouvelles donnees s\'ecrivent apres migration', () async {
      await baseEnVersion1();

      final base = AppDatabase(factory: databaseFactoryFfi, customPath: chemin);
      await base.open();
      addTearDown(base.close);

      await base.writePortion(
        'ciqual:9100',
        const Portion(label: 'gateau', grams: 65),
      );
      final retenue = await base.readPortion('ciqual:9100');
      expect(retenue, isNotNull);
      expect(retenue!.grams, 65);

      await base.savePesee(
        Pesee(
          id: 'p2',
          le: DateTime(2026, 9, 11),
          poidsKg: 71.5,
          note: 'a jeun',
        ),
      );
      await base.saveMesure(
        Mesure(
          id: 'm1',
          le: DateTime(2026, 9, 11),
          type: TypeMesure.taille,
          valeurCm: 82,
        ),
      );

      expect((await base.pesees()).single.poidsKg, 71.5);
      expect((await base.mesures()).single.type, TypeMesure.taille);
    });
  });
}
