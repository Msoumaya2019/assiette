import 'package:assiette/app.dart';
import 'package:assiette/data/ciqual_repository.dart';
import 'package:assiette/data/local/app_database.dart';
import 'package:assiette/models/app_settings.dart';
import 'package:assiette/state/providers.dart';
import 'package:assiette/ui/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Navigation et structure de l'application.
///
/// Ces tests montent l'application entiere, routeur compris, et n'utilisent
/// volontairement que `pump`, jamais `pumpAndSettle` : les ecrans lisent la
/// base, et une requete non encore terminee affiche un indicateur de chargement
/// qui tourne sans fin. Les assertions portent donc sur ce qui se construit de
/// facon synchrone — la barre de navigation, les actions de l'accueil, l'ecran
/// de secours — ce qui suffit a prouver que la navigation tient.
///
/// Les onglets sont montes dans un `IndexedStack` : les cinq ecrans restent
/// presents dans l'arbre meme quand ils ne sont pas visibles. On ne peut donc
/// pas conclure de la presence d'un texte quel onglet est actif — c'est
/// `selectedIndex` qui fait foi.
void main() {
  late AppDatabase base;
  late CiqualRepository ciqual;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    // La table de reference est embarquee : la charger ici verifie au passage
    // que l'actif est bien declare et analysable.
    ciqual = CiqualRepository();
    await ciqual.load();
  });

  setUp(() async {
    base = AppDatabase(
      factory: databaseFactoryFfi,
      customPath: inMemoryDatabasePath,
    );
    await base.open();
  });

  tearDown(() => base.close());

  Future<ProviderContainer> monte(
    WidgetTester tester, {
    String? adresseInitiale,
  }) async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(base),
        ciqualRepositoryProvider.overrideWithValue(ciqual),
        initialSettingsProvider.overrideWithValue(const AppSettings()),
      ],
    );
    addTearDown(container.dispose);

    // Naviguer avant la premiere image reproduit un lancement par un lien
    // invalide : la coquille de navigation n'a alors jamais ete construite.
    if (adresseInitiale != null) {
      container.read(routerProvider).go(adresseInitiale);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AssietteApp(),
      ),
    );
    // Une seule image suffit : tout ce qui est observe ci-dessous est construit
    // sans attendre le reseau ni la base.
    await tester.pump();
    return container;
  }

  /// Cible un libelle a l'interieur de la barre de navigation. Sans cela,
  /// « Historique » designerait aussi le titre de l'ecran correspondant.
  Finder onglet(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  int ongletActif(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  group('Coquille de navigation', () {
    testWidgets('les cinq onglets sont proposes, l\'accueil est actif', (
      tester,
    ) async {
      await monte(tester);

      expect(find.byType(NavigationBar), findsOneWidget);
      for (final label in const [
        'Accueil',
        'Historique',
        'Statistiques',
        'Favoris',
        'Reglages',
      ]) {
        expect(onglet(label), findsOneWidget, reason: 'onglet $label');
      }
      expect(ongletActif(tester), 0);
    });

    testWidgets('l\'accueil met en avant les trois actions principales', (
      tester,
    ) async {
      await monte(tester);

      // Exigence de conception : l'accueil reste simple, avec ces trois entrees
      // immediatement visibles.
      expect(find.text('Analyser mon repas'), findsOneWidget);
      expect(find.text('Scanner un produit'), findsOneWidget);
      expect(find.text('Rechercher'), findsOneWidget);
    });

    testWidgets('toucher un onglet change l\'onglet actif', (tester) async {
      await monte(tester);

      await tester.tap(onglet('Historique'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(ongletActif(tester), 1);

      await tester.tap(onglet('Reglages'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(ongletActif(tester), 4);

      // Revenir a l'accueil doit fonctionner aussi.
      await tester.tap(onglet('Accueil'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(ongletActif(tester), 0);
    });
  });

  group('Adresse inconnue', () {
    testWidgets('affiche un ecran de secours, jamais un ecran vide', (
      tester,
    ) async {
      await monte(tester, adresseInitiale: '/adresse-qui-nexiste-pas');
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Page introuvable'), findsOneWidget);
      expect(find.text('Cet ecran n\'existe pas.'), findsOneWidget);
    });

    testWidgets('l\'ecran de secours ramene a l\'accueil', (tester) async {
      await monte(tester, adresseInitiale: '/adresse-qui-nexiste-pas');
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('Revenir a l\'accueil'));
      await tester.pump();
      // Deux images : la premiere lance la transition, la seconde laisse le
      // routeur demonter l'ecran de secours.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // On retrouve la coquille de navigation et les actions de l'accueil :
      // aucune impasse.
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Analyser mon repas'), findsOneWidget);
      expect(find.text('Page introuvable'), findsNothing);
    });
  });

  group('Ecrans hors barre de navigation', () {
    testWidgets('Rechercher ouvre la recherche plein ecran', (tester) async {
      await monte(tester);

      await tester.tap(find.text('Rechercher'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Rechercher un aliment'), findsOneWidget);
    });
  });
}
