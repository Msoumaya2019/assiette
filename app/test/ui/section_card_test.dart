import 'package:assiette/core/theme.dart';
import 'package:assiette/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Le `trailing` d'une `SectionCard` doit accepter n'importe quel widget —
/// bouton plein compris.
///
/// ## Le defaut, et pourquoi il merite un test a lui seul
///
/// Le theme demande aux boutons pleins `minimumSize: Size.fromHeight(54)`, ce
/// qui signifie « au moins toute la largeur ». Un `Row` presente a ses enfants
/// **non flexibles** une largeur **non bornee**, pour qu'ils se dimensionnent
/// sur leur contenu. Les deux ensemble donnent une demande irrealisable, et
/// Flutter leve `BoxConstraints forces an infinite width`.
///
/// Le defaut ne se voyait nulle part avant l'ecran de suivi du poids, parce
/// qu'aucune carte n'avait encore de bouton plein en `trailing`. Il ne se
/// voyait pas non plus a la compilation, ni a l'analyse statique : il fallait
/// **construire** la carte pour qu'il tombe. Mesure, avant correctif : une
/// `SectionCard` avec un bouton en `trailing`, dans une simple `ListView`,
/// produisait vingt exceptions de rendu.
///
/// Ce fichier tient donc deux proprietes a la fois : le `trailing` accepte un
/// bouton plein, et il continue d'accepter tout le reste.
void main() {
  Future<void> monte(WidgetTester tester, Widget carte) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: ListView(children: [carte])),
      ),
    );
    await tester.pump();
  }

  Widget carte({Widget? trailing, Widget? enfant}) => SectionCard(
    title: 'Courbe',
    subtitle: 'Une seule pesee pour l\'instant',
    trailing: trailing,
    child: enfant ?? const SizedBox.shrink(),
  );

  group('Un bouton plein dans le trailing', () {
    testWidgets('ne fait pas tomber le rendu', (tester) async {
      await monte(
        tester,
        carte(
          trailing: FilledButton.tonalIcon(
            onPressed: () {},
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Peser'),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Peser'), findsOneWidget);
      expect(find.text('Courbe'), findsOneWidget);
      expect(find.text('Une seule pesee pour l\'instant'), findsOneWidget);
    });

    testWidgets('garde la hauteur de la cible tactile', (tester) async {
      await monte(
        tester,
        carte(
          trailing: FilledButton(onPressed: () {}, child: const Text('Peser')),
        ),
      );

      // Le theme impose 54 de haut. Borner la **largeur** ne doit pas
      // retrecir la hauteur : une cible tactile trop plate se rate.
      final taille = tester.getSize(find.widgetWithText(FilledButton, 'Peser'));
      expect(taille.height, greaterThanOrEqualTo(48));
    });

    testWidgets('se dimensionne sur son contenu, pas sur la carte', (
      tester,
    ) async {
      await monte(
        tester,
        carte(
          trailing: FilledButton(onPressed: () {}, child: const Text('Peser')),
        ),
      );

      // Sans borne, la largeur demandee etait infinie. Elle doit maintenant
      // rester celle du libelle, et laisser la place au titre.
      final bouton = tester.getSize(find.widgetWithText(FilledButton, 'Peser'));
      final carteLargeur = tester.getSize(find.byType(SectionCard)).width;
      expect(bouton.width, lessThan(carteLargeur));
      expect(bouton.width, greaterThan(0));
    });

    testWidgets('un bouton bordé passe aussi', (tester) async {
      await monte(
        tester,
        carte(
          trailing: OutlinedButton(
            onPressed: () {},
            child: const Text('Mesurer'),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Mesurer'), findsOneWidget);
    });
  });

  group('Ce qui n\'est pas un bouton plein reste intact', () {
    testWidgets('un texte', (tester) async {
      await monte(tester, carte(trailing: const Text('Tout voir')));

      expect(tester.takeException(), isNull);
      expect(find.text('Tout voir'), findsOneWidget);
    });

    testWidgets('un bouton texte, dont le theme ne borne pas la largeur', (
      tester,
    ) async {
      await monte(
        tester,
        carte(
          trailing: TextButton(
            onPressed: () {},
            child: const Text('Tout voir'),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Tout voir'), findsOneWidget);
    });

    testWidgets('un bouton icone, courant en fin de ligne', (tester) async {
      await monte(
        tester,
        carte(
          trailing: IconButton(
            onPressed: () {},
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Modifier',
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Modifier'), findsOneWidget);
    });

    testWidgets('une carte sans trailing reste inchangee', (tester) async {
      await monte(tester, carte(enfant: const Text('Contenu')));

      expect(tester.takeException(), isNull);
      expect(find.text('Contenu'), findsOneWidget);
    });
  });

  group('Le contenu de la carte est independant du trailing', () {
    testWidgets('un enfant haut ne change pas le comportement du trailing', (
      tester,
    ) async {
      // C'est le cas reel : la courbe fait 240 de haut, et c'est en
      // l'ajoutant qu'on decouvrait le defaut sur l'ecran de suivi du poids.
      await monte(
        tester,
        carte(
          trailing: FilledButton.tonalIcon(
            onPressed: () {},
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Peser'),
          ),
          enfant: const SizedBox(
            height: 240,
            child: ColoredBox(color: Color(0xFFEEEEEE)),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Peser'), findsOneWidget);
    });
  });
}
