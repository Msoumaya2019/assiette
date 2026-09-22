/// Le client du serveur d'authentification de Supabase.
///
/// Ou se situe cette couche
/// ------------------------
/// Le transport documente deja que le client Supabase officiel apporte « une
/// session, un stockage local et un rafraichissement de jeton — trois choses
/// dont l'application a besoin, mais qui n'appartiennent pas au transport ».
/// Ce fichier est la premiere de ces trois choses. Il ne connait ni la base, ni
/// les tables, ni l'arbitrage : il ouvre une session, et il la renouvelle.
///
/// Il n'utilise pas le client Supabase pour la meme raison que le transport :
/// il faut deux requetes HTTP, et l'epreuve demande un client injectable.
///
/// Ce que la specification officielle impose
/// -----------------------------------------
/// Elle a ete lue (`openapi.yaml` de `supabase/auth`), et trois de ses
/// avertissements changent la conception :
///
///   - **les erreurs sont incoherentes.** Le document le dit lui-meme : « Error
///     responses are somewhat inconsistent. Avoid using the `msg` and HTTP
///     status code to identify errors. HTTP 400 and 422 are used
///     interchangeably in many apps. » Le discriminant retenu est donc
///     `error_code` ; le code HTTP ne sert que de **repli**, quand le corps n'en
///     porte aucun ;
///   - **un `5xx` peut servir du non-JSON** : « they may serve non-JSON content.
///     Make sure you inspect the `Content-Type` header before parsing as JSON. »
///     Cet avertissement a d'abord produit un controle explicite du type de
///     contenu. Il a ete **retire** : la lecture du corps ne leve jamais, donc
///     le resultat etait identique avec et sans lui — aucun test ne pouvait
///     distinguer les deux, et une regle qu'aucune mesure ne separe est un
///     passif. L'avertissement est satisfait autrement, et plus surement : on ne
///     decode que ce qui se decode, et une panne qui n'annonce rien devient une
///     panne reessayable. Voir [_corps] ;
///   - **`apikey` est exige sur chaque point d'entree** (`APIKeyAuth`), pas
///     seulement sur celui-ci.
///
/// Mesure contre le projet reel, avec la cle publique seule : des identifiants
/// invalides rendent **`400`**, pas `401`, avec
/// `{"code":400,"error_code":"invalid_credentials","msg":"..."}`. C'est cette
/// mesure qui fixe la forme ci-dessous — et non la lecture de la documentation
/// du SDK, qui ne dit rien de la forme HTTP.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/failures.dart';
import '../models/session.dart';

/// Les deux valeurs de `grant_type` que ce client utilise.
const String _grantMotDePasse = 'password';
const String _grantRafraichissement = 'refresh_token';

class ClientAuthentification {
  ClientAuthentification({
    required String url,
    required this.clePublique,
    http.Client? client,
    this.delai = const Duration(seconds: 30),
  }) : _base = url.replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client(),
       _clientFourni = client != null;

  /// L'adresse du projet, sans barre oblique finale.
  final String _base;

  /// La cle publique du projet. Publique par conception.
  final String clePublique;

  final Duration delai;
  final http.Client _client;
  final bool _clientFourni;

  /// Ferme le client, s'il appartient a ce client d'authentification.
  ///
  /// Un client injecte appartient a l'appelant : le fermer ici rendrait
  /// inutilisable un client qu'un autre usage partage.
  void fermer() {
    if (!_clientFourni) _client.close();
  }

  // --- ce que le contrat demande ----------------------------------------

  /// Ouvre une session avec une adresse et un mot de passe.
  ///
  /// L'adresse est nettoyee de ses espaces, pas le mot de passe : un mot de
  /// passe peut legitimement commencer ou finir par une espace, et le rogner
  /// ferait echouer une saisie juste sans que rien ne le dise.
  Future<Session> connecter({
    required String email,
    required String motDePasse,
  }) => _demander(_grantMotDePasse, {
    'email': email.trim(),
    'password': motDePasse,
  });

  /// Obtient une session neuve a partir d'un jeton de rafraichissement.
  Future<Session> rafraichir(String jetonRafraichissement) => _demander(
    _grantRafraichissement,
    {'refresh_token': jetonRafraichissement},
  );

  // --- l'interne --------------------------------------------------------

  Future<Session> _demander(String type, Map<String, String> corps) async {
    final uri = Uri.parse(
      '$_base/auth/v1/token',
    ).replace(queryParameters: {'grant_type': type});

    final reponse = await _envoyer(
      () => _client.post(uri, headers: _entetes(), body: jsonEncode(corps)),
    );

    // Le statut est regarde **avant** le corps : un `429` peut venir d'un
    // intermediaire et ne rien porter d'exploitable, alors que le refus, lui,
    // est certain.
    if (reponse.statusCode == 429) throw const RateLimitFailure();

    if (reponse.statusCode >= 200 && reponse.statusCode < 300) {
      return _session(_corps(reponse) ?? const {});
    }
    throw _echec(reponse, type);
  }

  Map<String, String> _entetes() => {
    'apikey': clePublique,
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// Construit la session, ou refuse une reponse qui n'en est pas une.
  ///
  /// Les trois champs sont exiges ensemble. Un corps incomplet ne doit pas
  /// passer pour une session : un jeton d'acces vide ferait echouer chaque
  /// requete de donnees plus tard, loin d'ici, avec un message qui ne dirait
  /// rien de la cause.
  Session _session(Map<String, Object?> corps) {
    final acces = corps['access_token'];
    final rafraichissement = corps['refresh_token'];
    final utilisateur = corps['user'];
    final identifiant = utilisateur is Map ? utilisateur['id'] : null;

    if (acces is! String || acces.isEmpty) {
      throw const InvalidResponseFailure();
    }
    if (rafraichissement is! String || rafraichissement.isEmpty) {
      throw const InvalidResponseFailure();
    }
    if (identifiant is! String || identifiant.isEmpty) {
      throw const InvalidResponseFailure();
    }

    return Session(
      jetonAcces: acces,
      jetonRafraichissement: rafraichissement,
      expireLe: _expiration(corps),
      utilisateur: identifiant,
    );
  }

  /// L'expiration du jeton d'acces, en millisecondes depuis l'epoque.
  ///
  /// Le serveur rend `expires_at` en **secondes** Unix — l'unite de la
  /// specification — et `expires_in` en secondes relatives. Les deux sont
  /// acceptees, l'absolue d'abord : elle ne depend pas de l'horloge de
  /// l'appareil, qui peut etre fausse. Une absence vaut **zero**, c'est-a-dire
  /// « inconnu », jamais 1970.
  int _expiration(Map<String, Object?> corps) {
    final absolu = corps['expires_at'];
    if (absolu is num) return absolu.toInt() * 1000;

    final relatif = corps['expires_in'];
    if (relatif is num) {
      return DateTime.now().millisecondsSinceEpoch + relatif.toInt() * 1000;
    }
    return 0;
  }

  /// L'echec correspondant a une reponse de refus.
  ///
  /// [type] n'est pas decoratif : **le meme code HTTP ne veut pas dire la meme
  /// chose** selon l'operation. Un `401` sur un rafraichissement dit exactement
  /// ce qu'il faut faire — le jeton de rafraichissement ne vaut plus rien, il
  /// faut se reconnecter. Sur une connexion, il ne dit rien de tel :
  /// l'utilisateur est **deja** en train d'essayer, et le renvoyer vers
  /// « reconnectez-vous » ne lui apprendrait rien.
  AppFailure _echec(http.Response reponse, String type) {
    switch (_corps(reponse)?['error_code']) {
      case 'invalid_credentials':
        return const IdentifiantsRefusesFailure();
      case 'email_not_confirmed':
        return const AdresseNonConfirmeeFailure();
      case 'refresh_token_not_found':
      case 'session_not_found':
      case 'refresh_token_already_used':
        return const SessionRefuseeFailure();
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
        return const RateLimitFailure();
    }

    // Le code HTTP ne sert que de repli. La specification previent qu'il est peu
    // fiable — elle croise elle-meme les noms de `401` et de `403` — mais il
    // reste la seule information quand le corps n'en porte aucune.
    if (reponse.statusCode == 401 || reponse.statusCode == 403) {
      if (type == _grantRafraichissement) return const SessionRefuseeFailure();
      return ProviderFailure(
        'La connexion au compte a ete refusee',
        hint: 'Verifiez l\'adresse et le mot de passe.',
        statusCode: reponse.statusCode,
      );
    }
    if (reponse.statusCode >= 500) {
      return ProviderFailure(
        'Le service de compte est momentanement indisponible',
        hint: 'Reessayez dans quelques instants.',
        isRetryable: true,
        statusCode: reponse.statusCode,
      );
    }
    return ProviderFailure(
      'La connexion au compte a echoue',
      hint: 'Verifiez l\'adresse du projet et la cle publique dans Reglages.',
      statusCode: reponse.statusCode,
    );
  }

  /// Le corps decode, s'il est du JSON lisible. `null` sinon.
  ///
  /// Cette fonction **ne leve jamais**, et c'est elle qui repond a
  /// l'avertissement de la specification sur les `5xx` non-JSON : un corps
  /// qu'on ne sait pas lire rend `null`, la reponse tombe alors dans l'echelle
  /// des codes, et une panne serveur reste une panne serveur — reessayable —
  /// au lieu de devenir une « reponse inattendue », qui accuserait notre camp.
  Map<String, Object?>? _corps(http.Response reponse) {
    if (reponse.bodyBytes.isEmpty) return null;
    try {
      final decode = jsonDecode(utf8.decode(reponse.bodyBytes));
      return decode is Map ? decode.cast<String, Object?>() : null;
    } on FormatException {
      return null;
    }
  }

  /// Envoie la requete, et traduit les pannes de reseau.
  Future<http.Response> _envoyer(
    Future<http.Response> Function() requete,
  ) async {
    try {
      return await requete().timeout(delai);
    } on SocketException {
      throw const NetworkFailure();
    } on http.ClientException {
      throw const NetworkFailure();
    } on TimeoutException {
      throw const TimeoutFailure();
    }
  }
}
