import 'package:assiette/models/apercu_aliment.dart';
import 'package:assiette/models/food.dart';
import 'package:assiette/models/nutrition_values.dart';
import 'package:assiette/models/portion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 12 g de glucides et 96 kcal pour 100 g : les valeurs d'un pot de yaourt.
  const yaourt = Food(
    name: 'Yaourt nature',
    per100g: NutritionValues(kcal: 96, carbs: 12, protein: 4, fat: 3),
    source: FoodSource.openFoodFacts,
    servingSizeG: 125,
    servingLabel: '1 pot (125 g)',
  );

  const pot = Portion(label: 'pot', grams: 125);

  group('Valeurs et unite d\'un apercu', () {
    test('sans portion, les valeurs restent celles des 100 g', () {
      final apercu = apercuDePortion(yaourt, null);
      expect(apercu.valeurs.carbs, 12);
      expect(apercu.valeurs.kcal, 96);
      expect(apercu.reference, 'pour 100 g');
    });

    test('avec une portion, les valeurs portent sur une unite', () {
      final apercu = apercuDePortion(yaourt, pot);
      // 125 g d'un aliment a 12 g pour 100 g en contiennent 15.
      expect(apercu.valeurs.carbs, closeTo(15, 0.001));
      expect(apercu.valeurs.kcal, closeTo(120, 0.001));
      expect(apercu.reference, 'pour 1 pot (125 g)');
    });

    test('le nombre et son unite ne peuvent plus diverger', () {
      // Le defaut corrige : l'ecran produit annoncait « 12 g de glucides pour
      // 1 pot (125 g) » — le nombre des 100 g sous l'unite du pot, soit un
      // cinquieme de moins que la realite, sans que rien ne le signale. Le
      // nombre vient desormais du meme appel que l'unite, et les deux se
      // verifient ensemble : c'est le seul controle qui aurait attrape ca.
      final apercu = apercuDePortion(yaourt, pot);
      expect(apercu.reference, 'pour ${pot.etiquetteUnite}');
      expect(
        apercu.valeurs.carbs,
        closeTo(yaourt.per100g.carbs * pot.grams / 100, 0.001),
      );
    });

    test('une portion de 100 g laisse les valeurs inchangees', () {
      // Repere : un facteur d'echelle applique deux fois, ou pas du tout, se
      // verrait ici et nulle part ailleurs.
      final apercu = apercuDePortion(
        yaourt,
        const Portion(label: 'bol', grams: 100),
      );
      expect(apercu.valeurs.carbs, closeTo(yaourt.per100g.carbs, 0.001));
      expect(apercu.reference, 'pour 1 bol (100 g)');
    });

    test('une portion inexploitable ne fait pas afficher des zeros', () {
      // `forGrams` rend zero pour un poids nul : sans ce garde-fou, l'ecran
      // annoncerait « 0 g de glucides pour 0 g ».
      final apercu = apercuDePortion(
        yaourt,
        const Portion(label: 'pot', grams: 0),
      );
      expect(apercu.valeurs.carbs, yaourt.per100g.carbs);
      expect(apercu.reference, 'pour 100 g');
    });
  });
}
