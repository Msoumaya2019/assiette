import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/food.dart';
import '../../models/goals.dart';
import '../../models/meal.dart';
import '../../models/nutrition_values.dart';

/// Base de donnees locale.
///
/// Le stockage est la source de verite de l'application : elle fonctionne
/// entierement hors ligne, et la synchronisation future ne fera que repliquer
/// ces tables. Les valeurs nutritionnelles sont stockees **pour 100 g** dans
/// `meal_items`, jamais en total : modifier une portion reste donc toujours
/// recalculable sans perte de precision.
///
/// Ce qu'une ligne de `meal_items` conserve d'un aliment, et ce qu'elle ne
/// conserve pas — le choix est deliberé, il est donc ecrit ici :
///
///   - conserve : le nom, les neuf constituants pour 100 g, la provenance
///     (`source`, `source_ref`), la marque et l'image. La provenance est ce qui
///     permet a l'interface d'annoncer d'ou vient une valeur ;
///   - non conserve : le groupe d'aliments (`category`) et la portion usuelle
///     (`serving_size_g`, `serving_label`). Ces metadonnees ne servent qu'a
///     proposer une quantite au moment ou l'on ajoute un aliment, a partir de
///     la source interrogee en direct. Aucun ecran ne les relit depuis un repas
///     enregistre. Les stocker ajouterait trois colonnes pour des donnees que
///     personne ne lit.
///
/// Si un ecran venait a proposer la portion usuelle d'un aliment deja
/// enregistre, il faudrait ajouter ces colonnes et une migration.
class AppDatabase {
  AppDatabase({
    this.fileName = 'assiette.db',
    DatabaseFactory? factory,
    String? customPath,
  }) : _factory = factory ?? databaseFactory,
       _customPath = customPath;

  final String fileName;
  final DatabaseFactory _factory;
  final String? _customPath;

  Database? _db;

  /// Version du schema. A incrementer a chaque migration.
  static const int schemaVersion = 1;

  Database get db {
    final database = _db;
    if (database == null) {
      throw StateError(
        'La base de donnees n\'est pas ouverte. Appelez open() d\'abord.',
      );
    }
    return database;
  }

  bool get isOpen => _db != null;

  Future<void> open() async {
    if (_db != null) return;

    final path =
        _customPath ?? p.join(await _factory.getDatabasesPath(), fileName);

    _db = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (database) async {
          // Les cles etrangeres ne sont pas activees par defaut sur Android.
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> _onCreate(Database database, int version) async {
    final batch = database.batch();

    batch.execute('''
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
    ''');
    batch.execute('CREATE INDEX idx_meals_eaten_at ON meals (eaten_at DESC)');

    batch.execute('''
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
    ''');
    batch.execute('CREATE INDEX idx_meal_items_meal ON meal_items (meal_id)');

    batch.execute('''
      CREATE TABLE templates (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        items_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE favorites (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        label TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    batch.execute('CREATE INDEX idx_favorites_kind ON favorites (kind)');

    batch.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await batch.commit(noResult: true);
  }

  Future<void> _onUpgrade(Database database, int from, int to) async {
    // Aucune migration pour l'instant : la version 1 est la version initiale.
    // Les migrations suivantes s'ajouteront ici, en preservant les donnees.
  }

  // -------------------------------------------------------------------------
  // Repas
  // -------------------------------------------------------------------------

  Future<void> saveMeal(Meal meal) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      await txn.insert('meals', {
        'id': meal.id,
        'eaten_at': meal.eatenAt.millisecondsSinceEpoch,
        'name': meal.name,
        'source': meal.source.name,
        'notes': meal.notes,
        'photo_path': meal.photoPath,
        'is_estimate': meal.isEstimate ? 1 : 0,
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await _ecrireItems(txn, meal);
    });
  }

  /// Remplace les lignes d'un repas, en conservant leur ordre.
  ///
  /// Partage par `saveMeal` et `restaurerMeal` : les deux doivent ecrire
  /// **exactement** les memes colonnes. Deux copies divergeraient un jour, et
  /// la divergence ne se verrait qu'a la restauration — c'est-a-dire au moment
  /// ou l'utilisateur a deja perdu ses donnees.
  Future<void> _ecrireItems(DatabaseExecutor txn, Meal meal) async {
    // Remplacement complet des lignes : plus simple et plus sur qu'un
    // differentiel, et le volume par repas reste faible.
    await txn.delete('meal_items', where: 'meal_id = ?', whereArgs: [meal.id]);

    final batch = txn.batch();
    for (var index = 0; index < meal.items.length; index++) {
      final item = meal.items[index];
      batch.insert('meal_items', {
        'id': item.id,
        'meal_id': meal.id,
        'name': item.food.name,
        'quantity_g': item.quantityG,
        'kcal_100g': item.food.per100g.kcal,
        'carbs_100g': item.food.per100g.carbs,
        'sugars_100g': item.food.per100g.sugars,
        'starch_100g': item.food.per100g.starch,
        'protein_100g': item.food.per100g.protein,
        'fat_100g': item.food.per100g.fat,
        'sat_fat_100g': item.food.per100g.saturatedFat,
        'fiber_100g': item.food.per100g.fiber,
        'salt_100g': item.food.per100g.salt,
        'source': item.food.source.name,
        'source_ref': item.food.sourceRef,
        'brand': item.food.brand,
        'image_url': item.food.imageUrl,
        'confidence': item.confidence,
        'portion': item.portionSize?.name,
        'is_estimate': item.isEstimate ? 1 : 0,
        'sort_order': index,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<Meal?> mealById(String id) async {
    final rows = await db.query(
      'meals',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _buildMeal(rows.first);
  }

  /// Repas les plus recents d'abord.
  Future<List<Meal>> recentMeals({int limit = 100, DateTime? before}) async {
    final rows = await db.query(
      'meals',
      where: before == null
          ? 'deleted_at IS NULL'
          : 'deleted_at IS NULL AND eaten_at < ?',
      whereArgs: before == null ? null : [before.millisecondsSinceEpoch],
      orderBy: 'eaten_at DESC',
      limit: limit,
    );
    return Future.wait(rows.map(_buildMeal));
  }

  /// Tous les repas d'une periode, pour les statistiques.
  Future<List<Meal>> mealsBetween(DateTime start, DateTime end) async {
    final rows = await db.query(
      'meals',
      where: 'deleted_at IS NULL AND eaten_at >= ? AND eaten_at <= ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'eaten_at ASC',
    );
    return Future.wait(rows.map(_buildMeal));
  }

  /// Suppression logique : la ligne reste, ce qui permet de propager la
  /// suppression lors d'une future synchronisation au lieu de la perdre.
  Future<void> deleteMeal(String id) async {
    await db.update(
      'meals',
      {'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Meal> _buildMeal(Map<String, Object?> row) async {
    final id = row['id'] as String;
    final itemRows = await db.query(
      'meal_items',
      where: 'meal_id = ?',
      whereArgs: [id],
      orderBy: 'sort_order ASC',
    );

    final items = itemRows.map((item) {
      return MealItem(
        id: item['id'] as String,
        food: Food(
          name: item['name'] as String,
          per100g: NutritionValues(
            kcal: (item['kcal_100g'] as num).toDouble(),
            carbs: (item['carbs_100g'] as num).toDouble(),
            sugars: (item['sugars_100g'] as num).toDouble(),
            starch: (item['starch_100g'] as num).toDouble(),
            protein: (item['protein_100g'] as num).toDouble(),
            fat: (item['fat_100g'] as num).toDouble(),
            saturatedFat: (item['sat_fat_100g'] as num).toDouble(),
            fiber: (item['fiber_100g'] as num).toDouble(),
            salt: (item['salt_100g'] as num).toDouble(),
          ),
          source: FoodSource.fromId(item['source'] as String?),
          sourceRef: item['source_ref'] as String?,
          brand: item['brand'] as String?,
          imageUrl: item['image_url'] as String?,
        ),
        quantityG: (item['quantity_g'] as num).toDouble(),
        confidence: (item['confidence'] as num?)?.toDouble(),
        portionSize: item['portion'] == null
            ? null
            : PortionSize.fromId(item['portion'] as String?),
        isEstimate: (item['is_estimate'] as int? ?? 0) == 1,
        sortOrder: (item['sort_order'] as int?) ?? 0,
      );
    }).toList();

    return Meal(
      id: id,
      eatenAt: DateTime.fromMillisecondsSinceEpoch(row['eaten_at'] as int),
      name: row['name'] as String,
      items: items,
      source: MealSource.fromId(row['source'] as String?),
      notes: row['notes'] as String?,
      photoPath: row['photo_path'] as String?,
      isEstimate: (row['is_estimate'] as int? ?? 1) == 1,
    );
  }

  // -------------------------------------------------------------------------
  // Repas personnalises
  // -------------------------------------------------------------------------

  Future<void> saveTemplate(
    String id,
    String name,
    List<MealItem> items,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('templates', {
      'id': id,
      'name': name,
      'items_json': jsonEncode(items.map((item) => item.toJson()).toList()),
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<MealTemplate>> templates() async {
    final rows = await db.query('templates', orderBy: 'name ASC');
    return rows.map((row) {
      final raw = jsonDecode(row['items_json'] as String) as List;
      return MealTemplate(
        id: row['id'] as String,
        name: row['name'] as String,
        items: raw
            .map(
              (item) =>
                  MealItem.fromJson((item as Map).cast<String, dynamic>()),
            )
            .toList(),
      );
    }).toList();
  }

  Future<void> deleteTemplate(String id) async {
    await db.delete('templates', where: 'id = ?', whereArgs: [id]);
  }

  // -------------------------------------------------------------------------
  // Favoris
  // -------------------------------------------------------------------------

  Future<void> addFavorite(
    String id,
    String kind,
    String label,
    Map<String, dynamic> payload,
  ) async {
    await db.insert('favorites', {
      'id': id,
      'kind': kind,
      'label': label,
      'payload_json': jsonEncode(payload),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Favorite>> favorites({String? kind}) async {
    final rows = await db.query(
      'favorites',
      where: kind == null ? null : 'kind = ?',
      whereArgs: kind == null ? null : [kind],
      orderBy: 'created_at DESC',
    );
    return rows.map((row) {
      return Favorite(
        id: row['id'] as String,
        kind: row['kind'] as String,
        label: row['label'] as String,
        payload: (jsonDecode(row['payload_json'] as String) as Map)
            .cast<String, dynamic>(),
      );
    }).toList();
  }

  Future<void> deleteFavorite(String id) async {
    await db.delete('favorites', where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> isFavorite(String id) async {
    final rows = await db.query(
      'favorites',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  // -------------------------------------------------------------------------
  // Reglages
  // -------------------------------------------------------------------------

  Future<String?> readSetting(String key) async {
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> writeSetting(String key, String value) async {
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<DailyGoals> readGoals() async {
    final raw = await readSetting('daily_goals');
    if (raw == null || raw.isEmpty) return DailyGoals.none;
    try {
      return DailyGoals.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } on FormatException {
      return DailyGoals.none;
    }
  }

  Future<void> writeGoals(DailyGoals goals) =>
      writeSetting('daily_goals', jsonEncode(goals.toJson()));

  // -------------------------------------------------------------------------
  // Sauvegarde et restauration
  //
  // Les lectures ci-dessous rendent les lignes **telles qu'elles sont
  // stockees**, horodatages compris, et les ecritures les reinscrivent a
  // l'identique. `saveMeal` ne peut pas servir a restaurer : il remet
  // `created_at` et `updated_at` a maintenant et surtout `deleted_at` a nul, ce
  // qui **ressusciterait** un repas que l'utilisateur avait supprime.
  // -------------------------------------------------------------------------

  /// Toutes les lignes de `meals`, **supprimees comprises**.
  ///
  /// Une sauvegarde a besoin des pierres tombales : sans elles, une
  /// restauration sur un appareil ou le repas avait ete supprime le ferait
  /// reapparaitre, et l'utilisateur verrait revenir ce qu'il avait efface.
  Future<List<MealEnregistre>> mealsPourSauvegarde() async {
    final rows = await db.query('meals', orderBy: 'eaten_at ASC');
    final resultat = <MealEnregistre>[];
    for (final row in rows) {
      resultat.add(
        MealEnregistre(
          meal: await _buildMeal(row),
          createdAt: row['created_at'] as int,
          updatedAt: row['updated_at'] as int,
          deletedAt: row['deleted_at'] as int?,
        ),
      );
    }
    return resultat;
  }

  Future<List<TemplateEnregistre>> templatesPourSauvegarde() async {
    final rows = await db.query('templates', orderBy: 'name ASC');
    return rows.map((row) {
      final raw = jsonDecode(row['items_json'] as String) as List;
      return TemplateEnregistre(
        template: MealTemplate(
          id: row['id'] as String,
          name: row['name'] as String,
          items: raw
              .map(
                (item) =>
                    MealItem.fromJson((item as Map).cast<String, dynamic>()),
              )
              .toList(),
        ),
        createdAt: row['created_at'] as int,
        updatedAt: row['updated_at'] as int,
      );
    }).toList();
  }

  Future<List<FavoriteEnregistre>> favoritesPourSauvegarde() async {
    final rows = await db.query('favorites', orderBy: 'created_at DESC');
    return rows.map((row) {
      return FavoriteEnregistre(
        favorite: Favorite(
          id: row['id'] as String,
          kind: row['kind'] as String,
          label: row['label'] as String,
          payload: (jsonDecode(row['payload_json'] as String) as Map)
              .cast<String, dynamic>(),
        ),
        createdAt: row['created_at'] as int,
      );
    }).toList();
  }

  /// Tous les reglages, sans exception.
  ///
  /// Aucun secret ne figure dans cette table : la cle du fournisseur
  /// d'analyse vit dans le trousseau du systeme (`SecureStore`), pas ici. Le
  /// service de sauvegarde applique malgre tout une liste d'exclusion, pour
  /// qu'un reglage ajoute plus tard ne parte pas dans un fichier en clair sans
  /// que personne ne le remarque.
  Future<Map<String, String>> settingsPourSauvegarde() async {
    final rows = await db.query('settings');
    return {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
  }

  /// Inscrit un repas tel qu'il a ete sauvegarde, horodatages compris.
  Future<void> restaurerMeal(MealEnregistre enregistre) async {
    final meal = enregistre.meal;
    await db.transaction((txn) async {
      await txn.insert('meals', {
        'id': meal.id,
        'eaten_at': meal.eatenAt.millisecondsSinceEpoch,
        'name': meal.name,
        'source': meal.source.name,
        'notes': meal.notes,
        'photo_path': meal.photoPath,
        'is_estimate': meal.isEstimate ? 1 : 0,
        'created_at': enregistre.createdAt,
        'updated_at': enregistre.updatedAt,
        'deleted_at': enregistre.deletedAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await _ecrireItems(txn, meal);
    });
  }

  Future<void> restaurerTemplate(TemplateEnregistre enregistre) async {
    final template = enregistre.template;
    await db.insert('templates', {
      'id': template.id,
      'name': template.name,
      'items_json': jsonEncode(
        template.items.map((item) => item.toJson()).toList(),
      ),
      'created_at': enregistre.createdAt,
      'updated_at': enregistre.updatedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> restaurerFavorite(FavoriteEnregistre enregistre) async {
    final favorite = enregistre.favorite;
    await db.insert('favorites', {
      'id': favorite.id,
      'kind': favorite.kind,
      'label': favorite.label,
      'payload_json': jsonEncode(favorite.payload),
      'created_at': enregistre.createdAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> ecrireSettings(Map<String, String> valeurs) async {
    final batch = db.batch();
    for (final entree in valeurs.entries) {
      batch.insert('settings', {
        'key': entree.key,
        'value': entree.value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Identifiants des repas presents localement, supprimes compris.
  ///
  /// Sert a une fusion : ce qui existe deja ne doit pas etre ecrase, et ce qui
  /// a ete supprime ici ne doit pas revenir.
  Future<Set<String>> idsDeMeals() async {
    final rows = await db.query('meals', columns: ['id']);
    return {for (final row in rows) row['id'] as String};
  }

  /// Efface toutes les donnees locales. Utilise par la suppression de compte et
  /// par la remise a zero depuis les reglages.
  Future<void> wipe() async {
    await db.transaction((txn) async {
      await txn.delete('meal_items');
      await txn.delete('meals');
      await txn.delete('templates');
      await txn.delete('favorites');
      await txn.delete('settings');
    });
  }
}

/// Un repas tel qu'il est **stocke** : le modele, plus les horodatages de la
/// ligne.
///
/// `Meal` ne porte que `eaten_at` ; `created_at`, `updated_at` et `deleted_at`
/// n'existent qu'en base. Une sauvegarde qui les perdrait ne pourrait ni
/// conserver une suppression, ni arbitrer une fusion.
class MealEnregistre {
  const MealEnregistre({
    required this.meal,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final Meal meal;
  final int createdAt;
  final int updatedAt;

  /// Non nul lorsque le repas a ete supprime. La ligne reste en base : c'est
  /// ce qui permet a une synchronisation de propager la suppression.
  final int? deletedAt;

  bool get estSupprime => deletedAt != null;
}

/// Un repas personnalise tel qu'il est stocke.
class TemplateEnregistre {
  const TemplateEnregistre({
    required this.template,
    required this.createdAt,
    required this.updatedAt,
  });

  final MealTemplate template;
  final int createdAt;
  final int updatedAt;
}

/// Un favori tel qu'il est stocke.
class FavoriteEnregistre {
  const FavoriteEnregistre({required this.favorite, required this.createdAt});

  final Favorite favorite;
  final int createdAt;
}

/// Repas personnalise enregistre.
class MealTemplate {
  const MealTemplate({
    required this.id,
    required this.name,
    required this.items,
  });

  final String id;
  final String name;
  final List<MealItem> items;

  NutritionValues get totals =>
      NutritionValues.sum(items.map((item) => item.total));

  double get totalGrams => items.fold(0, (sum, item) => sum + item.quantityG);
}

/// Favori enregistre : aliment, produit ou repas personnalise.
class Favorite {
  const Favorite({
    required this.id,
    required this.kind,
    required this.label,
    required this.payload,
  });

  final String id;

  /// « food », « product » ou « template ».
  final String kind;

  final String label;
  final Map<String, dynamic> payload;

  Food? get asFood {
    if (kind == 'template') return null;
    final food = payload['food'];
    if (food is Map) return Food.fromJson(food.cast<String, dynamic>());
    return null;
  }
}
