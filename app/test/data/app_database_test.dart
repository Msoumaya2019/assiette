import 'package:assiette/core/horloge.dart';
import 'package:assiette/data/local/app_database.dart';
import 'package:assiette/data/local/synchronisation_locale.dart';
import 'package:assiette/models/arbitrage.dart';
import 'package:assiette/models/food.dart';
import 'package:assiette/models/goals.dart';
import 'package:assiette/models/meal.dart';
import 'package:assiette/models/nutrition_values.dart';
import 'package:assiette/models/portion.dart';
import 'package:assiette/models/suivi_poids.dart';
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

/// Une horloge d'appareil que le test avance lui-meme.
///
/// Sans elle, deux ecritures tomberaient dans la **meme milliseconde** — une
/// machine va vite — et la propriete la plus importante des pierres tombales ne
/// serait pas eprouvable : on ne peut pas montrer qu'une suppression **bat** une
/// modification anterieure si les deux portent la meme date, parce que c'est
/// alors la regle « a date egale, la suppression gagne » qui decide, et pas
/// celle qu'on veut prouver. Un test qui passerait par accident ne prouve rien.
class _HorlogeReglable {
  /// L'instant que l'horloge rendra, en millisecondes depuis l'epoque.
  ///
  /// Un champ, et non un parametre de constructeur : aucun test ne passe
  /// d'autre valeur, et un parametre jamais fourni est un avertissement — que la
  /// CI refuse, a juste titre.
  int maintenant = 1700000000000;

  Horloge get horloge =>
      Horloge(source: () => DateTime.fromMillisecondsSinceEpoch(maintenant));
}

/// La table synchronisable portant ce nom.
TableSynchronisable _table(String nom) =>
    tablesSynchronisables.firstWhere((table) => table.nom == nom);

void main() {
  // La base reelle passe par le greffon natif de la plateforme, indisponible
  // dans un test : on la fait tourner sur SQLite natif via FFI, en memoire pour
  // que chaque test parte d'un etat vierge.
  setUpAll(sqfliteFfiInit);

  late AppDatabase base;
  late _HorlogeReglable horloge;

  setUp(() async {
    horloge = _HorlogeReglable();
    base = AppDatabase(
      factory: databaseFactoryFfi,
      customPath: inMemoryDatabasePath,
      horloge: horloge.horloge,
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

    test('la remise a zero emporte aussi le suivi du poids', () async {
      await base.savePesee(
        Pesee(id: 'p1', le: DateTime(2026, 9, 12), poidsKg: 70),
      );
      await base.saveMesure(
        Mesure(
          id: 'm1',
          le: DateTime(2026, 9, 12),
          type: TypeMesure.taille,
          valeurCm: 82,
        ),
      );
      await base.writePortion(
        'ciqual:9100',
        const Portion(label: 'part', grams: 80),
      );
      await base.writeObjectifPoids(const ObjectifPoids(cibleKg: 68));

      await base.wipe();

      // Une remise a zero qui laisserait des mensurations derriere elle ne
      // serait pas une remise a zero, et l'utilisateur n'aurait aucun moyen de
      // s'en apercevoir.
      expect(await base.pesees(), isEmpty);
      expect(await base.mesures(), isEmpty);
      expect(await base.portionsPourSauvegarde(), isEmpty);
      expect((await base.readObjectifPoids()).estDefini, isFalse);
    });
  });

  group('Portions', () {
    const part = Portion(label: 'part', grams: 80);

    test('la portion d\'un aliment survit au stockage', () async {
      final enregistre = repas(DateTime(2026, 9, 18), [
        MealItem(food: riz, quantityG: 160, portion: part),
      ]);

      await base.saveMeal(enregistre);
      final relu = (await base.mealById(enregistre.id))!;
      final aliment = relu.items.single;

      expect(aliment.portion, isNotNull);
      expect(aliment.portion!.label, 'part');
      expect(aliment.portion!.grams, 80);

      // Le nombre d'unites est deduit, jamais stocke : deux valeurs a tenir
      // coherentes finiraient par diverger sans que rien ne le signale.
      expect(aliment.nombreDUnites, 2);
      expect(aliment.libellePortion, '2 parts · 160 g');
      // Comparaison approchee : 160 x 28 / 100 ne tombe pas juste en binaire.
      expect(relu.totals.carbs, closeTo(44.8, 1e-9));
    });

    test('un aliment sans portion n\'en invente pas', () async {
      final enregistre = repas(DateTime(2026, 9, 18), [item(riz, 150)]);
      await base.saveMeal(enregistre);

      final aliment = (await base.mealById(enregistre.id))!.items.single;
      expect(aliment.portion, isNull);
      expect(aliment.nombreDUnites, isNull);
      expect(aliment.libellePortion, isNull);
    });

    test('la portion survit aussi a un modele de repas', () async {
      await base.saveTemplate('t1', 'Gouter', [
        MealItem(food: riz, quantityG: 160, portion: part),
      ]);

      final modele = (await base.templates()).single;
      expect(modele.items.single.portion, part);
    });

    test('une portion retenue se relit par la cle de l\'aliment', () async {
      expect(await base.readPortion(AppDatabase.cleDePortion(riz)), isNull);

      await base.writePortion(AppDatabase.cleDePortion(riz), part);

      final retenue = await base.readPortion(AppDatabase.cleDePortion(riz));
      expect(retenue, part);
    });

    test('une portion absurde n\'est pas ecrite', () async {
      // Un poids d'unite nul rendrait toute conversion infinie.
      await base.writePortion('x', const Portion(label: 'rien', grams: 0));
      expect(await base.readPortion('x'), isNull);

      await base.writePortion('y', const Portion(label: '', grams: 80));
      expect(await base.readPortion('y'), isNull);
    });

    test('la portion retenue prime sur l\'etiquette de la source', () async {
      const produit = Food(
        name: 'Yaourt nature',
        per100g: NutritionValues(carbs: 4.5),
        source: FoodSource.openFoodFacts,
        sourceRef: '3033490005247',
        servingSizeG: 125,
        servingLabel: '1 pot (125 g)',
      );

      // Sans rien de retenu, l'etiquette de la source sert de proposition.
      final proposee = await base.portionPour(produit);
      expect(proposee!.label, 'pot');
      expect(proposee.grams, 125);

      // Une fois que l'utilisateur a dit ce qu'il voulait, sa reponse prime :
      // redemander 125 g apres qu'il a declare 150 g serait ignorer ce qu'il a
      // dit.
      await base.writePortion(
        AppDatabase.cleDePortion(produit),
        const Portion(label: 'pot', grams: 150),
      );
      final retenue = await base.portionPour(produit);
      expect(retenue!.grams, 150);
    });

    test('une etiquette inexploitable ne propose rien', () async {
      const produit = Food(
        name: 'Produit',
        per100g: NutritionValues(carbs: 10),
        source: FoodSource.openFoodFacts,
        sourceRef: '1',
        servingSizeG: 100,
        servingLabel: 'une portion',
      );

      expect(await base.portionPour(produit), isNull);
    });
  });

  group('Suivi du poids', () {
    test('une pesee fait un aller-retour, note comprise', () async {
      await base.savePesee(
        Pesee(
          id: 'p1',
          le: DateTime(2026, 9, 12, 8),
          poidsKg: 70.4,
          note: 'a jeun',
        ),
      );

      final relue = (await base.pesees()).single;
      expect(relue.poidsKg, 70.4);
      expect(relue.le, DateTime(2026, 9, 12, 8));
      expect(relue.note, 'a jeun');
    });

    test('les pesees sortent de la plus recente a la plus ancienne', () async {
      for (final jour in [10, 12, 11]) {
        await base.savePesee(
          Pesee(id: 'p$jour', le: DateTime(2026, 9, jour), poidsKg: 70),
        );
      }

      expect((await base.pesees()).map((p) => p.id), ['p12', 'p11', 'p10']);
    });

    test('la fenetre ecarte ce qui precede', () async {
      await base.savePesee(
        Pesee(id: 'vieux', le: DateTime(2026, 8, 1), poidsKg: 75),
      );
      await base.savePesee(
        Pesee(id: 'recent', le: DateTime(2026, 9, 10), poidsKg: 71),
      );

      expect(
        (await base.pesees(depuis: DateTime(2026, 9, 1))).map((p) => p.id),
        ['recent'],
      );
    });

    test('une pesee supprimee disparait sans quitter la base', () async {
      await base.savePesee(
        Pesee(id: 'p1', le: DateTime(2026, 9, 12), poidsKg: 70),
      );
      await base.deletePesee('p1');

      expect(await base.pesees(), isEmpty);

      // La ligne reste, comme pour les repas : une synchronisation future doit
      // pouvoir propager la suppression au lieu de la perdre.
      final lignes = await base.db.query('pesees');
      expect(lignes, hasLength(1));
      expect(lignes.single['deleted_at'], isNotNull);
    });

    test('une mesure fait un aller-retour', () async {
      await base.saveMesure(
        Mesure(
          id: 'm1',
          le: DateTime(2026, 9, 12),
          type: TypeMesure.hanches,
          valeurCm: 96.5,
        ),
      );

      final relue = (await base.mesures()).single;
      expect(relue.type, TypeMesure.hanches);
      expect(relue.valeurCm, 96.5);
      expect(relue.le, DateTime(2026, 9, 12));
    });

    test('une mesure d\'un type inconnu est ecartee, pas fatale', () async {
      // Cas d'une base ecrite par une version plus recente : la version
      // installee doit continuer de lire ce qu'elle comprend.
      await base.db.insert('mesures', {
        'id': 'm-inconnu',
        'mesure_le': DateTime(2026, 9, 12).millisecondsSinceEpoch,
        'type': 'tour-de-mollet',
        'valeur_cm': 38.0,
        'created_at': 1,
        'updated_at': 1,
        'deleted_at': null,
      });
      await base.saveMesure(
        Mesure(
          id: 'm1',
          le: DateTime(2026, 9, 12),
          type: TypeMesure.taille,
          valeurCm: 82,
        ),
      );

      final lues = await base.mesures();
      expect(lues, hasLength(1));
      expect(lues.single.type, TypeMesure.taille);
    });

    test('une mesure supprimee disparait de la lecture', () async {
      await base.saveMesure(
        Mesure(
          id: 'm1',
          le: DateTime(2026, 9, 12),
          type: TypeMesure.taille,
          valeurCm: 82,
        ),
      );
      await base.deleteMesure('m1');

      expect(await base.mesures(), isEmpty);
      expect((await base.db.query('mesures')).single['deleted_at'], isNotNull);
    });

    test('aucun objectif de poids n\'est propose par defaut', () async {
      expect((await base.readObjectifPoids()).estDefini, isFalse);
    });

    test('l\'objectif de poids fait un aller-retour', () async {
      await base.writeObjectifPoids(const ObjectifPoids(cibleKg: 68.5));
      expect((await base.readObjectifPoids()).cibleKg, 68.5);

      await base.writeObjectifPoids(ObjectifPoids.aucun);
      expect((await base.readObjectifPoids()).estDefini, isFalse);
    });

    test('un objectif illisible ne fait pas echouer le demarrage', () async {
      await base.writeSetting('objectif_poids', 'ceci n\'est pas du JSON');
      expect((await base.readObjectifPoids()).estDefini, isFalse);
    });
  });

  group('Une suppression est une modification', () {
    // Pourquoi ce groupe existe. L'arbitrage (`models/arbitrage.dart`) compare
    // `updatedAt` **d'abord**, et ne regarde la suppression qu'a date egale. Une
    // suppression qui laisse `updated_at` a sa valeur d'avant perd donc contre
    // une version distante plus recente : la ligne **ressuscite** sur l'appareil
    // qui vient de la supprimer — exactement le defaut que la pierre tombale
    // existe pour eviter. Cinq des six tables faisaient cela ; seule
    // `deleteFavorite`, la plus recente, ecrivait les deux dates.

    /// La version telle qu'un arbitrage la verrait.
    ///
    /// Lue par le **chemin reel** (`lireLignes`), et non fabriquee a la main
    /// depuis la ligne brute : une colonne renommee casserait ce test, alors
    /// qu'une version fabriquee a la main continuerait de passer en silence.
    Future<VersionArbitrable> version(String table) async =>
        (await lireLignes(base.db, _table(table))).single.version;

    test('les deux dates sont egales, sur les six tables', () async {
      // L'horloge **avance** entre l'enregistrement et la suppression, et c'est
      // indispensable : figee, elle rendrait les deux dates egales meme si la
      // suppression n'ecrivait que `deleted_at`, et ce test passerait sans rien
      // prouver. Le banc l'a montre — la premiere version de ce test ne tombait
      // pas sur la faute qu'il vise.
      final instants = <String, int>{};

      Future<void> supprimer(
        String table,
        Future<void> Function() enregistrer,
        Future<void> Function() effacer,
      ) async {
        await enregistrer();
        horloge.maintenant += 1000;
        await effacer();
        instants[table] = horloge.maintenant;
      }

      final enregistre = repas(DateTime(2026, 9, 18), [item(riz, 150)]);
      await supprimer(
        'meals',
        () => base.saveMeal(enregistre),
        () => base.deleteMeal(enregistre.id),
      );
      await supprimer(
        'templates',
        () => base.saveTemplate('t1', 'Dejeuner', [item(riz, 150)]),
        () => base.deleteTemplate('t1'),
      );
      await supprimer(
        'favorites',
        () => base.addFavorite('f1', 'food', 'Riz', {'name': 'Riz'}),
        () => base.deleteFavorite('f1'),
      );
      await supprimer(
        'portions',
        () => base.writePortion(
          'nom:riz',
          const Portion(label: 'part', grams: 80),
        ),
        () => base.deletePortion('nom:riz'),
      );
      await supprimer(
        'pesees',
        () => base.savePesee(
          Pesee(id: 'p1', le: DateTime(2026, 9, 12), poidsKg: 70),
        ),
        () => base.deletePesee('p1'),
      );
      await supprimer(
        'mesures',
        () => base.saveMesure(
          Mesure(
            id: 'm1',
            le: DateTime(2026, 9, 12),
            type: TypeMesure.taille,
            valeurCm: 82,
          ),
        ),
        () => base.deleteMesure('m1'),
      );

      for (final entree in instants.entries) {
        final ligne = (await base.db.query(entree.key)).single;
        expect(
          ligne['deleted_at'],
          entree.value,
          reason: '${entree.key} : la ligne reste, datee de sa suppression',
        );
        expect(
          ligne['updated_at'],
          entree.value,
          reason:
              '${entree.key} : la date de modification doit etre celle de la '
              'suppression, pas celle de l\'enregistrement — sinon la '
              'suppression perd contre une version distante plus recente, et la '
              'ligne ressuscite',
        );
      }
    });

    test('la suppression bat une modification anterieure', () async {
      final enregistre = repas(DateTime(2026, 9, 18), [item(riz, 150)]);
      await base.saveMeal(enregistre);

      // L'autre appareil a modifie le repas **avant** que celui-ci le supprime.
      final avant = await version('meals');
      final distante = VersionArbitrable(
        updatedAt: avant.updatedAt + 1000,
        deletedAt: null,
        empreinte: avant.empreinte,
      );

      horloge.maintenant = avant.updatedAt + 5000;
      await base.deleteMeal(enregistre.id);
      final locale = await version('meals');

      expect(locale.estSupprimee, isTrue);
      expect(
        arbitrer(locale: locale, distante: distante),
        VerdictArbitrage.garderLocale,
        reason:
            'la suppression est posterieure a la modification : elle doit '
            'gagner, sinon la ligne ressuscite',
      );
    });

    test('une modification posterieure a la suppression gagne', () async {
      // Le temoin negatif, et il compte autant que le test precedent : la
      // suppression n'est **pas** une victoire automatique. Une modification
      // plus recente doit l'emporter, sans quoi un appareil effacerait le
      // travail de l'autre sans recours.
      final enregistre = repas(DateTime(2026, 9, 18), [item(riz, 150)]);
      await base.saveMeal(enregistre);
      await base.deleteMeal(enregistre.id);

      final locale = await version('meals');
      final distante = VersionArbitrable(
        updatedAt: locale.updatedAt + 1000,
        deletedAt: null,
        empreinte: 'peu importe',
      );

      expect(
        arbitrer(locale: locale, distante: distante),
        VerdictArbitrage.prendreDistante,
        reason:
            'une modification posterieure doit gagner, meme contre une '
            'suppression',
      );
    });
  });
}
