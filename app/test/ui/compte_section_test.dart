/// La section Compte, telle qu'elle s'affiche.
///
/// Pourquoi ces tests existent
/// ---------------------------
/// Le notifieur est eprouve a part, dans `state/compte_test.dart`. Ce qui est
/// mesure **ici**, c'est la composition : quelle branche s'affiche, et ce que
/// l'utilisateur peut reellement atteindre. Les tests d'interface de ce projet
/// ont deja trouve deux defauts qu'aucun test de modele ne pouvait voir.
///
/// Pourquoi la decision de compilation passe par un provider
/// ---------------------------------------------------------
/// `AppConfig` est une constante de compilation, et cette compilation-ci ne
/// porte pas de projet. Sans la couture `projetConfigureProvider`, la section
/// afficherait toujours la meme explication, et le formulaire comme l'etat
/// connecte seraient **inatteignables en test** — c'est-a-dire non eprouves.
///
/// Ce que ces tests ne peuvent pas mesurer
/// ---------------------------------------
/// Que le vrai trousseau se comporte comme le faux. Cela demande un appareil.
///
/// La synchronisation, vue depuis l'ecran
/// --------------------------------------
/// Le passage lui-meme est eprouve dans `state/synchronisation_test.dart`. Ce
/// qui est regarde ici est le **chemin de l'utilisateur** : le bouton n'apparait
/// qu'avec un compte, un passage abouti dit ce qu'il a fait, et un projet sans
/// tables le dit **en nommant les tables** — c'est le premier message qu'un
/// projet neuf affiche, et il doit designer l'etape qui manque plutot que
/// proposer de reessayer.
library;

import 'dart:convert';

import 'package:assiette/app.dart';
import 'package:assiette/data/ciqual_repository.dart';
import 'package:assiette/data/local/app_database.dart';
import 'package:assiette/models/app_settings.dart';
import 'package:assiette/models/session.dart';
import 'package:assiette/services/client_authentification.dart';
import 'package:assiette/services/secure_store.dart';
import 'package:assiette/services/transport_supabase.dart';
import 'package:assiette/state/providers.dart';
import 'package:assiette/ui/screens/settings_screen.dart';
import 'package:assiette/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../services/faux_trousseau.dart';

// --- fixtures ---------------------------------------------------------------

const String _adresse = 'personne@exemple.fr';
const String _utilisateur = 'user-1';
const String _clePublique = 'cle-publique-de-test';
const int _expireLe = 1790000000000;

Session _sessionRangee() => const Session(
  jetonAcces: 'jeton-acces',
  jetonRafraichissement: 'jeton-rafraichissement',
  expireLe: _expireLe,
  utilisateur: _utilisateur,
  adresse: _adresse,
);

Map<String, Object?> _corpsSession() => {
  'access_token': 'jeton-acces',
  'token_type': 'bearer',
  'expires_in': 3600,
  'expires_at': 1790000000,
  'refresh_token': 'jeton-rafraichissement',
  'user': {'id': _utilisateur, 'email': _adresse},
};

Map<String, Object?> _refus(String code) => {
  'code': 400,
  'error_code': code,
  'msg': 'peu importe',
};

http.Client _serveur(Object? corps, {int statut = 200}) => MockClient(
  (requete) async => http.Response(
    jsonEncode(corps),
    statut,
    headers: const {'Content-Type': 'application/json; charset=utf-8'},
  ),
);

/// Une session dont l'expiration est **dans une heure**.
///
/// `_sessionRangee` porte une date passee : elle sert a eprouver l'affichage du
/// compte, et c'est ce qu'il faut pour cela. Un passage qui partirait d'elle
/// tenterait d'abord un renouvellement — ce qui n'est pas ce que ces tests-ci
/// regardent.
Session _sessionValide() => Session(
  jetonAcces: 'jeton-acces',
  jetonRafraichissement: 'jeton-rafraichissement',
  expireLe: DateTime.now().millisecondsSinceEpoch + 3600000,
  utilisateur: _utilisateur,
  adresse: _adresse,
);

/// Un faux projet, pour les passages declenches depuis l'ecran.
///
/// Il repond aux deux familles de requetes : l'authentification, et PostgREST.
/// `tablesAbsentes` reproduit l'etat d'un projet neuf — celui ou les tables du
/// script n'ont pas encore ete creees.
class _Projet {
  _Projet({this.tablesAbsentes = false});

  final bool tablesAbsentes;

  /// Les jetons vus sur les requetes de donnees.
  final List<String> jetonsVus = [];

  http.Client get client => MockClient((requete) async {
    if (requete.url.path.contains('/auth/v1/token')) {
      return http.Response(
        jsonEncode(_corpsSession()),
        200,
        headers: const {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
    if (requete.method == 'HEAD') return http.Response('', 200);

    jetonsVus.add(requete.headers['Authorization'] ?? '<aucun>');
    if (tablesAbsentes) {
      return http.Response(
        jsonEncode({
          'code': 'PGRST205',
          'message': 'Could not find the table in the schema cache',
        }),
        404,
        headers: const {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
    return http.Response(
      '[]',
      200,
      headers: const {'Content-Type': 'application/json; charset=utf-8'},
    );
  });
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
  ///
  /// L'application est montee **entiere**, et non l'ecran seul : `context.palette`
  /// lit une extension de theme que seule la theme de l'application fournit.
  Future<SecureStore> monte(
    WidgetTester tester, {
    SecureStore? store,
    http.Client? serveur,
    bool projet = false,
    _Projet? synchronisation,
  }) async {
    final magasin = store ?? SecureStore(storage: FauxTrousseau());
    // Un ecran assez haut pour que la liste des reglages tienne en entier.
    //
    // Sans cela, il faut amener la section Compte dans la zone visible, et
    // `ensureVisible` l'aligne sur le **bord haut**, ou un bouton a moitie
    // recouvert se laisse manquer : mesure faite, deux tests sont tombes sur un
    // toucher qui n'atteignait pas sa cible. Un ecran haut supprime le probleme
    // au lieu de le contourner.
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(base),
        ciqualRepositoryProvider.overrideWithValue(ciqual),
        initialSettingsProvider.overrideWithValue(const AppSettings()),
        secureStoreProvider.overrideWithValue(magasin),
        // La couture qui rend la section eprouvable : cette compilation-ci ne
        // porte pas de projet, et sans cette surcharge le formulaire ne
        // s'afficherait jamais.
        projetConfigureProvider.overrideWithValue(projet),
        if (serveur != null)
          clientAuthentificationProvider.overrideWithValue(
            ClientAuthentification(
              url: 'https://projet.supabase.co',
              clePublique: _clePublique,
              client: serveur,
            ),
          ),
        // Le transport de donnees, avec une adresse et un client de
        // remplacement. Sans cette surcharge, le vrai transport partirait vers
        // l'adresse vide de cette compilation-ci, et le test mesurerait un echec
        // de configuration au lieu du passage.
        if (synchronisation != null)
          transportSynchronisationProvider.overrideWith((ref) {
            final session = ref.watch(compteProvider).value;
            if (session == null) {
              throw StateError('Aucun compte connecte.');
            }
            return TransportSupabase(
              url: 'https://projet.supabase.co',
              clePublique: _clePublique,
              utilisateur: session.utilisateur,
              jeton: session.jetonAcces,
              client: synchronisation.client,
            );
          }),
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

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Reglages'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return magasin;
  }

  /// Fait defiler la liste des reglages jusqu'a ce que la cible soit construite.
  ///
  /// La liste est paresseuse : une section n'est pas construite tant qu'elle
  /// n'est pas approchee. Sans ce defilement, elle est introuvable — et non
  /// absente. L'ecran etant haut, la cible est generalement deja construite et
  /// l'appel ne fait rien.
  ///
  /// On n'ajoute **pas** `ensureVisible` : il aligne la cible sur le bord haut
  /// de la zone defilante, ou elle se laisse manquer. Voir le commentaire de
  /// l'ecran haut, dans `monte`.
  Future<void> defiler(WidgetTester tester, Finder cible) async {
    await tester.scrollUntilVisible(
      cible,
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

  /// Les deux champs de la section Compte, dans l'ordre d'affichage.
  Finder champs() => find.descendant(
    of: find.ancestor(
      of: find.text('Compte'),
      matching: find.byType(SectionCard),
    ),
    matching: find.byType(TextField),
  );

  /// Declenche un passage, et attend qu'il ait rendu la main.
  ///
  /// `pump` seul ne suffit pas, et c'est une **mesure**, pas une precaution :
  /// apres dix tours, l'ecran affichait encore « Passage en cours... ». Un
  /// passage fait de vrais echanges — la base SQLite repond depuis un isolat, et
  /// le faux projet depuis la boucle d'evenements — que le temps simule de
  /// `pump` n'avance pas. `runAsync` rend la main au vrai temps pour la duree
  /// demandee.
  ///
  /// L'attente est **bornee et conditionnelle** : elle s'arrete des que le
  /// passage a rendu la main. Si elle ne s'arretait jamais, les assertions qui
  /// suivent tomberaient sur « Passage en cours... », ce qui est le bon
  /// diagnostic — un test qui attend sans borne, lui, ne dirait rien.
  Future<void> lancerLePassage(WidgetTester tester) async {
    await tester.tap(find.text('Synchroniser maintenant'));
    await tester.pump();

    for (var tour = 0; tour < 50; tour++) {
      if (find.text('Passage en cours...').evaluate().isEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  testWidgets(
    'sans projet, l\'ecran explique au lieu de proposer un formulaire',
    (tester) async {
      await monte(tester);

      await defiler(tester, find.textContaining('compile sans projet'));

      expect(find.textContaining('compile sans projet'), findsOneWidget);
      // Le garde-fou du test : sans ces deux lignes, il passerait aussi sur un
      // ecran vide. Proposer une saisie qui ne peut pas aboutir ferait porter a
      // l'utilisateur la responsabilite d'une erreur de compilation.
      expect(find.text('Adresse electronique'), findsNothing);
      expect(find.text('Se connecter'), findsNothing);
    },
  );

  testWidgets('avec un projet, le formulaire est propose', (tester) async {
    await monte(tester, projet: true);

    await defiler(tester, find.text('Se connecter'));

    expect(find.text('Adresse electronique'), findsOneWidget);
    expect(find.text('Mot de passe'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
    expect(champs(), findsNWidgets(2));
  });

  testWidgets('une session rangee affiche de quel compte il s\'agit', (
    tester,
  ) async {
    final magasin = SecureStore(storage: FauxTrousseau());
    await magasin.ecrireSession(_sessionRangee());

    await monte(tester, store: magasin, projet: true);

    await defiler(tester, find.text('Se deconnecter'));

    expect(find.text('Connecte : $_adresse'), findsOneWidget);
    expect(find.text('Se deconnecter'), findsOneWidget);
    // Un compte connecte ne propose pas de se connecter : les deux etats ne
    // doivent jamais cohabiter, sinon on ne sait plus lequel fait foi.
    expect(find.text('Se connecter'), findsNothing);
  });

  testWidgets('un refus affiche le message du serveur, et ne garde rien', (
    tester,
  ) async {
    final magasin = await monte(
      tester,
      projet: true,
      serveur: _serveur(_refus('invalid_credentials'), statut: 400),
    );

    await defiler(tester, find.text('Se connecter'));
    await tester.enterText(champs().at(0), _adresse);
    await tester.enterText(champs().at(1), 'faux');
    await tester.tap(find.text('Se connecter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Le message vient de `failures.dart`, intact : le client distingue des
    // identifiants refuses d'une session refusee, et cette distinction doit
    // survivre jusqu'a l'ecran. Dire « reconnectez-vous » a quelqu'un qui est en
    // train d'essayer de se connecter ne lui apprendrait rien.
    expect(
      find.textContaining('Adresse ou mot de passe incorrect'),
      findsOneWidget,
    );
    // Rien n'a ete range : une session de secours ferait croire a une connexion
    // qui n'existe pas.
    expect(await magasin.lireSession(), isNull);
  });

  testWidgets('la deconnexion ramene le formulaire', (tester) async {
    final magasin = SecureStore(storage: FauxTrousseau());
    await magasin.ecrireSession(_sessionRangee());

    await monte(tester, store: magasin, projet: true);

    await defiler(tester, find.text('Se deconnecter'));
    await tester.tap(find.text('Se deconnecter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(await magasin.lireSession(), isNull);
    await defiler(tester, find.text('Se connecter'));
    expect(find.text('Se connecter'), findsOneWidget);
  });

  testWidgets('une connexion reussie affiche le compte, sans redemander', (
    tester,
  ) async {
    // Le seul test qui traverse la chaine entiere : le geste, le notifieur, le
    // client, le serveur, le trousseau, l'etat, et l'ecran. Chaque morceau est
    // eprouve a part ; ce qui se mesure ici, c'est qu'ils sont **branches**.
    final magasin = await monte(
      tester,
      projet: true,
      serveur: _serveur(_corpsSession()),
    );

    await defiler(tester, find.text('Se connecter'));
    await tester.enterText(champs().at(0), _adresse);
    await tester.enterText(champs().at(1), 'mot-de-passe-de-test');
    await tester.tap(find.text('Se connecter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(await magasin.lireSession(), isNotNull);
    await defiler(tester, find.text('Se deconnecter'));
    expect(find.text('Connecte : $_adresse'), findsOneWidget);
  });

  // --- la synchronisation, vue depuis l'ecran -------------------------------

  testWidgets('sans compte, aucune synchronisation n\'est proposee', (
    tester,
  ) async {
    await monte(tester, projet: true);

    await defiler(tester, find.text('Se connecter'));

    // Le bouton n'existe qu'avec une session : le proposer sans compte ferait
    // partir un passage qui n'aurait aucun jeton a presenter, et l'utilisateur
    // lirait un refus la ou il n'a rien a faire de plus que se connecter.
    expect(find.text('Synchroniser maintenant'), findsNothing);
  });

  testWidgets('un compte connecte propose de synchroniser', (tester) async {
    final magasin = SecureStore(storage: FauxTrousseau());
    await magasin.ecrireSession(_sessionValide());

    await monte(tester, store: magasin, projet: true);

    await defiler(tester, find.text('Synchroniser maintenant'));

    expect(find.text('Synchroniser maintenant'), findsOneWidget);
    // L'ecran dit ce qu'il n'a pas encore fait, au lieu de laisser croire a un
    // passage qui aurait eu lieu.
    expect(
      find.textContaining('Aucun passage n\'a encore eu lieu'),
      findsOneWidget,
    );
  });

  testWidgets('un passage abouti dit ce qu\'il a fait', (tester) async {
    final magasin = SecureStore(storage: FauxTrousseau());
    await magasin.ecrireSession(_sessionValide());
    final projet = _Projet();

    await monte(tester, store: magasin, projet: true, synchronisation: projet);

    await defiler(tester, find.text('Synchroniser maintenant'));
    await lancerLePassage(tester);

    // Le jeton de la session est bien celui qui part : sans cela, le passage
    // aurait ete refuse table par table, et le message l'aurait dit.
    expect(projet.jetonsVus, isNotEmpty);
    expect(projet.jetonsVus.toSet(), {'Bearer jeton-acces'});
    expect(find.textContaining('Tout est deja a jour'), findsOneWidget);
  });

  testWidgets('un projet sans tables le dit, en nommant les tables', (
    tester,
  ) async {
    final magasin = SecureStore(storage: FauxTrousseau());
    await magasin.ecrireSession(_sessionValide());
    final projet = _Projet(tablesAbsentes: true);

    await monte(tester, store: magasin, projet: true, synchronisation: projet);

    await defiler(tester, find.text('Synchroniser maintenant'));
    await lancerLePassage(tester);

    // Le message **d'installation**, et non un conseil de reessayer : aucune
    // tentative ne creera une table. C'est le premier message qu'un projet neuf
    // affiche, donc celui qui doit designer l'etape manquante.
    expect(
      find.textContaining('Les tables du projet n\'existent pas encore'),
      findsNWidgets(6),
      reason: 'chaque table en echec est nommee, aucune n\'est tue',
    );
    // Les tables sont nommees en clair, pas en vocabulaire de base de donnees.
    expect(find.textContaining('Repas : '), findsOneWidget);
    expect(find.textContaining('Pesees : '), findsOneWidget);
  });
}
