/// Ce que le client d'authentification **envoie**, et ce qu'il comprend.
///
/// Ce que ces tests mesurent
/// -------------------------
/// Les requetes **emises**, et les echecs **rendus**. Pas des constantes relues
/// dans le code : un test qui relirait le source passerait au vert le jour ou un
/// en-tete disparait. Meme discipline que `transport_supabase_test.dart`.
///
/// Ce qu'ils ne peuvent pas mesurer
/// --------------------------------
/// Que le serveur accepte ces requetes. Le faux serveur est un client HTTP
/// injecte : le vrai chemin de code s'execute, mais on ne saurait pas d'ici que
/// GoTrue lit `grant_type` comme on l'ecrit. Une seule chose est donc verifiee
/// contre le vrai serveur, et par mesure directe : des identifiants invalides y
/// rendent `400` avec `error_code: invalid_credentials` — c'est ce que le test
/// des identifiants refuses reproduit.
///
/// Pourquoi la casse des en-tetes n'est plus eprouvee ici
/// ------------------------------------------------------
/// Le transport lit un en-tete de **reponse** (`Date`) et a souffert de la
/// casse : `http.Response.headers` ne normalise rien. Ce client-ci n'en lit
/// aucun — le controle du type de contenu a ete retire parce qu'aucun test ne
/// pouvait le distinguer — donc la lecon ne s'applique pas, et un test qui la
/// rejouerait eprouverait une regle qui n'existe pas.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:assiette/core/failures.dart';
import 'package:assiette/models/session.dart';
import 'package:assiette/services/client_authentification.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

// --- fixtures ---------------------------------------------------------------

const String _adresse = 'https://projet.supabase.co/';
const String _clePublique = 'cle-publique-de-test';
const String _jetonAcces = 'jeton-acces';
const String _jetonRafraichissement = 'jeton-rafraichissement';
const String _utilisateur = 'user-1';

const String _adresseSaisie = 'personne@exemple.fr';
const String _motDePasse = 'mot-de-passe-de-test';

/// Une expiration et son equivalent local, ecrits tous les deux.
///
/// Les deux formes sont posees a la main plutot que calculees l'une depuis
/// l'autre : une conversion qui prendrait sa valeur attendue dans le meme calcul
/// que la valeur produite ne mesurerait rien.
const int _expiresAt = 1790000000;
const int _expireLe = 1790000000000;

http.Response _json(
  Object? corps, {
  int statut = 200,
  Map<String, String> entetes = const {},
}) => http.Response(
  jsonEncode(corps),
  statut,
  headers: {'Content-Type': 'application/json; charset=utf-8', ...entetes},
);

Map<String, Object?> _corpsSession({
  bool expiration = true,
  bool compte = true,
}) => {
  'access_token': _jetonAcces,
  'token_type': 'bearer',
  'expires_in': 3600,
  if (expiration) 'expires_at': _expiresAt,
  'refresh_token': _jetonRafraichissement,
  if (compte) 'user': {'id': _utilisateur, 'email': _adresseSaisie},
};

Map<String, Object?> _erreur(String code) => {
  'code': 400,
  'error_code': code,
  'msg': 'peu importe',
};

// --- le faux serveur --------------------------------------------------------

/// Un client HTTP qui enregistre ce qu'on lui envoie.
class _Espion extends http.BaseClient {
  _Espion(this._repond);

  final Future<http.Response> Function(http.Request requete) _repond;

  /// Vrai si `close()` a ete appele sur ce client.
  bool ferme = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest requete) async {
    final reponse = await _repond(requete as http.Request);
    return http.StreamedResponse(
      Stream.value(reponse.bodyBytes),
      reponse.statusCode,
      headers: reponse.headers,
      reasonPhrase: reponse.reasonPhrase,
    );
  }

  @override
  void close() {
    ferme = true;
    super.close();
  }
}

class _Banc {
  int appels = 0;
  http.Request? derniere;
  Duration delai = const Duration(seconds: 30);

  /// Ce que le serveur repond. Chaque test le remplace au besoin.
  Future<http.Response> Function(http.Request requete) repond = (_) async =>
      _json(_corpsSession());

  late final _Espion espion = _Espion((requete) {
    appels++;
    derniere = requete;
    return repond(requete);
  });

  ClientAuthentification get client => ClientAuthentification(
    url: _adresse,
    clePublique: _clePublique,
    client: espion,
    delai: delai,
  );

  /// La requete enregistree. Lever plutot que rendre `null` : un test qui
  /// interrogerait une requete jamais envoyee doit le dire, pas comparer `null`.
  http.Request get requete {
    final requete = derniere;
    if (requete == null) throw StateError('aucune requete envoyee');
    return requete;
  }

  Map<String, Object?> get corps =>
      (jsonDecode(requete.body) as Map).cast<String, Object?>();
}

void main() {
  late _Banc banc;

  setUp(() => banc = _Banc());

  Future<Session> connecter() =>
      banc.client.connecter(email: _adresseSaisie, motDePasse: _motDePasse);

  group('la connexion', () {
    test(
      'la requete porte le grant_type, l\'adresse et le mot de passe',
      () async {
        await connecter();

        expect(banc.requete.method, 'POST');
        expect(banc.requete.url.path, '/auth/v1/token');
        expect(banc.requete.url.queryParameters['grant_type'], 'password');
        expect(banc.corps['email'], _adresseSaisie);
        expect(banc.corps['password'], _motDePasse);
      },
    );

    test('la cle publique accompagne la requete', () async {
      await connecter();

      // `apikey` est exige sur chaque point d'entree du serveur
      // d'authentification, pas seulement sur celui-ci.
      expect(banc.requete.headers['apikey'], _clePublique);
      expect(
        banc.requete.headers['Content-Type'],
        contains('application/json'),
      );
    });

    test('une session revient complete', () async {
      final session = await connecter();

      expect(session.jetonAcces, _jetonAcces);
      expect(session.jetonRafraichissement, _jetonRafraichissement);
      // L'identifiant du compte, pas l'objet `user` entier : les politiques RLS
      // attendent un uuid.
      expect(session.utilisateur, _utilisateur);
    });

    test('expires_at est lu en secondes', () async {
      final session = await connecter();

      expect(session.expireLe, _expireLe);
    });

    test('expires_in sert de repli quand expires_at manque', () async {
      banc.repond = (_) async => _json(_corpsSession(expiration: false));
      final avant = DateTime.now().millisecondsSinceEpoch;

      final session = await connecter();

      // Des bornes, et non une egalite : la valeur depend de l'horloge. La
      // fenetre d'une minute suffit a distinguer « maintenant + une heure » de
      // toute autre lecture, y compris celle d'un `expires_in` non converti.
      expect(session.expireLe, greaterThan(avant + 3590000));
      expect(
        session.expireLe,
        lessThan(DateTime.now().millisecondsSinceEpoch + 3610000),
      );
    });

    test('l\'adresse est nettoyee, le mot de passe non', () async {
      await banc.client.connecter(
        email: '  $_adresseSaisie  ',
        motDePasse: '  $_motDePasse  ',
      );

      expect(banc.corps['email'], _adresseSaisie);
      // Un mot de passe peut legitimement commencer ou finir par une espace :
      // le rogner ferait echouer une saisie juste, sans que rien ne le dise.
      expect(banc.corps['password'], '  $_motDePasse  ');
    });
  });

  group('le rafraichissement', () {
    test('la requete porte son grant_type et le jeton', () async {
      await banc.client.rafraichir(_jetonRafraichissement);

      expect(banc.requete.url.path, '/auth/v1/token');
      expect(banc.requete.url.queryParameters['grant_type'], 'refresh_token');
      expect(banc.corps['refresh_token'], _jetonRafraichissement);
      // Le mot de passe n'a rien a faire ici : c'est tout l'interet du jeton.
      expect(banc.corps.containsKey('password'), isFalse);
    });

    test(
      'un jeton de rafraichissement mort demande de se reconnecter',
      () async {
        banc.repond = (_) async =>
            _json(_erreur('refresh_token_not_found'), statut: 400);

        await expectLater(
          banc.client.rafraichir(_jetonRafraichissement),
          throwsA(isA<SessionRefuseeFailure>()),
        );
      },
    );
  });

  group('les refus', () {
    test(
      'des identifiants invalides ne sont pas une session refusee',
      () async {
        // La mesure faite contre le vrai projet : `400`, pas `401`.
        banc.repond = (_) async =>
            _json(_erreur('invalid_credentials'), statut: 400);

        await expectLater(
          banc.client.connecter(email: _adresseSaisie, motDePasse: 'faux'),
          throwsA(isA<IdentifiantsRefusesFailure>()),
        );
      },
    );

    test('une adresse non confirmee est dite telle', () async {
      banc.repond = (_) async =>
          _json(_erreur('email_not_confirmed'), statut: 400);

      await expectLater(
        connecter(),
        throwsA(isA<AdresseNonConfirmeeFailure>()),
      );
    });

    test('un 429 reste une limite de debit', () async {
      banc.repond = (_) async =>
          _json({'code': 429, 'msg': 'trop de requetes'}, statut: 429);

      await expectLater(connecter(), throwsA(isA<RateLimitFailure>()));
    });

    test('une limite de debit annoncee en 400 est reconnue', () async {
      // Le document previent que `400` et `422` s'echangent : c'est
      // `error_code` qui decide, pas le statut.
      banc.repond = (_) async =>
          _json(_erreur('over_request_rate_limit'), statut: 400);

      await expectLater(connecter(), throwsA(isA<RateLimitFailure>()));
    });

    test('un 401 sur une connexion n\'est pas une session refusee', () async {
      // L'utilisateur est **deja** en train d'essayer de se connecter : lui
      // dire « reconnectez-vous » le renverrait vers un ecran ou il est.
      banc.repond = (_) async => _json({'msg': 'sans error_code'}, statut: 401);

      await expectLater(connecter(), throwsA(isA<ProviderFailure>()));
    });

    test('un 401 sur un rafraichissement est une session refusee', () async {
      // Ici, au contraire, le refus dit exactement quoi faire.
      banc.repond = (_) async => _json({'msg': 'sans error_code'}, statut: 401);

      await expectLater(
        banc.client.rafraichir(_jetonRafraichissement),
        throwsA(isA<SessionRefuseeFailure>()),
      );
    });
  });

  group('les reponses illisibles', () {
    test('une panne en HTML reste une panne reessayable', () async {
      banc.repond = (_) async => http.Response(
        '<html><body>502 Bad Gateway</body></html>',
        502,
        headers: const {'Content-Type': 'text/html'},
      );

      // L'avertissement de la specification, tenu : le corps n'est pas decode,
      // donc la panne reste une panne — reessayable, avec son statut — et non
      // une « reponse inattendue », qui accuserait notre camp.
      await expectLater(
        connecter(),
        throwsA(
          predicate(
            (Object? erreur) =>
                erreur is ProviderFailure &&
                erreur.isRetryable &&
                erreur.statusCode == 502,
          ),
        ),
      );
    });

    test('un 500 en JSON reste une panne reessayable', () async {
      banc.repond = (_) async => _json({'msg': 'sans error_code'}, statut: 500);

      await expectLater(
        connecter(),
        throwsA(
          predicate(
            (Object? erreur) => erreur is ProviderFailure && erreur.isRetryable,
          ),
        ),
      );
    });

    test('un refus de fond n\'est pas reessayable', () async {
      banc.repond = (_) async => _json({'msg': 'sans error_code'}, statut: 400);

      await expectLater(
        connecter(),
        throwsA(
          predicate(
            (Object? erreur) =>
                erreur is ProviderFailure && !erreur.isRetryable,
          ),
        ),
      );
    });

    test('une reponse sans jeton d\'acces est refusee', () async {
      banc.repond = (_) async => _json({
        'refresh_token': _jetonRafraichissement,
        'user': {'id': _utilisateur},
      });

      await expectLater(connecter(), throwsA(isA<InvalidResponseFailure>()));
    });

    test('une session sans compte est refusee', () async {
      banc.repond = (_) async => _json(_corpsSession(compte: false));

      // Sans identifiant, chaque ligne ecrite plus tard serait refusee par les
      // politiques RLS — loin d'ici, avec un message qui ne dirait rien de la
      // cause.
      await expectLater(connecter(), throwsA(isA<InvalidResponseFailure>()));
    });

    test('un corps illisible en 200 est refuse', () async {
      banc.repond = (_) async =>
          http.Response('pas du json', 200, headers: const {});

      await expectLater(connecter(), throwsA(isA<InvalidResponseFailure>()));
    });
  });

  group('le reseau', () {
    test('une coupure reseau est traduite', () async {
      banc.repond = (_) async => throw const SocketException('coupure');

      await expectLater(connecter(), throwsA(isA<NetworkFailure>()));
    });

    test('une connexion rompue est traduite', () async {
      // `ClientException` n'est pas `SocketException` : ce sont deux branches
      // distinctes, et sans ce test la seconde pourrait disparaitre sans que
      // rien ne tombe.
      banc.repond = (_) async => throw http.ClientException('connexion rompue');

      await expectLater(connecter(), throwsA(isA<NetworkFailure>()));
    });

    test('un delai depasse est traduit', () async {
      banc.delai = const Duration(milliseconds: 20);
      banc.repond = (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return _json(_corpsSession());
      };

      await expectLater(connecter(), throwsA(isA<TimeoutFailure>()));
    });
  });

  group('le client', () {
    test('le client injecte n\'est pas ferme', () async {
      final client = banc.client;
      client.fermer();

      // Un client injecte appartient a l'appelant : le fermer ici rendrait
      // inutilisable un client qu'un autre usage partage.
      expect(banc.espion.ferme, isFalse);
    });
  });

  group('la session', () {
    test('une expiration inconnue ne declenche aucun renouvellement', () {
      const session = Session(
        jetonAcces: _jetonAcces,
        jetonRafraichissement: _jetonRafraichissement,
        expireLe: 0,
        utilisateur: _utilisateur,
      );

      // Zero veut dire « inconnu », jamais « 1970 ». Renouveler a chaque appel
      // sans savoir pourquoi serait un remede pire que le mal : le serveur sait
      // refuser un jeton perime, et c'est ce refus-la qui fait foi.
      expect(
        session.estExpireeA(DateTime.now().millisecondsSinceEpoch),
        isFalse,
      );
    });

    test('la marge fait expirer un jeton proche de son terme', () {
      const session = Session(
        jetonAcces: _jetonAcces,
        jetonRafraichissement: _jetonRafraichissement,
        expireLe: _expireLe,
        utilisateur: _utilisateur,
      );

      // Trente secondes avant l'echeance, le jeton est deja tenu pour expire :
      // une requete qui met une seconde a partir essuierait un refus pour rien.
      expect(session.estExpireeA(_expireLe - 30000), isTrue);
      // Bien avant l'echeance, il ne l'est pas : sans ce temoin, un
      // `estExpireeA` qui rendrait toujours `true` passerait le test ci-dessus.
      expect(session.estExpireeA(_expireLe - 3600000), isFalse);
    });
  });
}
