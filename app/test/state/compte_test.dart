/// Le compte : se connecter, se deconnecter, et ce qui reste sur l'appareil.
///
/// Ce que ces tests mesurent
/// -------------------------
/// Le **vrai** `CompteNotifier`, sur un faux trousseau et un faux serveur HTTP.
/// Les deux sont injectes, donc le chemin de code reel s'execute : la lecture du
/// trousseau au demarrage, la requete, l'ecriture, l'effacement.
///
/// Ce qu'ils ne peuvent pas mesurer
/// --------------------------------
/// Que le serveur accepte la requete. `client_authentification_test.dart` s'en
/// approche d'aussi pres que possible, et la mesure faite contre le vrai projet
/// — des identifiants invalides rendent `400` avec `error_code`, pas `401` — est
/// ce qui fixe la forme des reponses simulees ici.
///
/// Ce qu'ils ne peuvent pas mesurer non plus : que le **vrai** trousseau se
/// comporte comme ce faux. Cela demande un appareil.
library;

import 'dart:convert';

import 'package:assiette/core/config.dart';
import 'package:assiette/core/failures.dart';
import 'package:assiette/models/session.dart';
import 'package:assiette/services/client_authentification.dart';
import 'package:assiette/services/secure_store.dart';
import 'package:assiette/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../services/faux_trousseau.dart';

// --- fixtures ---------------------------------------------------------------

const String _adresse = 'personne@exemple.fr';
const String _motDePasse = 'mot-de-passe-de-test';
const String _utilisateur = 'user-1';
const String _clePublique = 'cle-publique-de-test';

/// Une expiration et son equivalent local, ecrits tous les deux a la main :
/// une conversion qui prendrait sa valeur attendue dans le meme calcul que la
/// valeur produite ne mesurerait rien.
const int _expiresAt = 1790000000;
const int _expireLe = 1790000000000;

Map<String, Object?> _corpsSession() => {
  'access_token': 'jeton-acces',
  'token_type': 'bearer',
  'expires_in': 3600,
  'expires_at': _expiresAt,
  'refresh_token': 'jeton-rafraichissement',
  'user': {'id': _utilisateur, 'email': _adresse},
};

Map<String, Object?> _refus(String code) => {
  'code': 400,
  'error_code': code,
  'msg': 'peu importe',
};

Session _sessionRangee() => const Session(
  jetonAcces: 'jeton-acces',
  jetonRafraichissement: 'jeton-rafraichissement',
  expireLe: _expireLe,
  utilisateur: _utilisateur,
  adresse: _adresse,
);

/// Un serveur qui repond toujours la meme chose.
http.Client _serveur(Object? corps, {int statut = 200}) => MockClient(
  (requete) async => http.Response(
    jsonEncode(corps),
    statut,
    headers: const {'Content-Type': 'application/json; charset=utf-8'},
  ),
);

void main() {
  late SecureStore store;

  setUp(() => store = SecureStore(storage: FauxTrousseau()));

  /// Le conteneur, avec ses deux dependances remplacees.
  ///
  /// Le serveur n'est fourni que par les tests qui parlent au reseau : sans lui,
  /// `clientAuthentificationProvider` est laisse tel quel, ce qui permet de
  /// mesurer ce qu'il fait d'une compilation sans projet.
  ProviderContainer conteneur({http.Client? serveur}) {
    final container = ProviderContainer(
      overrides: [
        secureStoreProvider.overrideWithValue(store),
        if (serveur != null)
          clientAuthentificationProvider.overrideWithValue(
            ClientAuthentification(
              url: 'https://projet.supabase.co',
              clePublique: _clePublique,
              client: serveur,
            ),
          ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('ce qui est lu au demarrage', () {
    test('sans session rangee, le compte est deconnecte', () async {
      final container = conteneur();

      expect(await container.read(compteProvider.future), isNull);
    });

    test('une session rangee est relue au demarrage', () async {
      await store.ecrireSession(_sessionRangee());
      final container = conteneur();

      final session = await container.read(compteProvider.future);

      expect(session, isNotNull);
      expect(session!.utilisateur, _utilisateur);
      // L'adresse voyage avec la session : c'est elle qui permet a l'ecran de
      // dire **de quel compte** il s'agit. Un uuid ne dirait rien a personne.
      expect(session.adresse, _adresse);
    });
  });

  group('la connexion', () {
    test('une connexion reussie range la session dans le trousseau', () async {
      final container = conteneur(serveur: _serveur(_corpsSession()));

      await container
          .read(compteProvider.notifier)
          .connecter(email: _adresse, motDePasse: _motDePasse);

      final rangee = await store.lireSession();
      expect(rangee, isNotNull);
      expect(rangee!.utilisateur, _utilisateur);
      expect(rangee.jetonRafraichissement, 'jeton-rafraichissement');
      // L'etat suit l'ecriture. Sans cette mise a jour, l'ecran resterait sur le
      // formulaire alors que la session est ouverte : la deconnexion serait
      // alors inatteignable, et il faudrait redemarrer l'application.
      final etat = await container.read(compteProvider.future);
      expect(etat?.utilisateur, _utilisateur);
    });

    test('une connexion refusee n\'ecrit rien dans le trousseau', () async {
      final container = conteneur(
        serveur: _serveur(_refus('invalid_credentials'), statut: 400),
      );

      await expectLater(
        container
            .read(compteProvider.notifier)
            .connecter(email: _adresse, motDePasse: 'faux'),
        throwsA(isA<IdentifiantsRefusesFailure>()),
      );

      // Rien n'est ecrit avant que le serveur ait repondu. Une session de
      // secours serait pire qu'aucune session : elle ferait croire a une
      // connexion qui n'existe pas, et l'erreur ne se verrait qu'a la premiere
      // requete de donnees, loin d'ici.
      expect(await store.lireSession(), isNull);
      expect(await container.read(compteProvider.future), isNull);
    });

    test('l\'adresse saisie est nettoyee avant de partir', () async {
      http.Request? envoyee;
      final container = conteneur(
        serveur: MockClient((requete) async {
          envoyee = requete;
          return http.Response(
            jsonEncode(_corpsSession()),
            200,
            headers: const {'Content-Type': 'application/json'},
          );
        }),
      );

      await container
          .read(compteProvider.notifier)
          .connecter(email: '  $_adresse  ', motDePasse: _motDePasse);

      // Le nettoyage appartient au client, et il y est eprouve. Ce test-ci
      // verifie qu'il n'est pas contourne par l'appelant : la chaine traverse
      // trois couches, et une seule suffirait a laisser passer les espaces.
      expect(
        (jsonDecode(envoyee!.body) as Map)['email'],
        _adresse,
        reason: 'l\'adresse doit arriver nettoyee au serveur',
      );
    });
  });

  group('la deconnexion', () {
    test('la deconnexion efface la session du trousseau', () async {
      await store.ecrireSession(_sessionRangee());
      final container = conteneur();
      expect(await container.read(compteProvider.future), isNotNull);

      await container.read(compteProvider.notifier).deconnecter();

      expect(await store.lireSession(), isNull);
      expect(await container.read(compteProvider.future), isNull);
    });

    test('un effacement rate laisse la session en place', () async {
      store = SecureStore(storage: FauxTrousseau(effacementEchoue: true));
      await store.ecrireSession(_sessionRangee());
      final container = conteneur();
      expect(await container.read(compteProvider.future), isNotNull);

      await expectLater(
        container.read(compteProvider.notifier).deconnecter(),
        throwsA(isA<StateError>()),
      );

      // Le trousseau porte encore la session, et l'ecran doit continuer de le
      // dire. **L'ordre compte** : effacer l'etat d'abord aurait laisse une
      // application qui se dit deconnectee alors que le redemarrage suivant lui
      // donne tort, sans que rien n'explique l'ecart.
      expect(await container.read(compteProvider.future), isNotNull);
    });
  });

  group('la configuration de compilation', () {
    test('le client suit la configuration, et refuse sans projet', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Ce test enonce sa precondition au lieu de la supposer : `flutter test`
      // est lance sans `--dart-define`, localement comme dans `ci.yml`, donc
      // cette compilation-ci ne porte pas de projet. Le jour ou les tests
      // seraient compiles avec un projet, l'assertion ci-dessous tomberait —
      // et elle aurait raison de tomber, parce que la garde ne jouerait plus.
      expect(
        AppConfig.supabaseConfigured,
        isFalse,
        reason:
            'cette suite est compilee sans SUPABASE_URL : la garde du client '
            'est donc mesurable ici',
      );

      // Un exemplaire sans projet ne peut ouvrir aucune session. Le dire vaut
      // mieux que de laisser partir une requete vers une adresse vide, qui
      // echouerait plus loin avec un message qui ne dirait rien de la cause.
      expect(
        () => container.read(clientAuthentificationProvider),
        throwsStateError,
      );
    });
  });
}
