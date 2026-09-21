import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/food.dart';
import '../../models/goals.dart';
import '../../models/meal.dart';
import '../../models/nutrition_values.dart';
import '../../models/portion.dart';
import '../../models/suivi_poids.dart';

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
  ///
  /// 1 : schema initial.
  /// 2 : portions nommees (`meal_items.portion_label`, `portion_grams`), table
  ///     `portions` qui retient la portion d'un aliment, et suivi du poids
  ///     (`pesees`, `mesures`).
  /// 3 : pierres tombales la ou il en manquait (`portions`, `templates`,
  ///     `favorites`), et `favorites.updated_at`, qui manquait aussi.
  static const int schemaVersion = 3;

  /// Ce que la version 2 ajoute au schema initial.
  ///
  /// Ecrit **une seule fois**, et execute par les deux chemins : `_onCreate`
  /// l'applique apres les tables d'origine, `_onUpgrade` l'applique a une base
  /// restee en version 1. Recopier ces ordres dans les deux methodes les ferait
  /// diverger un jour, et la divergence ne se verrait que sur les appareils
  /// deja installes — c'est-a-dire exactement ceux dont on ne peut pas
  /// repartir de zero.
  ///
  /// Les `ALTER TABLE ... ADD COLUMN` fonctionnent dans les deux cas : la table
  /// `meal_items` existe deja quand ils sont joues, en creation comme en
  /// migration.
  static const List<String> _ajoutsVersion2 = [
    'ALTER TABLE meal_items ADD COLUMN portion_label TEXT',
    'ALTER TABLE meal_items ADD COLUMN portion_grams REAL',

    // Portion retenue pour un aliment, d'un repas a l'autre. La cle identifie
    // l'aliment : sa reference de source quand elle existe, son nom normalise
    // sinon.
    '''
      CREATE TABLE portions (
        cle TEXT PRIMARY KEY,
        label TEXT NOT NULL,
        grams REAL NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''',

    '''
      CREATE TABLE pesees (
        id TEXT PRIMARY KEY,
        mesure_le INTEGER NOT NULL,
        poids_kg REAL NOT NULL,
        note TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''',
    'CREATE INDEX idx_pesees_le ON pesees (mesure_le DESC)',

    '''
      CREATE TABLE mesures (
        id TEXT PRIMARY KEY,
        mesure_le INTEGER NOT NULL,
        type TEXT NOT NULL,
        valeur_cm REAL NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''',
    'CREATE INDEX idx_mesures_le ON mesures (mesure_le DESC)',
  ];

  /// Ce que la version 3 ajoute : des pierres tombales la ou il en manquait.
  ///
  /// Trois tables supprimaient leurs lignes **definitivement** : `portions`,
  /// `templates` et `favorites`. Une suppression definitive ne se propage pas.
  /// Le jour ou la synchronisation serait branchee, effacer un modele sur un
  /// telephone le laisserait sur les autres — et le prochain echanges l'aurait
  /// fait revenir sur celui-la meme. C'est le meme raisonnement qui avait deja
  /// mene aux pierres tombales de `meals`, `pesees` et `mesures` ; il n'avait
  /// simplement pas ete applique a ces trois-la.
  ///
  /// `favorites.updated_at` manquait aussi, et pour une autre raison : sans
  /// horodatage de modification, deux appareils ne peuvent pas arbitrer entre
  /// deux versions d'un meme favori. La colonne est **remplie depuis
  /// `created_at`** pour les lignes existantes — un favori jamais modifie a
  /// bien ete modifie pour la derniere fois quand il a ete cree.
  ///
  /// `meal_items` n'a **pas** de pierre tombale, et c'est deliberé : les lignes
  /// d'un repas sont reecrites en bloc a chaque enregistrement (`_ecrireItems`),
  /// donc leur cycle de vie est celui de leur repas. Une suppression du repas
  /// les emporte des deux cotes, et une modification les remplace. Leur ajouter
  /// un `deleted_at` creerait un second mecanisme pour dire la meme chose.
  static const List<String> _ajoutsVersion3 = [
    'ALTER TABLE portions ADD COLUMN deleted_at INTEGER',
    'ALTER TABLE templates ADD COLUMN deleted_at INTEGER',
    'ALTER TABLE favorites ADD COLUMN deleted_at INTEGER',
    'ALTER TABLE favorites ADD COLUMN updated_at INTEGER',
    'UPDATE favorites SET updated_at = created_at WHERE updated_at IS NULL',
  ];

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

    // Les deux listes, et dans l'ordre : une base neuve doit naitre au schema
    // courant, pas au schema initial qu'on completerait apres coup.
    for (final ordre in [..._ajoutsVersion2, ..._ajoutsVersion3]) {
      batch.execute(ordre);
    }

    await batch.commit(noResult: true);
  }

  /// Amene une base existante au schema courant, **sans perdre une ligne**.
  ///
  /// Chaque palier est traite separement et dans l'ordre : une base restee en
  /// version 1 doit pouvoir atteindre la version 3 le jour ou elle existera,
  /// sans qu'on ait a ecrire le raccourci 1 -> 3.
  Future<void> _onUpgrade(Database database, int from, int to) async {
    if (from < 2) {
      // Les tables existantes ne sont pas recreees : seules des colonnes et
      // des tables sont ajoutees. Aucun `DROP`, aucun `DELETE` — une migration
      // qui efface les donnees de l'utilisateur pour changer de schema est un
      // bug, pas une migration.
      final batch = database.batch();
      for (final ordre in _ajoutsVersion2) {
        batch.execute(ordre);
      }
      await batch.commit(noResult: true);
    }

    if (from < 3) {
      // Une base restee en version 1 traverse donc les deux paliers a la
      // suite, dans l'ordre, sans qu'on ait ecrit le raccourci 1 -> 3. C'est
      // exactement ce que la version 2 annoncait, et le cas se presente
      // maintenant pour de vrai.
      final batch = database.batch();
      for (final ordre in _ajoutsVersion3) {
        batch.execute(ordre);
      }
      await batch.commit(noResult: true);
    }
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
        'portion_label': item.portion?.label,
        'portion_grams': item.portion?.grams,
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
        // Une portion dont une seule des deux colonnes serait renseignee est
        // ecartee : `Portion.depuisJson` exige les deux, ce qui evite de
        // proposer « 0 g » comme poids d'unite.
        portion: Portion.depuisJson({
          'label': item['portion_label'],
          'grams': item['portion_grams'],
        }),
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
    final rows = await db.query(
      'templates',
      where: 'deleted_at IS NULL',
      orderBy: 'name ASC',
    );
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

  /// Suppression logique : la ligne reste, pour que la suppression puisse se
  /// propager le jour ou la synchronisation existera.
  ///
  /// Une suppression definitive ne laisse aucune trace, donc rien a envoyer.
  /// Le modele efface ici reviendrait depuis un autre appareil, et le prochain
  /// echange le ferait revenir sur celui-ci.
  Future<void> deleteTemplate(String id) async {
    await db.update(
      'templates',
      {'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
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
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('favorites', {
      'id': id,
      'kind': kind,
      'label': label,
      'payload_json': jsonEncode(payload),
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Favorite>> favorites({String? kind}) async {
    final rows = await db.query(
      'favorites',
      where: kind == null
          ? 'deleted_at IS NULL'
          : 'deleted_at IS NULL AND kind = ?',
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

  /// Suppression logique, comme pour les modeles et les repas.
  Future<void> deleteFavorite(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'favorites',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<bool> isFavorite(String id) async {
    final rows = await db.query(
      'favorites',
      columns: ['id'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  // -------------------------------------------------------------------------
  // Portions retenues
  //
  // Une portion appartient a un **aliment**, pas a un repas : c'est ce qui
  // permet de retrouver « 1 gateau = 65 g » au repas suivant. Sans cette table,
  // l'utilisateur devrait redefinir sa portion chaque fois, ce qui reviendrait
  // a ne pas avoir de portion du tout.
  // -------------------------------------------------------------------------

  /// Cle identifiant un aliment dans la table `portions`.
  static String cleDePortion(Food food) => Portion.clePour(
    source: food.source.name,
    sourceRef: food.sourceRef,
    nom: food.name,
  );

  /// Portion a proposer pour un aliment.
  ///
  /// L'ordre compte : une portion **retenue** prime sur l'etiquette annoncee
  /// par la source. C'est le sens meme de « retenir » — si l'utilisateur a
  /// declare une fois que son pot fait 150 g, redemander 125 g a chaque scan
  /// reviendrait a ignorer ce qu'il a dit.
  ///
  /// La portion d'etiquette sert de premier remplissage, et seulement quand
  /// elle est exploitable : `Portion.depuisEtiquette` refuse les formes
  /// ambigues plutot que d'inventer.
  Future<Portion?> portionPour(Food food) async {
    final retenue = await readPortion(cleDePortion(food));
    if (retenue != null) return retenue;
    return Portion.depuisEtiquette(food.servingLabel, food.servingSizeG);
  }

  /// Portion retenue pour un aliment, ou `null` s'il n'en a pas.
  ///
  /// Une portion supprimee n'en a plus : la ligne reste en base pour que la
  /// suppression puisse se propager, mais elle ne doit plus etre proposee.
  Future<Portion?> readPortion(String cle) async {
    final rows = await db.query(
      'portions',
      where: 'cle = ? AND deleted_at IS NULL',
      whereArgs: [cle],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Portion.depuisJson({
      'label': rows.first['label'],
      'grams': rows.first['grams'],
    });
  }

  /// Retient la portion d'un aliment. Un poids d'unite nul n'est pas ecrit :
  /// il rendrait toute conversion absurde.
  ///
  /// Redefinir une portion **efface sa pierre tombale** : c'est le geste par
  /// lequel l'utilisateur revient sur sa suppression, et il doit etre possible
  /// sans passer par la base.
  Future<void> writePortion(String cle, Portion portion) async {
    if (!portion.estValide) return;
    await db.insert('portions', {
      'cle': cle,
      'label': portion.label,
      'grams': portion.grams,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'deleted_at': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Suppression logique, comme pour les repas et les pesees.
  Future<void> deletePortion(String cle) async {
    await db.update(
      'portions',
      {'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'cle = ?',
      whereArgs: [cle],
    );
  }

  /// Portions **vivantes**, par cle d'aliment.
  ///
  /// C'est la lecture de l'interface : une portion supprimee ne doit plus etre
  /// proposee, meme si sa ligne subsiste en base. La table porte deux lecteurs
  /// aux besoins opposes — celui-ci, qui veut ce qui reste, et
  /// [portionsPourSauvegarde], qui veut aussi ce qui a disparu — et c'est
  /// pourquoi ils sont deux methodes distinctes plutot qu'un filtre pose a
  /// l'appel : un filtre oublie se voit mal, une methode qui ment sur son nom
  /// se voit tout de suite.
  Future<Map<String, Portion>> portionsVivantes() async {
    final rows = await db.query(
      'portions',
      where: 'deleted_at IS NULL',
      orderBy: 'cle ASC',
    );
    final resultat = <String, Portion>{};
    for (final row in rows) {
      final portion = Portion.depuisJson({
        'label': row['label'],
        'grams': row['grams'],
      });
      if (portion == null) continue;
      resultat[row['cle'] as String] = portion;
    }
    return resultat;
  }

  /// Portions telles qu'elles sont stockees, **supprimees comprises**.
  ///
  /// Une sauvegarde a besoin des pierres tombales, pour la meme raison que pour
  /// les repas : sans elles, restaurer sur un appareil ou la portion avait ete
  /// supprimee la ferait reapparaitre.
  Future<List<PortionEnregistree>> portionsPourSauvegarde() async {
    final rows = await db.query('portions', orderBy: 'cle ASC');
    final resultat = <PortionEnregistree>[];
    for (final row in rows) {
      final portion = Portion.depuisJson({
        'label': row['label'],
        'grams': row['grams'],
      });
      if (portion == null) continue;
      resultat.add(
        PortionEnregistree(
          cle: row['cle'] as String,
          portion: portion,
          updatedAt: row['updated_at'] as int,
          deletedAt: row['deleted_at'] as int?,
        ),
      );
    }
    return resultat;
  }

  /// Inscrit une portion telle qu'elle a ete sauvegardee, horodatages compris.
  Future<void> restaurerPortion(PortionEnregistree enregistree) async {
    if (!enregistree.portion.estValide) return;
    await db.insert('portions', {
      'cle': enregistree.cle,
      'label': enregistree.portion.label,
      'grams': enregistree.portion.grams,
      'updated_at': enregistree.updatedAt,
      'deleted_at': enregistree.deletedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Cles des portions presentes localement, **supprimees comprises**.
  ///
  /// Sert a une fusion, et doit donc inclure les pierres tombales : une portion
  /// supprimee ici ne doit pas etre ramenee par une sauvegarde. Sans cela, une
  /// fusion ferait revivre exactement ce que l'utilisateur venait d'effacer.
  Future<Set<String>> clesDePortions() async {
    final rows = await db.query('portions', columns: ['cle']);
    return {for (final row in rows) row['cle'] as String};
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
  // Suivi du poids
  //
  // Suivi personnel : l'application enregistre et affiche, elle ne suggere
  // aucune cible et ne produit aucun conseil. Ces donnees ne quittent pas
  // l'appareil, sauf par la sauvegarde que l'utilisateur declenche lui-meme.
  // -------------------------------------------------------------------------

  Future<ObjectifPoids> readObjectifPoids() async {
    final raw = await readSetting('objectif_poids');
    if (raw == null || raw.isEmpty) return ObjectifPoids.aucun;
    try {
      return ObjectifPoids.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } on FormatException {
      return ObjectifPoids.aucun;
    }
  }

  Future<void> writeObjectifPoids(ObjectifPoids objectif) =>
      writeSetting('objectif_poids', jsonEncode(objectif.toJson()));

  /// Pesees, de la plus recente a la plus ancienne.
  ///
  /// Les pesees supprimees sont exclues : la ligne reste en base pour qu'une
  /// synchronisation puisse propager la suppression, mais elle ne doit plus
  /// apparaitre nulle part.
  Future<List<Pesee>> pesees({DateTime? depuis, int? limit}) async {
    final rows = await db.query(
      'pesees',
      where: depuis == null
          ? 'deleted_at IS NULL'
          : 'deleted_at IS NULL AND mesure_le >= ?',
      whereArgs: depuis == null ? null : [depuis.millisecondsSinceEpoch],
      orderBy: 'mesure_le DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(_lirePesee).nonNulls.toList();
  }

  Future<void> savePesee(Pesee pesee) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('pesees', {
      'id': pesee.id,
      'mesure_le': pesee.le.millisecondsSinceEpoch,
      'poids_kg': pesee.poidsKg,
      'note': pesee.note,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Suppression logique, comme pour les repas.
  Future<void> deletePesee(String id) async {
    await db.update(
      'pesees',
      {'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mesures, de la plus recente a la plus ancienne.
  Future<List<Mesure>> mesures({DateTime? depuis}) async {
    final rows = await db.query(
      'mesures',
      where: depuis == null
          ? 'deleted_at IS NULL'
          : 'deleted_at IS NULL AND mesure_le >= ?',
      whereArgs: depuis == null ? null : [depuis.millisecondsSinceEpoch],
      orderBy: 'mesure_le DESC, created_at DESC',
    );
    // Une mesure dont le type est inconnu est ecartee au lieu de faire echouer
    // la lecture : une version plus ancienne de l'application doit pouvoir
    // ouvrir une base ecrite par une version plus recente.
    return rows.map(_lireMesure).nonNulls.toList();
  }

  Future<void> saveMesure(Mesure mesure) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('mesures', {
      'id': mesure.id,
      'mesure_le': mesure.le.millisecondsSinceEpoch,
      'type': mesure.type.name,
      'valeur_cm': mesure.valeurCm,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteMesure(String id) async {
    await db.update(
      'mesures',
      {'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Pesee? _lirePesee(Map<String, Object?> row) {
    final poids = (row['poids_kg'] as num?)?.toDouble();
    final le = row['mesure_le'] as int?;
    if (poids == null || le == null) return null;
    return Pesee(
      id: row['id'] as String,
      le: DateTime.fromMillisecondsSinceEpoch(le),
      poidsKg: poids,
      note: row['note'] as String?,
    );
  }

  Mesure? _lireMesure(Map<String, Object?> row) {
    final type = TypeMesure.fromId(row['type'] as String?);
    final valeur = (row['valeur_cm'] as num?)?.toDouble();
    final le = row['mesure_le'] as int?;
    if (type == null || valeur == null || le == null) return null;
    return Mesure(
      id: row['id'] as String,
      le: DateTime.fromMillisecondsSinceEpoch(le),
      type: type,
      valeurCm: valeur,
    );
  }

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

  /// Modeles enregistres, **supprimes compris**.
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
        deletedAt: row['deleted_at'] as int?,
      );
    }).toList();
  }

  /// Favoris, **supprimes compris**.
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
        // Une base ecrite avant la version 3 a des `updated_at` nuls : la
        // migration les remplit, mais une ligne ecrite entre-temps par un
        // chemin qui ne les poserait pas ne doit pas faire echouer la lecture.
        updatedAt: (row['updated_at'] as int?) ?? (row['created_at'] as int),
        deletedAt: row['deleted_at'] as int?,
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
      'deleted_at': enregistre.deletedAt,
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
      'updated_at': enregistre.updatedAt,
      'deleted_at': enregistre.deletedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Pesees telles qu'elles sont stockees, **supprimees comprises**.
  Future<List<PeseeEnregistree>> peseesPourSauvegarde() async {
    final rows = await db.query('pesees', orderBy: 'mesure_le ASC');
    return rows
        .map((row) {
          final pesee = _lirePesee(row);
          if (pesee == null) return null;
          return PeseeEnregistree(
            pesee: pesee,
            createdAt: row['created_at'] as int,
            updatedAt: row['updated_at'] as int,
            deletedAt: row['deleted_at'] as int?,
          );
        })
        .nonNulls
        .toList();
  }

  /// Mesures telles qu'elles sont stockees, **supprimees comprises**.
  Future<List<MesureEnregistree>> mesuresPourSauvegarde() async {
    final rows = await db.query('mesures', orderBy: 'mesure_le ASC');
    return rows
        .map((row) {
          final mesure = _lireMesure(row);
          if (mesure == null) return null;
          return MesureEnregistree(
            mesure: mesure,
            createdAt: row['created_at'] as int,
            updatedAt: row['updated_at'] as int,
            deletedAt: row['deleted_at'] as int?,
          );
        })
        .nonNulls
        .toList();
  }

  Future<void> restaurerPesee(PeseeEnregistree enregistree) async {
    final pesee = enregistree.pesee;
    await db.insert('pesees', {
      'id': pesee.id,
      'mesure_le': pesee.le.millisecondsSinceEpoch,
      'poids_kg': pesee.poidsKg,
      'note': pesee.note,
      'created_at': enregistree.createdAt,
      'updated_at': enregistree.updatedAt,
      'deleted_at': enregistree.deletedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> restaurerMesure(MesureEnregistree enregistree) async {
    final mesure = enregistree.mesure;
    await db.insert('mesures', {
      'id': mesure.id,
      'mesure_le': mesure.le.millisecondsSinceEpoch,
      'type': mesure.type.name,
      'valeur_cm': mesure.valeurCm,
      'created_at': enregistree.createdAt,
      'updated_at': enregistree.updatedAt,
      'deleted_at': enregistree.deletedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Identifiants des pesees presentes localement, supprimees comprises.
  Future<Set<String>> idsDePesees() async {
    final rows = await db.query('pesees', columns: ['id']);
    return {for (final row in rows) row['id'] as String};
  }

  /// Identifiants des mesures presentes localement, supprimees comprises.
  Future<Set<String>> idsDeMesures() async {
    final rows = await db.query('mesures', columns: ['id']);
    return {for (final row in rows) row['id'] as String};
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
  ///
  /// Toutes les tables y passent, y compris le suivi du poids : une remise a
  /// zero qui laisserait des mensurations derriere elle ne serait pas une
  /// remise a zero, et l'utilisateur n'aurait aucun moyen de le voir.
  Future<void> wipe() async {
    await db.transaction((txn) async {
      await txn.delete('meal_items');
      await txn.delete('meals');
      await txn.delete('templates');
      await txn.delete('favorites');
      await txn.delete('portions');
      await txn.delete('pesees');
      await txn.delete('mesures');
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
    this.deletedAt,
  });

  final MealTemplate template;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  bool get estSupprime => deletedAt != null;
}

/// Un favori tel qu'il est stocke.
class FavoriteEnregistre {
  const FavoriteEnregistre({
    required this.favorite,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final Favorite favorite;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  bool get estSupprime => deletedAt != null;
}

/// Une portion telle qu'elle est stockee.
///
/// La cle identifie l'aliment, pas la ligne : c'est elle qui sert de cle
/// primaire, et c'est elle qui doit voyager avec la pierre tombale.
class PortionEnregistree {
  const PortionEnregistree({
    required this.cle,
    required this.portion,
    required this.updatedAt,
    this.deletedAt,
  });

  final String cle;
  final Portion portion;
  final int updatedAt;
  final int? deletedAt;

  bool get estSupprimee => deletedAt != null;
}

/// Une pesee telle qu'elle est stockee.
///
/// Meme raison que pour les repas : `savePesee` remet `created_at` a maintenant
/// et `deleted_at` a nul. Restaurer avec elle **ressusciterait** une pesee que
/// l'utilisateur avait supprimee.
class PeseeEnregistree {
  const PeseeEnregistree({
    required this.pesee,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final Pesee pesee;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  bool get estSupprimee => deletedAt != null;
}

/// Une mesure corporelle telle qu'elle est stockee.
class MesureEnregistree {
  const MesureEnregistree({
    required this.mesure,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final Mesure mesure;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  bool get estSupprimee => deletedAt != null;
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
