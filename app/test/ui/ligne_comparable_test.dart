import 'package:assiette/core/theme.dart';
import 'package:assiette/models/apercu_aliment.dart';
import 'package:assiette/models/food.dart';
import 'package:assiette/models/nutrition_values.dart';
import 'package:assiette/models/portion.dart';
import 'package:assiette/ui/widgets/common.dart';
import 'package:flutter/material.dart';
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
///
/// Les derniers tests montent `ApercuValeurs` — le bloc qui ecrit la ligne — et
/// regardent ce qu'il affiche. Ils ne sont pas un doublon des precedents : une
/// fonction juste que le bloc n'appelle pas laisse l'utilisateur sans chiffre
/// comparable, et aucun test de fonction ne peut le voir. Le banc le fabrique.
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

  /// Les valeurs sont rendues en `RichText`, pour que le chiffre soit plus gras
  /// que son libelle : `find.text` ne les voit donc pas, et on cherche dans le
  /// texte aplati.
  Finder texteRiche(String extrait) => find.byWidgetPredicate(
    (widget) =>
        widget is RichText && widget.text.toPlainText().contains(extrait),
  );

  Future<void> monte(WidgetTester tester, Apercu apercu) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: ApercuValeurs(apercu: apercu)),
      ),
    );
  }

  // Le defaut d'origine vivait **ici**, dans ce que l'ecran ecrivait : ces tests
  // le tiennent au niveau du widget, et non plus seulement de la fonction.
  group('Le bloc affiche', () {
    testWidgets('les valeurs de la portion, sous l\'unite de la portion', (
      tester,
    ) async {
      await monte(tester, apercuDePortion(yaourt, pot));

      expect(texteRiche('15 g glucides'), findsOneWidget);
      expect(find.text('pour 1 pot (125 g)'), findsOneWidget);
    });

    testWidgets('le chiffre comparable, et sous l\'unite des 100 g', (
      tester,
    ) async {
      await monte(tester, apercuDePortion(yaourt, pot));

      expect(find.text('soit 12 g de glucides pour 100 g'), findsOneWidget);
      // Le pot et les 100 g ne portent jamais la meme etiquette : c'est
      // exactement ce que l'ecran fautif faisait.
      expect(find.text('pour 100 g'), findsNothing);
    });

    testWidgets('rien de comparable quand l\'apercu est deja pour 100 g', (
      tester,
    ) async {
      await monte(tester, apercuDePortion(yaourt, null));

      expect(find.text('pour 100 g'), findsOneWidget);
      expect(find.textContaining('soit '), findsNothing);
      expect(texteRiche('12 g glucides'), findsOneWidget);
    });
  });
}
