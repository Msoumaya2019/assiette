import 'package:assiette/models/food.dart';
import 'package:assiette/models/goals.dart';
import 'package:assiette/models/meal.dart';
import 'package:assiette/models/nutrition_values.dart';
import 'package:assiette/services/nutrition_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Aliment de test, avec des valeurs rondes pour que les attentes restent
/// lisibles : 50 g de glucides pour 100 g.
Food food(
  String name, {
  double carbs = 50,
  double kcal = 250,
  double protein = 8,
  double fat = 4,
  double fiber = 2,
  double sugars = 5,
}) {
  return Food(
    name: name,
    per100g: NutritionValues(
      kcal: kcal,
      carbs: carbs,
      protein: protein,
      fat: fat,
      fiber: fiber,
      sugars: sugars,
    ),
    source: FoodSource.ciqual,
  );
}

Meal mealAt(DateTime at, List<MealItem> items, {String name = 'Repas'}) {
  return Meal(eatenAt: at, name: name, items: items, isEstimate: false);
}

MealItem item(
  double grams, {
  String name = 'Riz',
  double? carbs,
  double? confidence,
  bool isEstimate = false,
}) {
  return MealItem(
    food: food(name, carbs: carbs ?? 50),
    quantityG: grams,
    confidence: confidence,
    isEstimate: isEstimate,
  );
}

void main() {
  final reference = DateTime(2026, 3, 18, 12, 0);

  group('Totaux d\'un repas', () {
    test('la somme des glucides correspond au poids de chaque aliment', () {
      final meal = mealAt(reference, [
        item(180, name: 'Riz', carbs: 28), // 50,4 g
        item(150, name: 'Poulet', carbs: 0), // 0 g
        item(60, name: 'Pain', carbs: 55), // 33 g
      ]);

      expect(meal.totals.carbs, closeTo(83.4, 0.001));
    });

    test('un repas vide totalise zero', () {
      final meal = mealAt(reference, []);
      expect(meal.totals.carbs, 0);
      expect(meal.totals.isNotEmpty, isFalse);
      expect(meal.isEmpty, isTrue);
    });

    test('le poids total additionne les quantites', () {
      final meal = mealAt(reference, [item(180), item(120), item(50)]);
      expect(meal.totalGrams, 350);
    });

    test('modifier une quantite change le total sans toucher aux autres', () {
      final first = item(180, name: 'Riz', carbs: 28);
      final second = item(150, name: 'Poulet', carbs: 0);
      final meal = mealAt(reference, [first, second]);

      final before = meal.totals.carbs;
      meal.items[0] = meal.items[0].copyWith(quantityG: 90);
      final after = meal.totals.carbs;

      expect(before, closeTo(50.4, 0.001));
      expect(after, closeTo(25.2, 0.001));
    });
  });

  group('Confiance globale', () {
    test('une moyenne ponderee par le poids, pas une moyenne simple', () {
      final meal = mealAt(reference, [
        item(100, name: 'Riz', confidence: 0.9),
        item(400, name: 'Poulet', confidence: 0.5),
      ]);

      // (0.9 * 100 + 0.5 * 400) / 500 = 0.58
      expect(meal.overallConfidence, closeTo(0.58, 1e-9));
    });

    test('les aliments saisis a la main sont exclus du calcul', () {
      final meal = mealAt(reference, [
        item(100, name: 'Riz', confidence: 0.8),
        item(200, name: 'Pain'), // saisie manuelle : pas de confiance
      ]);

      expect(meal.overallConfidence, closeTo(0.8, 1e-9));
    });

    test('sans aliment estime, la confiance est nulle', () {
      final meal = mealAt(reference, [item(100), item(200)]);
      expect(meal.overallConfidence, isNull);
      expect(meal.needsReview, isFalse);
    });

    test('une confiance faible declenche la demande de verification', () {
      final meal = mealAt(reference, [item(200, confidence: 0.4)]);
      expect(meal.needsReview, isTrue);
    });

    test('une confiance elevee ne declenche pas de verification', () {
      final meal = mealAt(reference, [item(200, confidence: 0.92)]);
      expect(meal.needsReview, isFalse);
    });
  });

  group('Filtrage par periode', () {
    final meals = [
      mealAt(DateTime(2026, 3, 16, 8), [
        item(100, carbs: 50),
      ], name: 'Lundi matin'),
      mealAt(DateTime(2026, 3, 16, 20), [
        item(100, carbs: 50),
      ], name: 'Lundi soir'),
      mealAt(DateTime(2026, 3, 17, 12), [
        item(200, carbs: 50),
      ], name: 'Mardi midi'),
      mealAt(DateTime(2026, 3, 18, 12), [
        item(50, carbs: 100),
      ], name: 'Mercredi midi'),
    ];

    test('les repas d\'un jour sont correctement isoles', () {
      final monday = NutritionCalculator.forDay(meals, DateTime(2026, 3, 16));
      expect(monday.length, 2);
      expect(
        monday.map((meal) => meal.name),
        containsAll(['Lundi matin', 'Lundi soir']),
      );
    });

    test('un repas en fin de journee appartient bien a ce jour', () {
      final late = mealAt(DateTime(2026, 3, 16, 23, 59, 59), [item(100)]);
      expect(
        NutritionCalculator.forDay([late], DateTime(2026, 3, 16)).length,
        1,
      );
      expect(
        NutritionCalculator.forDay([late], DateTime(2026, 3, 17)),
        isEmpty,
      );
    });

    test('un repas a minuit appartient au jour qui commence', () {
      final midnight = mealAt(DateTime(2026, 3, 17, 0, 0, 0), [item(100)]);
      expect(
        NutritionCalculator.forDay([midnight], DateTime(2026, 3, 16)),
        isEmpty,
      );
      expect(
        NutritionCalculator.forDay([midnight], DateTime(2026, 3, 17)).length,
        1,
      );
    });

    test('le resume du jour agrege totaux et nombre de repas', () {
      final summary = NutritionCalculator.summaryForDay(
        meals,
        DateTime(2026, 3, 16),
      );

      expect(summary.mealCount, 2);
      expect(summary.totals.carbs, closeTo(100, 0.001)); // 2 x 50 g
    });
  });

  group('Serie journaliere', () {
    test('sept jours sont toujours renvoyes, meme sans repas', () {
      final series = NutritionCalculator.dailySeries(
        const [],
        reference,
        days: 7,
      );
      expect(series.length, 7);
      expect(series.every((bucket) => bucket.mealCount == 0), isTrue);
      expect(series.every((bucket) => bucket.totals.carbs == 0), isTrue);
    });

    test('la serie se termine au jour de reference', () {
      final series = NutritionCalculator.dailySeries(
        const [],
        reference,
        days: 7,
      );
      expect(series.last.date, DateTime(2026, 3, 18));
      expect(series.first.date, DateTime(2026, 3, 12));
    });

    test('les repas sont places dans le bon seau', () {
      final meals = [
        mealAt(DateTime(2026, 3, 18, 12), [item(100, carbs: 50)]),
        mealAt(DateTime(2026, 3, 16, 12), [item(200, carbs: 50)]),
      ];

      final series = NutritionCalculator.dailySeries(meals, reference, days: 7);

      expect(series.last.totals.carbs, closeTo(50, 0.001));
      expect(series[4].totals.carbs, closeTo(100, 0.001)); // 16 mars
      expect(series[0].totals.carbs, 0); // 12 mars
    });

    test('un repas hors de la fenetre est ignore', () {
      final meals = [
        mealAt(DateTime(2026, 2, 1, 12), [item(100)]),
      ];
      final series = NutritionCalculator.dailySeries(meals, reference, days: 7);
      expect(series.every((bucket) => bucket.mealCount == 0), isTrue);
    });
  });

  group('Serie hebdomadaire', () {
    test('les semaines commencent le lundi', () {
      final series = NutritionCalculator.weeklySeries(
        const [],
        reference,
        weeks: 6,
      );
      expect(series.length, 6);
      expect(
        series.every((bucket) => bucket.date.weekday == DateTime.monday),
        isTrue,
      );
    });

    test('la derniere semaine contient le jour de reference', () {
      final series = NutritionCalculator.weeklySeries(
        const [],
        reference,
        weeks: 6,
      );
      final lastWeek = series.last.date;
      expect(
        lastWeek.isBefore(reference) || lastWeek.isAtSameMomentAs(reference),
        isTrue,
      );
      expect(reference.difference(lastWeek).inDays, lessThan(7));
    });
  });

  group('Moyenne par periode active', () {
    test('les periodes sans repas ne font pas chuter la moyenne', () {
      // Trois jours actifs a 60 g, quatre jours vides : la moyenne doit rester
      // a 60 g, et non tomber a 60 * 3 / 7.
      final series = [
        for (var i = 0; i < 3; i++)
          DailyBucket(
            date: DateTime(2026, 3, 10 + i),
            totals: const NutritionValues(carbs: 60),
            mealCount: 2,
          ),
        for (var i = 0; i < 4; i++)
          DailyBucket(
            date: DateTime(2026, 3, 13 + i),
            totals: NutritionValues.zero,
            mealCount: 0,
          ),
      ];

      final average = NutritionCalculator.averagePerActiveDay(series);
      expect(average.carbs, closeTo(60, 1e-9));
    });

    test(
      'la moyenne porte sur toutes les valeurs, pas seulement les glucides',
      () {
        final series = [
          DailyBucket(
            date: DateTime(2026, 3, 10),
            totals: const NutritionValues(kcal: 2000, carbs: 200, protein: 100),
            mealCount: 3,
          ),
          DailyBucket(
            date: DateTime(2026, 3, 11),
            totals: const NutritionValues(kcal: 1000, carbs: 100, protein: 50),
            mealCount: 2,
          ),
        ];

        final average = NutritionCalculator.averagePerActiveDay(series);
        expect(average.kcal, closeTo(1500, 1e-9));
        expect(average.carbs, closeTo(150, 1e-9));
        expect(average.protein, closeTo(75, 1e-9));
      },
    );

    test('sans periode active, la moyenne est nulle', () {
      final series = [
        DailyBucket(
          date: reference,
          totals: NutritionValues.zero,
          mealCount: 0,
        ),
      ];
      expect(NutritionCalculator.averagePerActiveDay(series).carbs, 0);
    });
  });

  group('Fourchette d\'incertitude des glucides', () {
    test('un aliment pese a la main produit une fourchette serree', () {
      final meal = mealAt(reference, [
        MealItem(food: food('Riz'), quantityG: 200, isEstimate: false),
      ]);

      final (low, high) = NutritionCalculator.carbsRange(meal);
      expect(low, lessThan(meal.totals.carbs));
      expect(high, greaterThan(meal.totals.carbs));
      // Sans estimation, la marge reste faible.
      expect((high - low) / meal.totals.carbs, lessThan(0.3));
    });

    test('une confiance faible elargit la fourchette', () {
      final sure = mealAt(reference, [
        MealItem(
          food: food('Riz'),
          quantityG: 200,
          confidence: 0.95,
          isEstimate: true,
        ),
      ]);
      final unsure = mealAt(reference, [
        MealItem(
          food: food('Riz'),
          quantityG: 200,
          confidence: 0.35,
          isEstimate: true,
        ),
      ]);

      final (sureLow, sureHigh) = NutritionCalculator.carbsRange(sure);
      final (unsureLow, unsureHigh) = NutritionCalculator.carbsRange(unsure);

      expect(unsureHigh - unsureLow, greaterThan(sureHigh - sureLow));
    });

    test('la fourchette est centree sur le total estime', () {
      final meal = mealAt(reference, [
        MealItem(
          food: food('Riz'),
          quantityG: 200,
          confidence: 0.8,
          isEstimate: true,
        ),
      ]);

      final (low, high) = NutritionCalculator.carbsRange(meal);
      final middle = (low + high) / 2;

      expect(middle, closeTo(meal.totals.carbs, 0.001));
    });

    test('la borne basse ne descend jamais sous zero', () {
      final meal = mealAt(reference, [
        MealItem(
          food: food('Riz', carbs: 0),
          quantityG: 200,
          confidence: 0.2,
          isEstimate: true,
        ),
      ]);

      final (low, high) = NutritionCalculator.carbsRange(meal);
      expect(low, 0);
      expect(high, 0);
    });
  });

  group('Progression vers les objectifs', () {
    test('aucun objectif defini ne produit aucune progression', () {
      const goals = DailyGoals.none;
      const summary = NutritionSummary(
        totals: NutritionValues(carbs: 50),
        mealCount: 1,
      );
      expect(NutritionCalculator.progress(goals, summary), isEmpty);
    });

    test('un objectif de glucides produit une progression', () {
      const goals = DailyGoals(carbsG: 200);
      const summary = NutritionSummary(
        totals: NutritionValues(carbs: 50),
        mealCount: 1,
      );

      final progress = NutritionCalculator.progress(goals, summary);
      expect(progress.length, 1);
      expect(progress.first.ratio, closeTo(0.25, 1e-9));
      expect(progress.first.remaining, closeTo(150, 1e-9));
      expect(progress.first.isExceeded, isFalse);
    });

    test('un depassement est signale et le remplissage reste borne', () {
      const goals = DailyGoals(carbsG: 100);
      const summary = NutritionSummary(
        totals: NutritionValues(carbs: 150),
        mealCount: 3,
      );

      final progress = NutritionCalculator.progress(goals, summary).first;
      expect(progress.isExceeded, isTrue);
      expect(progress.ratio, closeTo(1.5, 1e-9));
      expect(progress.clampedRatio, 1.0);
    });

    test('un objectif nul ne provoque pas de division par zero', () {
      const goals = DailyGoals(carbsG: 0);
      const summary = NutritionSummary(
        totals: NutritionValues(carbs: 50),
        mealCount: 1,
      );
      expect(NutritionCalculator.progress(goals, summary).first.ratio, 0);
    });
  });

  group('Repartition des glucides par repas', () {
    test('les repas de meme nom sont regroupes', () {
      final meals = [
        mealAt(reference, [item(100, carbs: 50)], name: 'Dejeuner'),
        mealAt(reference, [item(100, carbs: 50)], name: 'Dejeuner'),
        mealAt(reference, [item(100, carbs: 20)], name: 'Diner'),
      ];

      final breakdown = NutritionCalculator.carbsByMeal(meals);
      expect(breakdown['Dejeuner'], closeTo(100, 0.001));
      expect(breakdown['Diner'], closeTo(20, 0.001));
    });
  });
}
