import 'package:assiette/core/formatters.dart';
import 'package:assiette/core/theme.dart';
import 'package:assiette/data/local/app_database.dart';
import 'package:assiette/models/app_settings.dart';
import 'package:assiette/models/suivi_poids.dart';
import 'package:assiette/state/providers.dart';
import 'package:assiette/ui/screens/poids_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// L'ecran de suivi du poids, pilote comme un utilisateur le pilote.
///
/// Cet ecran n'etait couvert qu'au niveau du modele et de la base. Or ce qui
/// peut casser ici n'est pas le calcul : c'est le **chemin** — une boite de
/// saisie qui n'enregistre rien, un onglet qui ne s'ouvre pas, un resume qui ne
/// se met pas a jour apres une pesee. Un test de modele vert ne dit rien de
/// tout cela.
///
/// Les tests passent par la vraie base SQLite (en memoire) et le vrai
/// fournisseur d'etat : ce qui est verifie est donc la chaine complete,
/// saisie → enregistrement → relecture → affichage.
void main() {
  late AppDatabase base;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    // Sans cet appel, les formats de date retombent silencieusement sur
    // l'anglais : l'ecran afficherait « September 21, 2026 ».
    await initializeFormatting();
  });

  // `databaseFactoryFfi` envoie **chaque appel dans un isolate separe**. Sous
  // `testWidgets`, qui fait tourner le corps du test dans une zone asynchrone
  // simulee, ce message n'est jamais delivre : le fournisseur ne se resout pas,
  // l'ecran reste sur son indicateur de chargement, et `pumpAndSettle` expire.
  // `databaseFactoryFfiNoIsolate` execute l'appel dans l'isolate courant, donc
  // par de simples microtaches — que la zone simulee, elle, traite.
  //
  // Mesure : avec `databaseFactoryFfi`, la lecture ne revient jamais (le test
  // tourne plus de six minutes). Les tests de base, eux, sont de simples
  // `test()` et n'ont pas cette contrainte.
  setUp(() async {
    base = AppDatabase(
      factory: databaseFactoryFfiNoIsolate,
      customPath: inMemoryDatabasePath,
    );
    await base.open();
  });

  tearDown(() => base.close());

  Future<void> monte(WidgetTester tester) async {
    // La fenetre de test par defaut fait 800x600 : ce n'est pas un telephone,
    // et l'historique d'un ecran de suivi n'y tient pas. Une liste paresseuse
    // ne construit alors pas les lignes du bas, et une assertion sur leur
    // contenu echouerait pour une raison qui n'a rien a voir avec ce qu'on
    // verifie. On donne donc a l'ecran une taille de telephone realiste.
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(base),
        initialSettingsProvider.overrideWithValue(const AppSettings()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('fr'),
          supportedLocales: const [Locale('fr'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const PoidsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Cible le champ dont le libelle est donne, en remontant depuis le texte.
  Finder champ(String libelle) =>
      find.ancestor(of: find.text(libelle), matching: find.byType(TextField));

  /// Saisit une pesee par l'interface : bouton, boite de dialogue, validation.
  Future<void> saisirPesee(WidgetTester tester, String poids) async {
    await tester.tap(find.text('Ajouter une pesee'));
    await tester.pumpAndSettle();

    expect(find.text('Nouvelle pesee'), findsOneWidget);
    await tester.enterText(champ('Poids'), poids);
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
  }

  group('Aucune pesee', () {
    testWidgets('l\'ecran invite a commencer, sans afficher de courbe', (
      tester,
    ) async {
      await monte(tester);

      expect(find.text('Suivi du poids'), findsOneWidget);
      expect(find.text('Aucune pesee'), findsOneWidget);
      expect(find.text('Ajouter une pesee'), findsOneWidget);
      // Une courbe sans point n'apprendrait rien : elle n'est pas dessinee.
      expect(find.text('Courbe'), findsNothing);
    });

    testWidgets('le resume affiche un tiret, pas un zero trompeur', (
      tester,
    ) async {
      await monte(tester);

      // « 0 kg » se lirait comme un poids mesure.
      expect(find.text('—'), findsOneWidget);
      expect(find.text('Dernier poids'), findsOneWidget);
    });

    testWidgets('aucun objectif n\'est propose d\'avance', (tester) async {
      await monte(tester);

      expect(find.text('Aucun objectif defini'), findsOneWidget);
      expect(find.text('Definir un objectif'), findsOneWidget);
      // L'application ne suggere aucune cible : elle le dit.
      expect(find.textContaining('ne propose aucune valeur'), findsOneWidget);
    });
  });

  group('Enregistrer une pesee', () {
    testWidgets(
      'la pesee apparait dans le resume, la courbe et l\'historique',
      (tester) async {
        await monte(tester);
        await saisirPesee(tester, '72,4');

        // Le chiffre principal.
        expect(find.text('72,4'), findsOneWidget);
        expect(find.text('kg'), findsOneWidget);
        // La courbe se dessine des la premiere pesee.
        expect(find.text('Courbe'), findsOneWidget);
        expect(find.text('Une seule pesee pour l\'instant'), findsOneWidget);
        // Et l'historique la reprend.
        expect(find.text('72,4 kg'), findsOneWidget);
        expect(find.text('1 pesee'), findsOneWidget);
        expect(find.text('Aucune pesee'), findsNothing);
      },
    );

    testWidgets('la virgule et le point sont acceptes pareillement', (
      tester,
    ) async {
      await monte(tester);
      await saisirPesee(tester, '72.4');

      expect(find.text('72,4'), findsOneWidget);
    });

    testWidgets('une remarque est conservee et affichee', (tester) async {
      await monte(tester);

      await tester.tap(find.text('Ajouter une pesee'));
      await tester.pumpAndSettle();
      await tester.enterText(champ('Poids'), '72,4');
      await tester.enterText(champ('Remarque (facultatif)'), 'a jeun');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(find.textContaining('a jeun'), findsOneWidget);
    });

    testWidgets('un poids nul est refuse, la boite reste ouverte', (
      tester,
    ) async {
      await monte(tester);

      await tester.tap(find.text('Ajouter une pesee'));
      await tester.pumpAndSettle();
      await tester.enterText(champ('Poids'), '0');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(find.text('Entrez un poids superieur a zero.'), findsOneWidget);
      expect(find.text('Nouvelle pesee'), findsOneWidget);
      // Rien n'a ete enregistre.
      expect(await base.pesees(), isEmpty);
    });

    testWidgets('annuler n\'enregistre rien', (tester) async {
      await monte(tester);

      await tester.tap(find.text('Ajouter une pesee'));
      await tester.pumpAndSettle();
      await tester.enterText(champ('Poids'), '72,4');
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(find.text('Aucune pesee'), findsOneWidget);
      expect(await base.pesees(), isEmpty);
    });

    testWidgets('deux pesees le meme jour ne font qu\'un point de courbe', (
      tester,
    ) async {
      // Regle du modele : un point par jour, le dernier. Deux pesees le meme
      // jour ne doivent donc pas fabriquer une « variation » — ce serait un
      // ecart de quelques heures presente comme une evolution.
      await monte(tester);
      await saisirPesee(tester, '72,4');

      await tester.tap(find.text('Peser'));
      await tester.pumpAndSettle();
      await tester.enterText(champ('Poids'), '70,2');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      // Le chiffre principal est bien le plus recent…
      expect(find.text('70,2'), findsOneWidget);
      // …mais la courbe ne compte qu'un point, donc aucune variation.
      expect(find.text('Une seule pesee pour l\'instant'), findsOneWidget);
      expect(find.textContaining('depuis le debut'), findsNothing);
      // Les deux pesees sont pourtant conservees : c'est l'affichage qui
      // choisit, pas l'enregistrement.
      expect(await base.pesees(), hasLength(2));
    });

    testWidgets('une pesee anterieure donne une variation, sans jugement', (
      tester,
    ) async {
      // La pesee d'hier est posee directement en base : passer par l'interface
      // obligerait a choisir une date dans le calendrier, et testerait le
      // calendrier de Flutter autant que cet ecran.
      await base.savePesee(
        Pesee(
          id: 'hier',
          le: DateTime.now().subtract(const Duration(days: 1)),
          poidsKg: 72.4,
        ),
      );

      await monte(tester);
      await tester.tap(find.text('Peser'));
      await tester.pumpAndSettle();
      await tester.enterText(champ('Poids'), '70,2');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(find.text('-2,2 kg depuis le debut'), findsOneWidget);
      // Le mot « perdu » ou « gagne » qualifierait le signe : l'application
      // affiche l'ecart, elle ne dit pas s'il est souhaitable.
      expect(find.textContaining('perdu'), findsNothing);
      expect(find.textContaining('gagne'), findsNothing);
    });

    testWidgets('supprimer une pesee la retire de l\'historique', (
      tester,
    ) async {
      await monte(tester);
      await saisirPesee(tester, '72,4');

      await tester.tap(find.byTooltip('Supprimer cette pesee'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();

      expect(find.text('Aucune pesee'), findsOneWidget);
      expect(await base.pesees(), isEmpty);
    });
  });

  group('Objectif de poids', () {
    testWidgets('un objectif defini s\'affiche sur la fiche et sur la courbe', (
      tester,
    ) async {
      await monte(tester);
      await saisirPesee(tester, '72,4');

      await tester.tap(find.text('Definir un objectif'));
      await tester.pumpAndSettle();

      expect(find.text('Objectif de poids'), findsOneWidget);
      await tester.enterText(champ('Poids vise'), '70');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();

      // La fiche de l'objectif, et la puce du resume.
      expect(find.text('70 kg'), findsOneWidget);
      expect(find.text('objectif 70 kg'), findsOneWidget);
      expect(find.text('Modifier l\'objectif'), findsOneWidget);
      expect(find.text('Aucun objectif defini'), findsNothing);
    });

    testWidgets('retirer l\'objectif ne touche pas aux pesees', (tester) async {
      await monte(tester);
      await saisirPesee(tester, '72,4');

      await tester.tap(find.text('Definir un objectif'));
      await tester.pumpAndSettle();
      await tester.enterText(champ('Poids vise'), '70');
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Retirer'));
      await tester.pumpAndSettle();

      expect(find.text('Aucun objectif defini'), findsOneWidget);
      expect(find.text('72,4'), findsOneWidget);
    });
  });

  group('Mensurations', () {
    testWidgets('l\'onglet s\'ouvre et annonce l\'absence de mesure', (
      tester,
    ) async {
      await monte(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(TabBar),
          matching: find.text('Mensurations'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('En centimetres, quand vous le souhaitez'),
        findsOneWidget,
      );
      expect(find.text('Aucune mesure enregistree.'), findsOneWidget);
      expect(find.text('Mesurer'), findsOneWidget);
    });

    testWidgets('une mesure enregistree apparait en tuile et en historique', (
      tester,
    ) async {
      await monte(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(TabBar),
          matching: find.text('Mensurations'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mesurer'));
      await tester.pumpAndSettle();

      expect(find.text('Nouvelle mesure'), findsOneWidget);
      // Le type par defaut, et sa precision annoncee.
      expect(find.text('Tour de taille'), findsOneWidget);
      await tester.enterText(champ('Valeur'), '82');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(find.text('82 cm'), findsOneWidget);
      expect(find.text('Tour de taille · 82 cm'), findsOneWidget);
      expect(find.text('1 mesure'), findsOneWidget);
      expect(find.text('Aucune mesure enregistree.'), findsNothing);
    });

    testWidgets('une valeur nulle est refusee', (tester) async {
      await monte(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(TabBar),
          matching: find.text('Mensurations'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mesurer'));
      await tester.pumpAndSettle();

      await tester.enterText(champ('Valeur'), '0');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(find.text('Entrez une valeur superieure a zero.'), findsOneWidget);
      expect(await base.mesures(), isEmpty);
    });
  });

  group('Ce qui reste sur l\'appareil', () {
    testWidgets('les pesees survivent a une relecture depuis la base', (
      tester,
    ) async {
      await monte(tester);
      await saisirPesee(tester, '72,4');

      // Ce qui a ete ecrit est bien ce qui sera relu au prochain lancement.
      // `pesees()` ne rend que les vivantes : une pierre tombale n'y figure
      // pas, ce qui est exactement la propriete a tenir.
      final relues = await base.pesees();
      expect(relues.length, 1);
      expect(relues.single.poidsKg, 72.4);
    });
  });
}
