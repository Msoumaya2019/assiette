import 'package:assiette/app.dart';
import 'package:assiette/data/ciqual_repository.dart';
import 'package:assiette/data/local/app_database.dart';
import 'package:assiette/models/app_settings.dart';
import 'package:assiette/services/notification_service.dart';
import 'package:assiette/state/providers.dart';
import 'package:assiette/ui/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Activation des rappels et autorisation des notifications.
///
/// Le defaut couvert ici etait silencieux : le reglage s'activait, la
/// notification etait programmee, et rien n'arrivait jamais sur Android 13+ ou
/// sur iOS, faute d'autorisation demandee. Aucun message ne l'expliquait.
///
/// Ces tests echouent sur le code d'avant la correction, et c'est voulu : sans
/// appel a `requestPermission`, le compteur d'appels reste a zero et
/// l'interrupteur s'active malgre un refus.
class _EspionNotifications extends NotificationService {
  _EspionNotifications({required this.accorde});

  /// Ce que l'utilisateur repond a la demande d'autorisation.
  final bool accorde;

  /// Nombre de fois ou l'autorisation a ete demandee.
  int demandes = 0;

  @override
  Future<bool> requestPermission() async {
    demandes += 1;
    return accorde;
  }
}

void main() {
  late AppDatabase base;
  late CiqualRepository ciqual;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
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

  /// Monte l'application entiere et ouvre l'onglet des reglages.
  ///
  /// On n'utilise jamais `pumpAndSettle` : les autres onglets restent montes
  /// dans l'`IndexedStack` et lisent la base, ce qui laisserait tourner un
  /// indicateur de chargement sans fin.
  Future<_EspionNotifications> monte(
    WidgetTester tester, {
    required bool accorde,
  }) async {
    final espion = _EspionNotifications(accorde: accorde);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(base),
        ciqualRepositoryProvider.overrideWithValue(ciqual),
        initialSettingsProvider.overrideWithValue(const AppSettings()),
        notificationServiceProvider.overrideWithValue(espion),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AssietteApp(),
      ),
    );
    await tester.pump();

    // L'ecran est monte seul dans un `MaterialApp` : `context.palette` lit une
    // extension de theme que seule la theme de l'application fournit. Il faut
    // donc monter l'application entiere, puis ouvrir l'onglet des reglages —
    // les ecrans de l'`IndexedStack` restent presents mais seul l'onglet actif
    // repond aux touches.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Reglages'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return espion;
  }

  Finder interrupteur(String libelle) =>
      find.widgetWithText(SwitchListTile, libelle);

  bool estActif(WidgetTester tester, String libelle) =>
      tester.widget<SwitchListTile>(interrupteur(libelle)).value;

  const rappelRepas = 'Rappel pour renseigner un repas';
  const resumeJournee = 'Resume de la journee';

  /// Fait defiler la liste des reglages jusqu'a l'interrupteur vise.
  ///
  /// La liste est paresseuse : la section « Notifications » n'est pas construite
  /// tant qu'elle n'est pas approchee. Sans ce defilement, l'interrupteur est
  /// introuvable — et non absent.
  Future<void> defiler(WidgetTester tester, String libelle) async {
    await tester.scrollUntilVisible(
      interrupteur(libelle),
      300,
      // `.first` : l'ecran contient plusieurs zones defilantes (la liste, et
      // celles qu'abritent les cartes de section). La premiere est la liste
      // exterieure, celle qu'il faut faire defiler.
      scrollable: find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump();
  }

  Future<void> basculer(WidgetTester tester, String libelle) async {
    await defiler(tester, libelle);
    await tester.tap(interrupteur(libelle));
    // Une image pour lancer le traitement, une seconde pour laisser aboutir la
    // demande d'autorisation, qui est asynchrone.
    await tester.pump();
    await tester.pump();
    // L'enregistrement du reglage passe par un isolate. Sans temps reel, il
    // reste en attente et la fermeture de la base en fin de test echoue sur
    // « This database has already been closed ». Ce n'est pas un defaut de
    // l'application : c'est le harnais qui doit laisser le travail aboutir.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pump();
  }

  testWidgets('activer un rappel demande l\'autorisation', (tester) async {
    final espion = await monte(tester, accorde: true);

    await basculer(tester, rappelRepas);

    expect(
      espion.demandes,
      1,
      reason: 'l\'autorisation doit etre demandee avant d\'activer le rappel',
    );
  });

  testWidgets('autorisation accordee : le rappel s\'active', (tester) async {
    await monte(tester, accorde: true);

    await defiler(tester, rappelRepas);
    expect(estActif(tester, rappelRepas), isFalse);
    await basculer(tester, rappelRepas);

    expect(estActif(tester, rappelRepas), isTrue);
  });

  testWidgets('autorisation refusee : le rappel reste desactive', (
    tester,
  ) async {
    await monte(tester, accorde: false);

    await basculer(tester, rappelRepas);

    expect(
      estActif(tester, rappelRepas),
      isFalse,
      reason: 'un refus ne doit pas laisser croire que le rappel est actif',
    );
  });

  testWidgets('autorisation refusee : une explication est affichee', (
    tester,
  ) async {
    await monte(tester, accorde: false);

    await basculer(tester, rappelRepas);

    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.textContaining('Autorisez-les dans les reglages du telephone'),
      findsOneWidget,
    );
  });

  testWidgets('desactiver un rappel ne demande aucune autorisation', (
    tester,
  ) async {
    final espion = await monte(tester, accorde: true);

    // On active d'abord, ce qui consomme une demande.
    await basculer(tester, rappelRepas);
    expect(estActif(tester, rappelRepas), isTrue);
    expect(espion.demandes, 1);

    await basculer(tester, rappelRepas);

    expect(estActif(tester, rappelRepas), isFalse);
    expect(
      espion.demandes,
      1,
      reason: 'eteindre ne doit jamais rouvrir une demande d\'autorisation',
    );
  });

  testWidgets('le resume de la journee suit la meme regle', (tester) async {
    final espion = await monte(tester, accorde: false);

    await basculer(tester, resumeJournee);

    expect(espion.demandes, 1);
    expect(estActif(tester, resumeJournee), isFalse);
  });
}
