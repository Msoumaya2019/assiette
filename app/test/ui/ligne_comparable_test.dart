import 'package:assiette/models/apercu_aliment.dart';
import 'package:assiette/models/food.dart';
import 'package:assiette/models/nutrition_values.dart';
import 'package:assiette/models/portion.dart';
import 'package:assiette/ui/widgets/common.dart';
import 'package:flutter_test/flutter_test.dart';

/// La ligne comparable des listes de resultats.
///
/// Une liste sert a comparer, mais deux produits dont l'un est chiffre pour un
/// pot et l'autre pour 100 g ne se comparent pas sans un calcul mental. Cette
/// ligne rend le chiffre comparable lisible, sans retirer la portion mise en
/// avant.
///
/// Le defaut qu'elle doit rendre impossible est celui qui a vecu : l'ecran
/// annoncait « 12 g de glucides pour 1 pot (125 g) », ou 12 est la valeur des
/// 100 g — le pot en contient 15. D'ou l'assertion qui compte : l'etiquette de
/// cette ligne est **toujours** celle des 100 g, jamais celle de la portion.
/// C'est precisement ce qu'un ecran se tromperait a ecrire, et c'est pour cela
/// que la ligne est construite une seule fois, pour les deux listes.
void main() {
  // 12 g de glucides pour 100 g, et un pot annonce a 125 g : le pot en
  // contient donc 15, et les deux chiffres ne se confondent pas.
  const yaourt = Food(
    name: 'Yaourt nature',
    per100g: NutritionValues(kcal: 96, carbs: 12, protein: 4, fat: 3),
    source: FoodSource.openFoodFacts,
    servingSizeG: 125,
    servingLabel: '1 pot (125 g)',
  );

  const pot = Portion(label: 'pot', grams: 125);

  test('la ligne porte le chiffre des 100 g, et le dit', () {
    expect(
      ligneComparable(apercuDePortion(yaourt, pot)),
      'soit 12 g de glucides pour 100 g',
    );
  });

  test('l\'etiquette de la ligne n\'est jamais celle de la portion', () {
    // Une ligne qui annoncerait « pour 1 pot (125 g) » en portant 12 — ou
    // l'inverse — serait le defaut d'origine, reproduit a l'identique. Les
    // deux assertions le ferment dans les deux sens.
    final apercu = apercuDePortion(yaourt, pot);
    final ligne = ligneComparable(apercu)!;

    expect(ligne, contains(reference100g));
    expect(ligne, isNot(contains(apercu.reference)));
    expect(ligne, contains('12'));
  });

  test('sans portion, il n\'y a pas de ligne', () {
    // L'apercu **est** alors la valeur des 100 g : une seconde ligne dirait
    // deux fois la meme chose, sous deux formes.
    expect(ligneComparable(apercuDePortion(yaourt, null)), isNull);
  });

  test('une portion inexploitable ne laisse pas de ligne', () {
    final apercu = apercuDePortion(
      yaourt,
      const Portion(label: 'pot', grams: 0),
    );
    expect(ligneComparable(apercu), isNull);
  });
}
