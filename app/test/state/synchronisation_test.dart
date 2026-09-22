/// Le passage de synchronisation, du compte jusqu'au rapport.
///
/// Ce que ces tests mesurent
/// -------------------------
/// Le **vrai** `SynchronisationNotifier`, sur une vraie base SQLite, un faux
/// trousseau et un faux projet. Ce qui est mesure ici n'est pas la convergence —
/// `synchronisation_service_test.dart` la couvre, table par table — mais ce qui
/// la **declenche** : de quel compte elle part, avec quel jeton, et ce qui reste
/// quand elle echoue.
///
/// La regle qui a motive ce fichier
/// --------------------------------
/// **Le renouvellement d'un jeton perime precede la construction du service.**
/// Le transport est bati a partir de la session rangee ; un service lu avant le
/// renouvellement porterait le jeton perime, et **chaque table** serait refusee,
/// avec un message de session qui n'expliquerait pas pourquoi. Aucune relecture
/// ne voit cette faute : les deux ecritures sont justes, c'est leur **ordre** qui
/// compte. Seul l'en-tete reellement envoye les separe — c'est donc lui qui est
/// regarde.
///
/// La meme faute a une variante plus discrete : renouveler, puis **oublier de
/// publier** la session neuve. Le jeton part alors perime, sans qu'aucune ligne
/// de code ne soit fausse prise isolement. Le second point de mesure — le
/// trousseau porte le jeton neuf — attrape celle-la.
///
/// Ce que ces tests ne peuvent pas mesurer
/// ---------------------------------------
/// Que le projet accepte ces requetes. Le faux projet repond ce qu'on lui dit de
/// repondre : ce fichier etablit qu'on envoie le bon jeton au bon endroit, pas
/// que PostgREST en fait ce qu'on croit. Et le transport substitue ici est celui
/// du vrai fournisseur, avec une adresse et un client HTTP de remplacement : la
/// **couture** entre le compte et le transport, elle, est mesuree par la garde
/// du dernier groupe, qui interroge le vrai fournisseur.
library;

import 'dart:convert';
import 'dart:io';

import 'package:assiette/core/config.dart';
import 'package:assiette/core/failures.dart';
import 'package:assiette/data/local/app_database.dart';
import 'package:assiette/data/local/synchronisation_locale.dart';
import 'package:assiette/models/session.dart';
import 'package:assiette/models/synchronisation.dart';
import 'package:assiette/services/client_authentification.dart';
import 'package:assiette/services/secure_store.dart';
import 'package:assiette/services/transport_supabase.dart';
import 'package:assiette/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../services/faux_trousseau.dart';

// --- fixtures ---------------------------------------------------------------

const String _utilisateur = 'user-1';
const String _adresse = 'personne@exemple.fr';
const String _clePublique = 'cle-publique-de-test';
const String _adresseDuProjet = 'https://projet.supabase.co';

/// Le jeton range dans le trousseau, et celui que le serveur rend ensuite.
const String _jetonRange = 'jeton-range';
const String _jetonNeuf = 'jeton-neuf';

/// Une expiration **dans le passe**, et volontairement pas zero.
///
/// Zero veut dire « inconnu » et ne declenche aucun renouvellement — voir
/// `Session.estExpireeA`. Une session perimee doit donc porter une date non
/// nulle, sans quoi ce fichier mesurerait l'inverse de ce qu'il annonce.
const int _perime = 1000;

/// Une expiration dans une heure.
int _valide() => DateTime.now().millisecondsSinceEpoch + 3600000;

Session _session({required int expireLe, String jeton = _jetonRange}) =>
    Session(
      jetonAcces: jeton,
      jetonRafraichissement: 'rafraichissement-range',
      expireLe: expireLe,
      utilisateur: _utilisateur,
      adresse: _adresse,
    );

Map<String, Object?> _corpsSession() => {
  'access_token': _jetonNeuf,
  'refresh_token': 'rafraichissement-neuf',
  'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
  'user': {'id': _utilisateur, 'email': _adresse},
};

http.Response _json(Object? corps, {int statut = 200}) => http.Response(
  jsonEncode(corps),
  statut,
  headers: const {'Content-Type': 'application/json; charset=utf-8'},
);

/// Un faux projet : l'authentification d'un cote, PostgREST de l'autre.
class _Projet {
  _Projet({this.refusDuRafraichissement = false});

  final bool refusDuRafraichissement;

  /// Les en-tetes `Authorization` vus sur les requetes de **donnees**.
  ///
  /// Ce que la regle d'ordre se lit : le renouvellement a ses propres en-tetes
  /// (`apikey` seul), donc compter les jetons ici mesure ce qui part vraiment
  /// vers les tables, et rien d'autre.
  final List<String> jetonsVus = [];

  bool rafraichissementDemande = false;

  http.Client get client => MockClient(_recevoir);

  Future<http.Response> _recevoir(http.Request requete) async {
    if (requete.url.path.contains('/auth/v1/token')) {
      rafraichissementDemande = true;
      if (refusDuRafraichissement) {
        return _json({
          'code': 400,
          'error_code': 'refresh_token_not_found',
          'msg': 'peu importe',
        }, statut: 400);
      }
      return _json(_corpsSession());
    }

    // `heureServeur` interroge la racine en `HEAD` : ce n'est pas une lecture de
    // donnees, et l'y compter ferait croire a une requete de table.
    if (requete.method == 'HEAD') return http.Response('', 200);

    jetonsVus.add(requete.headers['Authorization'] ?? '<aucun>');
    return _json(const []);
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory repertoire;
  late AppDatabase base;
  late SecureStore store;

  setUp(() async {
    repertoire = Directory.systemTemp.createTempSync('assiette-etat-sync');
    base = AppDatabase(
      factory: databaseFactoryFfi,
      customPath: p.join(repertoire.path, 'local.db'),
    );
    await base.open();
    store = SecureStore(storage: FauxTrousseau());
  });

  tearDown(() async {
    await base.close();
    repertoire.deleteSync(recursive: true);
  });

  ProviderContainer conteneur({_Projet? projet}) {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(base),
        secureStoreProvider.overrideWithValue(store),
        // `flutter test` est lance sans `--dart-define`, localement comme dans
        // `ci.yml` : sans cette surcharge, le transport refuserait de se
        // construire et **aucun** passage ne serait mesurable. La garde
        // elle-meme est mesuree par le dernier groupe, sans surcharge.
        projetConfigureProvider.overrideWithValue(true),
        if (projet != null) ...[
          clientAuthentificationProvider.overrideWithValue(
            ClientAuthentification(
              url: _adresseDuProjet,
              clePublique: _clePublique,
              client: projet.client,
            ),
          ),
          // Le transport du vrai fournisseur, avec une adresse et un client HTTP
          // de remplacement. La couture — session lue, jeton retenu — est
          // **recopiee** de `transportSynchronisationProvider` : si elle y
          // changeait, ce test continuerait de passer. C'est pourquoi le
          // dernier groupe interroge le vrai fournisseur, qui n'est eprouvable
          // ici que par ses refus.
          transportSynchronisationProvider.overrideWith((ref) {
            final session = ref.watch(compteProvider).value;
            if (session == null) {
              throw StateError(
                'Aucun compte connecte : la synchronisation demande une '
                'session.',
              );
            }
            return TransportSupabase(
              url: _adresseDuProjet,
              clePublique: _clePublique,
              utilisateur: session.utilisateur,
              jeton: session.jetonAcces,
              client: projet.client,
            );
          }),
        ],
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Pose une pesee locale, par le meme chemin qu'une version gagnante.
  Future<void> poserUnePesee() => ecrireLigne(
    base.db,
    tablesSynchronisables.firstWhere((table) => table.nom == 'pesees'),
    LigneSynchronisable(
      cle: 'p1',
      updatedAt: 1000,
      contenu: {
        'mesure_le': 1000,
        'poids_kg': 70.5,
        'note': null,
        'created_at': 1000,
      },
    ),
  );

  group('ce qu\'un passage exige', () {
    test('sans compte, le passage est refuse et rien ne part', () async {
      final projet = _Projet();
      final container = conteneur(projet: projet);

      await container.read(synchronisationProvider.notifier).synchroniser();

      final etat = container.read(synchronisationProvider);
      expect(etat.hasError, isTrue);
      expect(etat.error, isA<SessionRefuseeFailure>());
      // Le refus precede toute requete de donnees. Un passage qui partirait
      // sans jeton reviendrait refuse table par table, et l'ecran annoncerait
      // six tables en echec la ou il n'y a qu'un compte absent.
      expect(projet.jetonsVus, isEmpty);
    });

    test('un jeton valide part tel quel, sans renouvellement', () async {
      await store.ecrireSession(_session(expireLe: _valide()));
      final projet = _Projet();
      final container = conteneur(projet: projet);

      await container.read(synchronisationProvider.notifier).synchroniser();

      final etat = container.read(synchronisationProvider);
      expect(etat.hasError, isFalse, reason: '${etat.error}');
      expect(projet.rafraichissementDemande, isFalse);
      expect(projet.jetonsVus.toSet(), {'Bearer $_jetonRange'});
      // Rien a faire des deux cotes : le rapport doit le dire, et non afficher
      // un passage qui n'a rien vu.
      expect(etat.value!.estVide, isTrue);
    });

    test('un jeton perime est renouvele, et c\'est le jeton neuf qui part', () async {
      await store.ecrireSession(_session(expireLe: _perime));
      final projet = _Projet();
      final container = conteneur(projet: projet);

      await container.read(synchronisationProvider.notifier).synchroniser();

      final etat = container.read(synchronisationProvider);
      expect(etat.hasError, isFalse, reason: '${etat.error}');
      expect(projet.rafraichissementDemande, isTrue);

      // **Le point de mesure.** Toutes les requetes de donnees portent le jeton
      // neuf, et aucune ne porte l'ancien. Le renouvellement qui ne precederait
      // pas la construction du transport laisserait ici `Bearer $_jetonRange`,
      // et chaque table serait refusee.
      expect(projet.jetonsVus, isNotEmpty);
      expect(projet.jetonsVus.toSet(), {'Bearer $_jetonNeuf'});

      // Et la session neuve est **rangee**, pas seulement utilisee : sans cela,
      // le redemarrage suivant repartirait du jeton perime, et le passage
      // suivant renouvellerait une seconde fois pour rien.
      final rangee = await store.lireSession();
      expect(rangee!.jetonAcces, _jetonNeuf);
      expect(rangee.jetonRafraichissement, 'rafraichissement-neuf');
    });

    test('un renouvellement refuse laisse la session en place', () async {
      await store.ecrireSession(_session(expireLe: _perime));
      final projet = _Projet(refusDuRafraichissement: true);
      final container = conteneur(projet: projet);

      await container.read(synchronisationProvider.notifier).synchroniser();

      final etat = container.read(synchronisationProvider);
      expect(etat.hasError, isTrue);
      expect(etat.error, isA<SessionRefuseeFailure>());
      expect(projet.jetonsVus, isEmpty);

      // La deconnexion est un geste de l'utilisateur, pas un effet de bord d'un
      // passage rate. L'effacer ici lui retirerait un compte qu'il n'a pas
      // demande a quitter — et le refus, lui, est deja affiche.
      expect(await store.lireSession(), isNotNull);
    });

    test('le rapport d\'un passage est conserve, lignes comprises', () async {
      await store.ecrireSession(_session(expireLe: _valide()));
      await poserUnePesee();
      final projet = _Projet();
      final container = conteneur(projet: projet);

      await container.read(synchronisationProvider.notifier).synchroniser();

      final rapport = container.read(synchronisationProvider).value;
      expect(rapport, isNotNull);
      // La pesee locale part : c'est ce qui distingue « un passage a eu lieu »
      // de « un passage a rendu la main ». Un etat qui ne retiendrait que
      // l'absence d'erreur passerait le test precedent et tomberait ici.
      expect(rapport!.poussees, 1);
      expect(rapport.parTable['pesees']!.poussees, 1);
      expect(rapport.aEchoue, isFalse);
    });
  });

  group('la configuration de compilation', () {
    test('le transport refuse sans projet, et sans compte', () {
      // Ce test enonce sa precondition : la compilation des tests ne porte pas
      // de projet, donc la garde est mesurable ici. Le jour ou elle en
      // porterait un, l'assertion tomberait — et elle aurait raison de tomber.
      expect(
        AppConfig.supabaseConfigured,
        isFalse,
        reason:
            'cette suite est compilee sans SUPABASE_URL : la garde du '
            'transport est donc mesurable ici',
      );

      final sansProjet = ProviderContainer();
      addTearDown(sansProjet.dispose);
      expect(
        () => sansProjet.read(transportSynchronisationProvider),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Aucun projet'),
          ),
        ),
      );

      // Un projet, mais aucun compte : deux refus distincts, et deux messages
      // distincts. Les confondre ferait chercher une adresse de projet la ou il
      // faut se connecter.
      final sansCompte = ProviderContainer(
        overrides: [
          projetConfigureProvider.overrideWithValue(true),
          secureStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(sansCompte.dispose);
      expect(
        () => sansCompte.read(transportSynchronisationProvider),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Aucun compte'),
          ),
        ),
      );
    });
  });
}
