import 'package:assiette/data/local/app_database.dart';
import 'package:assiette/models/food.dart';
import 'package:assiette/models/goals.dart';
import 'package:assiette/models/meal.dart';
import 'package:assiette/models/nutrition_values.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Aliments de test, aux valeurs rondes pour que les attentes se verifient de
/// tete. Ils couvrent volontairement les deux origines possibles d'une donnee :
/// une table de reference et une saisie manuelle.
const riz = Food(
  name: 'Riz blanc cuit',
  per100g: NutritionValues(
    kcal: 130,
    carbs: 28,
    sugars: 0.1,
    starch: 27,
    protein: 2.7,
    fat: 0.3,
    saturatedFat: 0.1,
    fiber: 0.4,
    salt: 0.01,
  ),
  source: FoodSource.ciqual,
  sourceRef: '9100',
  category: 'Cereales et derives',
);

const pain = Food(
  name: 'Pain complet',
  per100g: NutritionValues(
    kcal: 250,
    carbs: 45,
    sugars: 3,
    starch: 42,
    protein: 9,
    fat: 3,
    saturatedFat: 0.6,
    fiber: 7,
    salt: 1.2,
  ),
  source: FoodSource.manual,
);

/// Produit industriel, pour verifier que la provenance commerciale survit elle
/// aussi au stockage : c'est elle qui permet a l'interface de dire d'ou vient
/// une valeur.
const yaourt = Food(
  name: 'Yaourt nature',
  per100g: NutritionValues(
    kcal: 60,
    carbs: 4.5,
    sugars: 4.5,
    protein: 4,
    fat: 3,
    saturatedFat: 2,
    salt: 0.1,
  ),
  source: FoodSource.openFoodFacts,
  sourceRef: '3033490005247',
  brand: 'Marque Test',
  imageUrl: 'https://images.openfoodfacts.org/test.jpg',
);

MealItem item(Food food, double grams, {double? confidence}) =>
    MealItem(food: food, quantityG: grams, confidence: confidence);

Meal repas(
  DateTime at,
  List<MealItem> items, {
  String name = 'Repas',
  MealSource source = MealSource.manual,
  bool isEstimate = false,
}) => Meal(
  eatenAt: at,
  name: name,
  items: items,
  source: source,
  isEstimate: isEstimate,
);

/// Verifie que les neuf constituants ont bien survecu au stockage.
///
/// Une colonne oubliee dans `saveMeal` ou dans la relecture ferait disparaitre
/// une valeur sans bruit : le total resterait plausible, mais faux. C'est
/// exactement le genre de perte qu'un test doit empecher.
void attendreLesMemesValeurs(NutritionValues attendu, NutritionValues obtenu) {
  expect(obtenu.kcal, attendu.kcal, reason: 'kcal');
  expect(obtenu.carbs, attendu.carbs, reason: 'glucides');
  expect(obtenu.sugars, attendu.sugars, reason: 'sucres');
  expect(obtenu.starch, attendu.starch, reason: 'amidon');
  expect(obtenu.protein, attendu.protein, reason: 'proteines');
  expect(obtenu.fat, attendu.fat, reason: 'lipides');
  expect(obtenu.saturatedFat, attendu.saturatedFat, reason: 'satures');
  expect(obtenu.fiber, attendu.fiber, reason: 'fibres');
  expect(obtenu.salt, attendu.salt, reason: 'sel');
}

void main() {
  // La base reelle passe par le greffon natif de la plateforme, indisponible
  // dans un test : on la fait tourner sur SQLite natif via FFI, en memoire pour
  // que chaque test parte d'un etat vierge.
  setUpAll(sqfliteFfiInit);

  late AppDatabase base;

  setUp(() async {
    base = AppDatabase(
      factory: databaseFactoryFfi,
      customPath: inMemoryDatabasePath,
    );
    await base.open();
  });

  tearDown(() => base.close());

  group('Repas', () {
    test('un repas enregistre se relit a l\'identique', () async {
      final enregistre = repas(
        DateTime(2026, 9, 18, 12, 30),
        [
          item(riz, 150, confidence: 0.8),
          MealItem(food: pain, quantityG: 60, portionSize: PortionSize.small),
        ],
        name: 'Dejeuner',
        source: MealSource.photo,
        isEstimate: true,
      )..notes = 'Pris au restaurant';

      await base.saveMeal(enregistre);
      final relu = await base.mealById(enregistre.id);

      expect(relu, isNotNull);
      expect(relu!.name, 'Dejeuner');
      expect(relu.eatenAt, DateTime(2026, 9, 18, 12, 30));
      expect(relu.source, MealSource.photo);
      expect(relu.isEstimate, isTrue);
      expect(relu.notes, 'Pris au restaurant');

      // L'ordre des aliments est celui de la saisie.
      expect(relu.items.map((i) => i.food.name), [
        'Riz blanc cuit',
        'Pain complet',
      ]);
      expect(relu.items.first.quantityG, 150);
      expect(relu.items.first.confidence, 0.8);
      expect(relu.items.first.food.source, FoodSource.ciqual);
      expect(relu.items.first.food.sourceRef, '9100');

      // Un aliment saisi a la main garde sa provenance et sa portion.
      expect(relu.items[1].food.source, FoodSource.manual);
      expect(relu.items[1].portionSize, PortionSize.small);
      expect(relu.items[1].confidence, isNull);

      // Aucun constituant n'est perdu au passage en base.
      attendreLesMemesValeurs(riz.per100g, relu.items.first.food.per100g);
      attendreLesMemesValeurs(pain.per100g, relu.items[1].food.per100g);
    });

    test('la provenance d\'un produit industriel survit au stockage', () async {
      // Sans la source, la marque et la reference, l'interface ne pourrait plus
      // distinguer une valeur de reference d'une estimation — exigence de
      // conception, pas confort d'affichage.
      final enregistre = repas(DateTime(2026, 9, 18), [item(yaourt, 125)]);
      await base.saveMeal(enregistre);

      final relu = (await base.mealById(enregistre.id))!;
      final food = relu.items.single.food;

      expect(food.source, FoodSource.openFoodFacts);
      expect(food.sourceRef, '3033490005247');
      expect(food.brand, 'Marque Test');
      expect(food.imageUrl, 'https://images.openfoodfacts.org/test.jpg');
      expect(food.displayName, 'Yaourt nature — Marque Test');
      attendreLesMemesValeurs(yaourt.per100g, food.per100g);
    });

    test('les valeurs sont stockees pour 100 g, jamais en total', () async {
      await base.saveMeal(repas(DateTime(2026, 9, 18), [item(riz, 100)]));

      // Lecture de la colonne brute : c'est la seule facon de verifier
      // l'invariant de stockage lui-meme.
      final lignes = await base.db.query('meal_items');
      final ligne = lignes.single;

      expect(ligne['quantity_g'], 100.0);
      expect(ligne['carbs_100g'], 28.0);
      expect(ligne['kcal_100g'], 130.0);
      expect(ligne['protein_100g'], 2.7);
      expect(ligne['salt_100g'], 0.01);
    });

    test(
      'doubler la portion double le total sans toucher aux valeurs de reference',
      () async {
        final enregistre = repas(DateTime(2026, 9, 18), [item(riz, 100)]);
        await base.saveMeal(enregistre);

        final avant = (await base.mealById(enregistre.id))!;
        expect(avant.totals.carbs, 28.0);
        expect(avant.totals.kcal, 130.0);

        // L'utilisateur corrige la portion apres coup.
        avant.items.first.quantityG = 200;
        await base.saveMeal(avant);

        final apres = (await base.mealById(enregistre.id))!;
        expect(apres.totals.carbs, 56.0);
        expect(apres.totals.kcal, 260.0);
        expect(apres.totalGrams, 200.0);

        // Les valeurs de reference n'ont pas bouge, et l'enregistrement remplace
        // la ligne au lieu d'en ajouter une seconde.
        final lignes = await base.db.query('meal_items');
        expect(lignes, hasLength(1));
        expect(lignes.single['carbs_100g'], 28.0);
        expect(lignes.single['quantity_g'], 200.0);
        expect(apres.items.first.food.per100g.carbs, 28.0);
      },
    );

    test('une suppression est logique : la ligne reste, invisible', () async {
      final enregistre = repas(DateTime(2026, 9, 18), [item(riz, 100)]);
      await base.saveMeal(enregistre);
      await base.deleteMeal(enregistre.id);

      expect(await base.mealById(enregistre.id), isNull);
      expect(await base.recentMeals(), isEmpty);

      // La ligne est conservee pour qu'une future synchronisation puisse
      // propager la suppression au lieu de la perdre.
      final lignes = await base.db.query('meals');
      expect(lignes, hasLength(1));
      expect(lignes.single['deleted_at'], isNotNull);
    });

    test('la periode inclut ses bornes et exclut l\'exterieur', () async {
      final debut = DateTime(2026, 9, 18);
      final fin = DateTime(2026, 9, 18, 23, 59, 59);

      await base.saveMeal(repas(debut, [item(riz, 100)], name: 'Minuit'));
      await base.saveMeal(
        repas(fin, [item(riz, 100)], name: 'Derniere seconde'),
      );
      await base.saveMeal(
        repas(debut.subtract(const Duration(milliseconds: 1)), [
          item(riz, 100),
        ], name: 'Avant'),
      );
      await base.saveMeal(
        repas(fin.add(const Duration(milliseconds: 1)), [
          item(riz, 100),
        ], name: 'Apres'),
      );

      final journee = await base.mealsBetween(debut, fin);
      expect(journee.map((m) => m.name), ['Minuit', 'Derniere seconde']);
    });

    test('les repas recents sortent du plus recent au plus ancien', () async {
      for (var jour = 1; jour <= 3; jour++) {
        await base.saveMeal(
          repas(DateTime(2026, 9, jour), [item(riz, 100)], name: 'Jour $jour'),
        );
      }

      expect((await base.recentMeals()).map((m) => m.name), [
        'Jour 3',
        'Jour 2',
        'Jour 1',
      ]);

      // La limite sert au defilement de l'historique.
      expect((await base.recentMeals(limit: 2)).map((m) => m.name), [
        'Jour 3',
        'Jour 2',
      ]);

      // Le curseur exclut strictement la date demandee.
      expect(
        (await base.recentMeals(
          before: DateTime(2026, 9, 3),
        )).map((m) => m.name),
        ['Jour 2', 'Jour 1'],
      );
    });
  });

  group('Reglages et objectifs', () {
    test('un reglage absent se lit nul, et se reecrit', () async {
      expect(await base.readSetting('analysis_mode'), isNull);

      await base.writeSetting('analysis_mode', 'proxy');
      expect(await base.readSetting('analysis_mode'), 'proxy');

      await base.writeSetting('analysis_mode', 'local');
      expect(await base.readSetting('analysis_mode'), 'local');
    });

    test('aucun objectif n\'est propose par defaut', () async {
      final parDefaut = await base.readGoals();
      expect(parDefaut.isEmpty, isTrue);
      expect(parDefaut.carbsG, isNull);
    });

    test('les objectifs personnels font un aller-retour', () async {
      await base.writeGoals(
        const DailyGoals(carbsG: 180, kcal: 2000, fiberG: 30),
      );

      final relus = await base.readGoals();
      expect(relus.carbsG, 180);
      expect(relus.kcal, 2000);
      expect(relus.fiberG, 30);
      expect(relus.proteinG, isNull);
      expect(relus.fatG, isNull);
    });
  });

  group('Modeles et favoris', () {
    test('les modeles de repas reviennent tries par nom', () async {
      await base.saveTemplate('b', 'Dejeuner', [item(riz, 150)]);
      await base.saveTemplate('a', 'Petit dejeuner', [item(pain, 60)]);

      final modeles = await base.templates();
      expect(modeles.map((m) => m.name), ['Dejeuner', 'Petit dejeuner']);
      expect(modeles.first.items.single.quantityG, 150);
      expect(modeles.first.items.single.food.name, 'Riz blanc cuit');
      attendreLesMemesValeurs(
        riz.per100g,
        modeles.first.items.single.food.per100g,
      );
    });

    test(
      'reenregistrer un modele du meme identifiant remplace le precedent',
      () async {
        await base.saveTemplate('a', 'Dejeuner', [item(riz, 150)]);
        await base.saveTemplate('a', 'Dejeuner', [item(riz, 250)]);

        final modeles = await base.templates();
        expect(modeles, hasLength(1));
        expect(modeles.single.items.single.quantityG, 250);
      },
    );

    test('les favoris se filtrent par genre', () async {
      await base.addFavorite('f-riz', 'food', 'Riz blanc cuit', {
        'name': 'Riz blanc cuit',
      });
      await base.addFavorite('f-repas', 'meal', 'Dejeuner', {
        'name': 'Dejeuner',
      });

      expect(await base.favorites(), hasLength(2));
      expect(
        (await base.favorites(kind: 'food')).single.label,
        'Riz blanc cuit',
      );
      expect((await base.favorites(kind: 'meal')).single.label, 'Dejeuner');

      expect(await base.isFavorite('f-riz'), isTrue);
      expect(await base.isFavorite('f-inconnu'), isFalse);

      await base.deleteFavorite('f-riz');
      expect(await base.isFavorite('f-riz'), isFalse);
      expect(await base.favorites(), hasLength(1));
    });
  });

  group('Remise a zero', () {
    test('la remise a zero vide toutes les tables', () async {
      await base.saveMeal(repas(DateTime(2026, 9, 18), [item(riz, 100)]));
      await base.saveTemplate('t1', 'Petit dejeuner', [item(pain, 60)]);
      await base.addFavorite('f1', 'food', 'Riz', {'name': 'Riz'});
      await base.writeSetting('theme', 'dark');
      await base.writeGoals(const DailyGoals(carbsG: 200));

      await base.wipe();

      expect(await base.recentMeals(), isEmpty);
      expect(await base.templates(), isEmpty);
      expect(await base.favorites(), isEmpty);
      expect(await base.readSetting('theme'), isNull);
      expect((await base.readGoals()).isEmpty, isTrue);

      // Les aliments partent avec les repas : sinon la base grossirait
      // indefiniment apres une remise a zero.
      final lignes = await base.db.query('meal_items');
      expect(lignes, isEmpty);
    });
  });
}
