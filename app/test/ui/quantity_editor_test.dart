import 'package:assiette/core/theme.dart';
import 'package:assiette/models/portion.dart';
import 'package:assiette/ui/widgets/quantity_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// L'editeur de quantite, quand une portion nommee est definie.
///
/// La demande est precise : lire « 2 gateaux », pas « 130 g ». Ces tests
/// tiennent les trois proprietes qui la rendent vraie, et qui peuvent chacune
/// casser separement :
///
///   1. ce qui **s'affiche** est le nombre d'unites, pas le poids ;
///   2. le pas des boutons + et − porte sur les **unites**, pas sur les
///      grammes — c'est ce que l'utilisateur attend d'un bouton a cote de
///      « 2 gateaux » ;
///   3. ce qui est **transmis** reste des grammes. Un `onChange` qui recevrait
///      `3` au lieu de `195` ferait enregistrer trois grammes de gateau, et le
///      total de glucides deviendrait faux sans que rien ne le signale.
///
/// Le point 3 est celui qui compte : c'est un test de modele qui l'avait
/// attrape une premiere fois, en affichant « 160 parts · 12800 g ». L'interface
/// ne doit pas pouvoir le reintroduire.
void main() {
  const gateau = Portion(label: 'gateau', grams: 65);

  late List<double> poids;
  late List<Portion?> portions;

  setUp(() {
    poids = [];
    portions = [];
  });

  Future<void> monte(
    WidgetTester tester, {
    required double quantite,
    Portion? portion,
    bool portionModifiable = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuantityEditor(
              quantityG: quantite,
              portion: portion,
              onChange: poids.add,
              onPortionChange: portionModifiable ? portions.add : null,
            ),
          ),
        ),
      ),
    );
  }

  /// Cible le champ dont le libelle est donne. Le libelle est rendu a
  /// l'interieur du `TextField` : on remonte donc depuis le texte.
  Finder champ(String libelle) =>
      find.ancestor(of: find.text(libelle), matching: find.byType(TextField));

  group('Sans portion, rien ne change', () {
    testWidgets('la quantite se lit en grammes', (tester) async {
      await monte(tester, quantite: 130);

      expect(find.text('130 g'), findsOneWidget);
      expect(find.text('Appuyez pour saisir le poids reel'), findsOneWidget);
    });

    testWidgets('le bouton + avance de dix grammes', (tester) async {
      await monte(tester, quantite: 130);

      await tester.tap(find.byTooltip('Augmenter de 10 grammes'));
      await tester.pump();

      expect(poids, [140.0]);
      expect(find.text('140 g'), findsOneWidget);
    });

    testWidgets('le bouton − recule de dix grammes', (tester) async {
      await monte(tester, quantite: 130);

      await tester.tap(find.byTooltip('Reduire de 10 grammes'));
      await tester.pump();

      expect(poids, [120.0]);
    });

    testWidgets('aucun raccourci d\'unite n\'est propose', (tester) async {
      await monte(tester, quantite: 130);

      expect(find.text('1 gateau'), findsNothing);
      expect(find.text('Retirer la portion'), findsNothing);
    });
  });

  group('Avec une portion, l\'unite prend la place du poids', () {
    testWidgets('la quantite se lit en gateaux, le poids reste visible', (
      tester,
    ) async {
      await monte(tester, quantite: 130, portion: gateau);

      expect(find.text('2 gateaux'), findsOneWidget);
      expect(find.text('130 g · appuyez pour corriger'), findsOneWidget);
      // Le poids seul ne doit plus etre le chiffre principal.
      expect(find.text('130 g'), findsNothing);
    });

    testWidgets('une seule unite s\'accorde au singulier', (tester) async {
      await monte(tester, quantite: 65, portion: gateau);

      // Deux fois « 1 gateau » : le chiffre principal et le raccourci.
      expect(find.text('1 gateau'), findsNWidgets(2));
      expect(find.text('1 gateaux'), findsNothing);
    });

    testWidgets('le bouton + ajoute une unite, pas dix grammes', (
      tester,
    ) async {
      await monte(tester, quantite: 130, portion: gateau);

      await tester.tap(find.byTooltip('Ajouter 1 gateau'));
      await tester.pump();

      // 3 unites a 65 g : c'est 195 g qui sont transmis, pas 3.
      expect(poids, [195.0]);
      expect(find.text('3 gateaux'), findsOneWidget);
    });

    testWidgets('le bouton − retire une unite', (tester) async {
      await monte(tester, quantite: 130, portion: gateau);

      await tester.tap(find.byTooltip('Retirer 1 gateau'));
      await tester.pump();

      expect(poids, [65.0]);
      expect(find.text('1 gateau'), findsNWidgets(2));
    });

    testWidgets('le raccourci ramene a exactement une unite', (tester) async {
      await monte(tester, quantite: 130, portion: gateau);

      await tester.tap(find.widgetWithText(ActionChip, '1 gateau'));
      await tester.pump();

      expect(poids, [65.0]);
      expect(find.text('65 g · appuyez pour corriger'), findsOneWidget);
    });

    testWidgets('une quantite a la virgule reste lisible', (tester) async {
      // 97,5 g : une unite et demie. L'arrondi d'affichage ne doit pas faire
      // disparaitre la demie, et le francais garde le singulier en dessous de
      // deux — « 1,5 gateau », pas « 1,5 gateaux ».
      await monte(tester, quantite: 97.5, portion: gateau);

      expect(find.text('1,5 gateau'), findsOneWidget);
      expect(find.text('97,5 g · appuyez pour corriger'), findsOneWidget);
    });
  });

  group('Definir et retirer une portion', () {
    testWidgets('le bouton n\'apparait que si la portion est modifiable', (
      tester,
    ) async {
      await monte(tester, quantite: 130, portionModifiable: false);

      expect(find.text('Definir une portion'), findsNothing);
    });

    testWidgets('definir une portion ne change pas la quantite saisie', (
      tester,
    ) async {
      await monte(tester, quantite: 130);

      await tester.tap(find.text('Definir une portion'));
      await tester.pumpAndSettle();

      // La boite porte le meme texte que le bouton qui l'ouvre : c'est le
      // champ « Nom de l'unite », propre a la boite, qui prouve qu'elle est
      // ouverte.
      expect(find.text('Nom de l\'unite'), findsOneWidget);

      // Le poids propose reprend la quantite deja saisie : definir une portion
      // ne doit jamais reecrire ce que l'utilisateur a tape.
      expect(find.widgetWithText(TextField, '130'), findsOneWidget);

      await tester.enterText(champ('Nom de l\'unite'), 'gateau');
      await tester.enterText(champ('Poids d\'une unite'), '65');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();

      expect(portions.length, 1);
      expect(portions.single!.label, 'gateau');
      expect(portions.single!.grams, 65);
      // Aucun poids n'a ete retransmis : la quantite n'a pas bouge.
      expect(poids, isEmpty);
    });

    testWidgets('un nom vide est refuse, la boite reste ouverte', (
      tester,
    ) async {
      await monte(tester, quantite: 130);

      await tester.tap(find.text('Definir une portion'));
      await tester.pumpAndSettle();

      await tester.enterText(champ('Nom de l\'unite'), '   ');
      await tester.enterText(champ('Poids d\'une unite'), '65');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();

      expect(portions, isEmpty);
      // La boite est restee ouverte : l'utilisateur corrige, il ne ressaisit
      // pas tout.
      expect(find.text('Nom de l\'unite'), findsOneWidget);
    });

    testWidgets('un poids nul est refuse', (tester) async {
      await monte(tester, quantite: 130);

      await tester.tap(find.text('Definir une portion'));
      await tester.pumpAndSettle();

      await tester.enterText(champ('Nom de l\'unite'), 'gateau');
      await tester.enterText(champ('Poids d\'une unite'), '0');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();

      expect(portions, isEmpty);
    });

    testWidgets('retirer la portion rend la lecture en grammes', (
      tester,
    ) async {
      await monte(tester, quantite: 130, portion: gateau);

      expect(find.text('1 gateau = 65 g'), findsOneWidget);

      await tester.tap(find.text('Retirer la portion'));
      await tester.pump();

      // `null` est bien transmis : c'est ce que la base enregistre pour
      // « plus de portion ».
      expect(portions, [null]);
    });
  });
}
