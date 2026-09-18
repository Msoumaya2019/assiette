import 'package:assiette/models/nutrition_values.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NutritionValues.forGrams', () {
    test('met a l\'echelle proportionnellement au poids', () {
      const values = NutritionValues(kcal: 200, carbs: 50, protein: 10, fat: 5, fiber: 4, salt: 1);

      final half = values.forGrams(50);
      expect(half.carbs, closeTo(25, 0.001));
      expect(half.kcal, closeTo(100, 0.001));
      expect(half.protein, closeTo(5, 0.001));
      expect(half.fiber, closeTo(2, 0.001));
    });

    test('une quantite nulle donne des valeurs nulles', () {
      const values = NutritionValues(kcal: 200, carbs: 50);
      expect(values.forGrams(0).carbs, 0);
      expect(values.forGrams(0).kcal, 0);
    });

    test('une quantite negative est traitee comme nulle', () {
      const values = NutritionValues(carbs: 50);
      expect(values.forGrams(-30).carbs, 0);
    });

    test('une quantite superieure a 100 g depasse la valeur de reference', () {
      const values = NutritionValues(carbs: 20);
      expect(values.forGrams(250).carbs, closeTo(50, 0.001));
    });

    test('100 g restitue exactement la valeur de reference', () {
      const values = NutritionValues(kcal: 137.5, carbs: 22.25, protein: 8.1, fat: 3.3, fiber: 2.2);
      final same = values.forGrams(100);

      expect(same.kcal, closeTo(137.5, 1e-9));
      expect(same.carbs, closeTo(22.25, 1e-9));
      expect(same.protein, closeTo(8.1, 1e-9));
      expect(same.fat, closeTo(3.3, 1e-9));
      expect(same.fiber, closeTo(2.2, 1e-9));
    });

    test('l\'arrondi ne derive pas apres plusieurs changements de portion', () {
      const values = NutritionValues(carbs: 63.7);

      // L'utilisateur ajuste plusieurs fois la quantite : le total doit
      // toujours etre recalcule depuis les valeurs pour 100 g, jamais cumule.
      var quantity = 180.0;
      for (final factor in [0.5, 2.0, 1.25, 0.8]) {
        quantity *= factor;
        expect(values.forGrams(quantity).carbs, closeTo(63.7 * quantity / 100, 1e-9));
      }
    });
  });

  group('NutritionValues addition', () {
    test('additionne composant par composant', () {
      const a = NutritionValues(kcal: 100, carbs: 20, sugars: 5, protein: 3, fat: 2, fiber: 1, salt: 0.2);
      const b = NutritionValues(kcal: 250, carbs: 10, sugars: 1, protein: 15, fat: 12, fiber: 3, salt: 0.8);

      final sum = a + b;

      expect(sum.kcal, 350);
      expect(sum.carbs, 30);
      expect(sum.sugars, 6);
      expect(sum.protein, 18);
      expect(sum.fat, 14);
      expect(sum.fiber, 4);
      expect(sum.salt, closeTo(1.0, 1e-9));
    });

    test('la soustraction est l\'inverse de l\'addition', () {
      const a = NutritionValues(kcal: 300, carbs: 40);
      const b = NutritionValues(kcal: 120, carbs: 15);

      final result = (a + b) - b;

      expect(result.kcal, closeTo(a.kcal, 1e-9));
      expect(result.carbs, closeTo(a.carbs, 1e-9));
    });

    test('la somme d\'une liste vide est nulle', () {
      expect(NutritionValues.sum(const []).carbs, 0);
      expect(NutritionValues.sum(const []).isNotEmpty, isFalse);
    });

    test('la somme d\'une liste correspond a l\'addition successive', () {
      const values = [
        NutritionValues(carbs: 12.5),
        NutritionValues(carbs: 30),
        NutritionValues(carbs: 7.25),
      ];

      expect(NutritionValues.sum(values).carbs, closeTo(49.75, 1e-9));
    });
  });

  group('Indicateurs derives', () {
    test('la part des sucres est bornee entre 0 et 1', () {
      expect(const NutritionValues(carbs: 100, sugars: 50).sugarShare, closeTo(0.5, 1e-9));
      expect(const NutritionValues(carbs: 0, sugars: 0).sugarShare, 0);
      // Donnee incoherente : la part reste bornee plutot que de depasser 1.
      expect(const NutritionValues(carbs: 10, sugars: 30).sugarShare, 1.0);
    });

    test('une energie coherente avec les macronutriments n\'est pas signalee', () {
      // 20 g de glucides + 10 g de proteines + 10 g de lipides = 80 + 40 + 90 = 210 kcal
      const values = NutritionValues(kcal: 210, carbs: 20, protein: 10, fat: 10);
      expect(values.energyIsInconsistent, isFalse);
    });

    test('une energie tres eloignee des macronutriments est signalee', () {
      const values = NutritionValues(kcal: 500, carbs: 20, protein: 10, fat: 10);
      expect(values.energyIsInconsistent, isTrue);
    });

    test('une donnee sans energie n\'est jamais signalee comme incoherente', () {
      expect(const NutritionValues(carbs: 20, protein: 5).energyIsInconsistent, isFalse);
      expect(NutritionValues.zero.energyIsInconsistent, isFalse);
    });
  });

  group('Serialisation', () {
    test('un aller-retour JSON conserve toutes les valeurs', () {
      const original = NutritionValues(
        kcal: 412.5,
        carbs: 66.3,
        sugars: 24.1,
        starch: 30.2,
        protein: 7.8,
        fat: 12.5,
        saturatedFat: 4.2,
        fiber: 5.4,
        salt: 0.62,
      );

      final restored = NutritionValues.fromJson(original.toJson());

      expect(restored.kcal, closeTo(original.kcal, 1e-9));
      expect(restored.carbs, closeTo(original.carbs, 1e-9));
      expect(restored.sugars, closeTo(original.sugars, 1e-9));
      expect(restored.starch, closeTo(original.starch, 1e-9));
      expect(restored.protein, closeTo(original.protein, 1e-9));
      expect(restored.fat, closeTo(original.fat, 1e-9));
      expect(restored.saturatedFat, closeTo(original.saturatedFat, 1e-9));
      expect(restored.fiber, closeTo(original.fiber, 1e-9));
      expect(restored.salt, closeTo(original.salt, 1e-9));
    });

    test('les cles absentes valent zero', () {
      final values = NutritionValues.fromJson(const {'carbs': 12});
      expect(values.carbs, 12);
      expect(values.kcal, 0);
      expect(values.protein, 0);
    });

    test('une valeur textuelle numerique est acceptee', () {
      final values = NutritionValues.fromJson(const {'carbs': '18.5'});
      expect(values.carbs, closeTo(18.5, 1e-9));
    });

    test('une valeur textuelle non numerique retombe a zero', () {
      final values = NutritionValues.fromJson(const {'carbs': 'non mesure'});
      expect(values.carbs, 0);
    });
  });
}
