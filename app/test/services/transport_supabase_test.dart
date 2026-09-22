/// Ce que le transport fait **reellement** de chaque requete.
///
/// Ce que ces tests mesurent
/// -------------------------
/// Les requetes **emises**, pas des constantes relues dans le code. Un test qui
/// relirait le source passerait au vert le jour ou un en-tete disparait ; un
/// test qui regarde la requete ne le peut pas. Meme discipline que
/// `deepseek_provider_test.dart`, et meme raison.
///
/// Le faux serveur est un client HTTP injecte : le transport ne sait pas qu'on
/// lui ment, donc c'est bien **le vrai chemin de code** qui s'execute — le
/// decoupage en pages, le deuxieme passage sur les aliments, les trois
/// conversions de type. Ce qui n'est pas eprouve ici, et qui ne peut pas l'etre
/// sans projet Supabase, c'est que le serveur accepte ces requetes : ce fichier
/// etablit qu'on envoie ce qu'on croit envoyer, pas que PostgREST en fait ce
/// qu'on croit.
///
/// Pourquoi les en-tetes sont ecrits avec leur casse reelle
/// --------------------------------------------------------
/// Un vrai serveur envoie `Date`, avec sa majuscule. Un faux serveur qui
/// ecrirait `date` validerait un transport qui cherche `'date'` en dur — et ce
/// transport-la rendrait `null` en production, en silence, parce que l'ecart
/// d'horloge est un diagnostic dont l'echec ne se voit pas. Le premier test de
/// ce fichier existe pour cela, et c'est la seule raison pour laquelle il ecrit
/// `Date` comme il l'ecrit.
library;

import 'dart:async';
import 'dart:convert';

import 'package:assiette/core/failures.dart';
import 'package:assiette/data/local/synchronisation_locale.dart';
import 'package:assiette/models/synchronisation.dart';
import 'package:assiette/services/transport_supabase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// --- fixtures ---------------------------------------------------------------

const String _adresse = 'https://projet.supabase.co/';
const String _clePublique = 'cle-publique-de-test';
const String _utilisateur = 'user-1';
const String _jeton = 'jeton-de-session';

/// Un horodatage et son equivalent local, ecrits tous les deux.
///
/// Les deux formes sont posees a la main plutot que calculees l'une depuis
/// l'autre : une conversion qui prendrait la valeur attendue dans le meme
/// calcul que la valeur produite ne mesurerait rien.
const String _iso = '2023-11-14T22:13:20.000Z';
const int _ms = 1700000000000;

const String _dateHttp = 'Tue, 22 Sep 2026 07:54:18 GMT';

TableSynchronisable _table(String nom) =>
    tablesSynchronisables.firstWhere((table) => table.nom == nom);

/// Une reponse JSON, en UTF-8.
///
/// Le `charset` n'est pas cosmetique : sans lui, `http.Response` encode le corps
/// en latin-1, et le transport, qui decode en UTF-8, refuserait une reponse
/// parfaitement valide.
http.Response _json(
  Object? corps, {
  int statut = 200,
  Map<String, String> entetes = const {},
}) => http.Response(
  jsonEncode(corps),
  statut,
  headers: {'content-type': 'application/json; charset=utf-8', ...entetes},
);

/// Un repas tel que le serveur le porte.
Map<String, Object?> _repasDistant(
  String cle, {
  String uuid = 'uuid-1',
  Object? photoPath,
}) => {
  'id': uuid,
  'user_id': _utilisateur,
  'client_id': cle,
  'eaten_at': _iso,
  'name': 'Riz blanc cuit',
  'source': 'ciqual',
  'notes': null,
  'photo_path': photoPath,
  'is_estimate': true,
  'created_at': _iso,
  'updated_at': _iso,
  'deleted_at': null,
  // Denormalisees par le serveur : le local ne les porte pas.
  'total_kcal': 195.0,
  'total_carbs_g': 42.0,
  'total_sugars_g': 0.2,
  'total_protein_g': 4.1,
  'total_fat_g': 0.5,
  'total_fiber_g': 0.6,
  'total_salt_g': 0.02,
};

/// Un aliment tel que le serveur le porte.
Map<String, Object?> _alimentDistant(String cle, String uuidRepas) => {
  'id': 'ligne-$cle',
  'user_id': _utilisateur,
  'client_id': cle,
  'meal_id': uuidRepas,
  'name': 'Riz blanc cuit',
  'quantity_g': 150.0,
  'kcal_100g': 130.0,
  'carbs_100g': 28.0,
  'sugars_100g': 0.1,
  'starch_100g': 27.0,
  'protein_100g': 2.7,
  'fat_100g': 0.3,
  'sat_fat_100g': 0.1,
  'fiber_100g': 0.4,
  'salt_100g': 0.01,
  'source': 'ciqual',
  'source_ref': '9100',
  'brand': null,
  'image_url': null,
  'confidence': 0.9,
  'portion_size': null,
  'is_estimate': false,
  'sort_order': 0,
  'created_at': _iso,
  'updated_at': _iso,
};

/// Un aliment en vocabulaire **local**, comme `lireLignes` le produit.
Map<String, Object?> _alimentLocal(String cle) => {
  'id': cle,
  'name': 'Riz blanc cuit',
  'quantity_g': 150.0,
  'kcal_100g': 130.0,
  'carbs_100g': 28.0,
  'sugars_100g': 0.1,
  'starch_100g': 27.0,
  'protein_100g': 2.7,
  'fat_100g': 0.3,
  'sat_fat_100g': 0.1,
  'fiber_100g': 0.4,
  'salt_100g': 0.01,
  'source': 'ciqual',
  'source_ref': '9100',
  'brand': null,
  'image_url': null,
  'confidence': 0.9,
  'portion': null,
  'is_estimate': 0,
  'sort_order': 0,
};

/// Un repas en vocabulaire **local**, comme `lireLignes` le produit.
LigneSynchronisable _repasLocal(
  String cle, {
  List<Map<String, Object?>> aliments = const [],
  Map<String, Object?> supplement = const {},
}) => LigneSynchronisable(
  cle: cle,
  updatedAt: _ms,
  contenu: {
    'eaten_at': _ms,
    'name': 'Riz blanc cuit',
    'source': 'ciqual',
    'notes': null,
    'is_estimate': 1,
    'created_at': _ms,
    ...supplement,
    cleDesEnfants: aliments,
  },
);

// --- le faux projet ---------------------------------------------------------

/// Un client qui retient s'il a ete ferme.
///
/// Un client injecte appartient a l'appelant : le transport qui le fermerait
/// rendrait inutilisable un client qu'un autre usage partage. La faute est
/// silencieuse — l'appelant decouvre le probleme bien plus tard, sur une
/// requete sans rapport — donc elle se mesure ici.
class _Espion extends http.BaseClient {
  _Espion(this._interne);

  final http.Client _interne;
  bool ferme = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest requete) =>
      _interne.send(requete);

  @override
  void close() {
    ferme = true;
    _interne.close();
  }
}

/// Le faux projet, et les requetes qu'il a recues.
class _Banc {
  _Banc({
    this.lignesParPage = plafondPostgrest,
    this.delai = const Duration(seconds: 30),
  });

  final int lignesParPage;
  final Duration delai;

  /// Les requetes recues, dans l'ordre.
  final List<http.Request> requetes = [];

  /// Ce que le faux serveur repond. Chaque test le remplace.
  Future<http.Response> Function(http.Request requete) repondre = (_) async =>
      _json(const []);

  late final _Espion espion = _Espion(MockClient(_recevoir));

  late final TransportSupabase transport = TransportSupabase(
    url: _adresse,
    clePublique: _clePublique,
    utilisateur: _utilisateur,
    jeton: _jeton,
    client: espion,
    lignesParPage: lignesParPage,
    delai: delai,
  );

  Future<http.Response> _recevoir(http.Request requete) {
    requetes.add(requete);
    return repondre(requete);
  }

  /// Les requetes d'une methode donnee.
  List<http.Request> de(String methode) => [
    for (final requete in requetes)
      if (requete.method == methode) requete,
  ];

  /// Les requetes qui visent une table donnee.
  ///
  /// Lire un agregat lit **deux** tables : les repas, puis leurs aliments. Un
  /// comptage qui ne distingue pas les deux mesurerait autre chose que ce qu'il
  /// annonce.
  List<http.Request> sur(String table) => [
    for (final requete in requetes)
      if (requete.url.pathSegments.last == table) requete,
  ];

  http.Request get derniere => requetes.last;
}

/// Les en-tetes d'une requete, en minuscules.
Map<String, String> _entetesDe(http.Request requete) => {
  for (final entree in requete.headers.entries)
    entree.key.toLowerCase(): entree.value,
};

/// Le corps d'une requete, quand c'est une liste.
List<Map<String, Object?>> _listeDe(http.Request requete) {
  final decode = jsonDecode(requete.body);
  if (decode is! List) throw StateError('corps inattendu : $decode');
  return [
    for (final element in decode)
      if (element is Map) element.cast<String, Object?>(),
  ];
}

/// Le corps d'une requete, quand c'est un objet.
Map<String, Object?> _objetDe(http.Request requete) => _listeDe(requete).single;

void main() {
  group('l\'heure du serveur', () {
    test('l\'en-tete Date est lu quelle que soit sa casse', () async {
      final banc = _Banc();
      banc.repondre = (_) async =>
          http.Response('', 200, headers: {'Date': _dateHttp});

      expect(
        await banc.transport.heureServeur(),
        DateTime.utc(2026, 9, 22, 7, 54, 18).millisecondsSinceEpoch,
      );
      expect(banc.derniere.method, 'HEAD');
      expect(banc.derniere.url.path, '/rest/v1/');
    });

    test('une reponse d\'erreur porte quand meme l\'heure', () async {
      // Une passerelle pose `Date` sur **toutes** ses reponses. Refuser celle
      // d'une reponse en erreur ferait disparaitre le diagnostic d'horloge sur
      // un projet mal configure — c'est-a-dire exactement quand on en a besoin.
      final banc = _Banc();
      banc.repondre = (_) async =>
          http.Response('', 401, headers: {'Date': _dateHttp});

      expect(
        await banc.transport.heureServeur(),
        DateTime.utc(2026, 9, 22, 7, 54, 18).millisecondsSinceEpoch,
      );
    });

    test('sans en-tete Date, l\'heure est refusee', () async {
      final banc = _Banc();
      banc.repondre = (_) async => http.Response('', 200);

      await expectLater(
        banc.transport.heureServeur(),
        throwsA(isA<InvalidResponseFailure>()),
      );
    });
  });

  group('la lecture', () {
    test('les pages sont demandees par Range, et la lecture s\'arrete sur une '
        'page incomplete', () async {
      final banc = _Banc(lignesParPage: 2);
      final pages = [
        [_repasDistant('m1'), _repasDistant('m2')],
        [_repasDistant('m3')],
      ];
      banc.repondre = (requete) async {
        if (requete.url.pathSegments.last == 'meal_items') {
          return _json(const []);
        }
        final debut = int.parse(requete.headers['Range']!.split('-').first);
        return _json(pages[debut ~/ 2], statut: 206);
      };

      final lignes = await banc.transport.lire(_table('meals'));

      expect([for (final ligne in lignes) ligne.cle], ['m1', 'm2', 'm3']);
      final repas = banc.sur('meals');
      expect(repas, hasLength(2));
      expect(repas[0].headers['Range'], '0-1');
      expect(repas[1].headers['Range'], '2-3');
      expect(repas[0].headers['Range-Unit'], 'items');
      // Sans `Range`, PostgREST rend au plus mille lignes **sans le dire** : la
      // synchronisation croirait le reste absent du serveur.
      expect(repas[0].url.queryParameters['select'], '*');
    });

    test('une lecture qui ne finit jamais est arretee', () async {
      // Une page toujours pleine ferait tourner la boucle sans fin. La borne
      // doit se voir : au-dela, ce n'est plus une synchronisation.
      final banc = _Banc(lignesParPage: 1);
      banc.repondre = (_) async => _json([_repasDistant('m1')], statut: 206);

      await expectLater(
        banc.transport.lire(_table('meals')),
        throwsA(
          isA<ProviderFailure>().having(
            (e) => e.message,
            'message',
            contains('$pagesMax pages'),
          ),
        ),
      );
      expect(banc.requetes, hasLength(pagesMax));
    });

    test(
      'une ligne distante revient en vocabulaire local, types convertis',
      () async {
        final banc = _Banc();
        banc.repondre = (_) async => _json([_repasDistant('m1')]);

        final ligne = (await banc.transport.lire(_table('meals'))).single;

        expect(ligne.cle, 'm1');
        expect(ligne.updatedAt, _ms);
        expect(ligne.deletedAt, isNull);
        expect(ligne.contenu['eaten_at'], _ms);
        expect(ligne.contenu['created_at'], _ms);
        // `true` cote serveur, `1` cote local : sans conversion, les deux
        // empreintes differeraient a jamais.
        expect(ligne.contenu['is_estimate'], 1);
      },
    );

    test('les colonnes du serveur n\'entrent pas dans le contenu', () async {
      final banc = _Banc();
      banc.repondre = (_) async => _json([_repasDistant('m1')]);

      final ligne = (await banc.transport.lire(_table('meals'))).single;

      // Exactement ce que `lireLignes` produit pour la table locale : les
      // colonnes de service sont portees a cote, la cle aussi, les colonnes
      // denormalisees du serveur n'existent pas en local, et un agregat range
      // ses aliments sous `items` — jamais son lien.
      expect(ligne.contenu.keys.toSet(), {
        'eaten_at',
        'name',
        'source',
        'notes',
        'is_estimate',
        'created_at',
        cleDesEnfants,
      });
    });

    test(
      'une colonne propre a l\'appareil ne revient pas dans le contenu',
      () async {
        final banc = _Banc();
        banc.repondre = (_) async => _json([
          _repasDistant(
            'm1',
            photoPath: '/data/user/0/fr.assiette/files/meal_photos/autre.jpg',
          ),
        ]);

        final ligne = (await banc.transport.lire(_table('meals'))).single;

        // Le chemin est celui d'un **autre** appareil. Le faire entrer dans le
        // contenu le ferait ecrire en local, et l'image manquerait sans erreur.
        expect(ligne.contenu.containsKey('photo_path'), isFalse);
        expect(ligne.contenu.containsKey('photoPath'), isFalse);
      },
    );

    test('un jsonb revient en texte local', () async {
      final banc = _Banc();
      banc.repondre = (_) async => _json([
        {
          'id': 'uuid-t1',
          'user_id': _utilisateur,
          'client_id': 't1',
          'name': 'Petit dejeuner',
          'items': [
            {'name': 'Pain', 'grams': 60},
          ],
          'created_at': _iso,
          'updated_at': _iso,
        },
      ]);

      final ligne = (await banc.transport.lire(_table('templates'))).single;

      // Le serveur rend une **liste**, le local attend une chaine.
      expect(ligne.contenu['items_json'], '[{"name":"Pain","grams":60}]');
    });

    test('les aliments se rattachent a leur repas, et la colonne de lien est '
        'exclue', () async {
      final banc = _Banc();
      banc.repondre = (requete) async => _json(
        requete.url.path.endsWith('meal_items')
            ? [_alimentDistant('i1', 'uuid-1'), _alimentDistant('i2', 'uuid-1')]
            : [_repasDistant('m1')],
      );

      final ligne = (await banc.transport.lire(_table('meals'))).single;

      final aliments = ligne.contenu[cleDesEnfants]! as List<Object?>;
      expect(aliments, hasLength(2));
      final premier = aliments.first! as Map<String, Object?>;
      expect(premier['id'], 'i1');
      // La colonne de lien est derivee du parent : la garder ferait dependre
      // l'empreinte d'une valeur qui n'appartient pas a la ligne.
      expect(premier.containsKey('meal_id'), isFalse);
      expect(premier['portion'], isNull);
      expect(premier['is_estimate'], 0);
      // Meme ensemble de cles que ce que `lireLignes` produit en local.
      expect(premier.keys.toSet(), _alimentLocal('i1').keys.toSet());
    });

    test(
      'un repas sans aliment rend une liste vide, jamais une absence',
      () async {
        final banc = _Banc();
        banc.repondre = (requete) async => _json(
          requete.url.path.endsWith('meal_items')
              ? const []
              : [_repasDistant('m1')],
        );

        final ligne = (await banc.transport.lire(_table('meals'))).single;

        // Une absence d'un cote et une liste vide de l'autre feraient diverger
        // les empreintes pour toujours.
        expect(ligne.contenu[cleDesEnfants], isEmpty);
      },
    );

    test('un aliment dont le repas n\'est pas la est ignore', () async {
      final banc = _Banc();
      banc.repondre = (requete) async => _json(
        requete.url.path.endsWith('meal_items')
            ? [_alimentDistant('i1', 'uuid-inconnu')]
            : [_repasDistant('m1')],
      );

      final ligne = (await banc.transport.lire(_table('meals'))).single;

      expect(ligne.contenu[cleDesEnfants], isEmpty);
    });
  });

  group('l\'ecriture', () {
    /// Un faux serveur qui accepte tout, et rend l'`uuid` du repas ecrit.
    Future<http.Response> _accepter(http.Request requete) async {
      if (requete.method == 'GET') {
        return _json([
          {'id': 'uuid-1', 'client_id': 'm1'},
        ]);
      }
      if (requete.method == 'DELETE') return http.Response('', 204);
      return http.Response('', 201);
    }

    test('un repas part en upsert, avec on_conflict et Prefer', () async {
      final banc = _Banc();
      banc.repondre = _accepter;

      await banc.transport.ecrire(_table('meals'), [
        _repasLocal('m1', aliments: [_alimentLocal('i1')]),
      ]);

      final envoi = banc.de('POST').first;
      expect(envoi.url.path, '/rest/v1/meals');
      // Sans `on_conflict`, PostgREST refuse au lieu de remplacer, et la
      // synchronisation echoue a chaque passage sans rien perdre.
      expect(envoi.url.queryParameters['on_conflict'], 'user_id,client_id');
      final entetes = _entetesDe(envoi);
      expect(entetes['prefer'], 'resolution=merge-duplicates,return=minimal');
      expect(entetes['apikey'], _clePublique);
      expect(entetes['authorization'], 'Bearer $_jeton');
      expect(entetes['content-type'], 'application/json');

      final corps = _objetDe(envoi);
      expect(corps['client_id'], 'm1');
      // RLS filtre par `auth.uid()` : une ligne sans son proprietaire est
      // refusee.
      expect(corps['user_id'], _utilisateur);
      expect(corps['updated_at'], _iso);
      // Les aliments ne sont pas une colonne : ils partent par le deuxieme
      // passage.
      expect(corps.containsKey(cleDesEnfants), isFalse);
    });

    test('les dates repartent en ISO, les booleens en booleen', () async {
      final banc = _Banc();
      banc.repondre = _accepter;

      await banc.transport.ecrire(_table('meals'), [_repasLocal('m1')]);

      final corps = _objetDe(banc.de('POST').first);
      expect(corps['eaten_at'], _iso);
      expect(corps['created_at'], _iso);
      // La date de modification ne vient pas du contenu : elle est portee a
      // cote par la ligne. Sans conversion, le serveur recevrait un entier la
      // ou le schema attend un `timestamptz`.
      expect(corps['updated_at'], _iso);
      expect(corps['deleted_at'], isNull);
      expect(corps['is_estimate'], isTrue);
      expect(corps['notes'], isNull);
    });

    test('une colonne propre a l\'appareil ne part jamais', () async {
      final banc = _Banc();
      banc.repondre = _accepter;

      // `contenuDe` retire deja cette colonne de ce qu'il rend ; ce test etablit
      // que le transport la retire **aussi**, donc que la regle ne depend pas de
      // son appelant. C'est ce qui la rend vraie le jour ou un second appelant
      // apparait.
      await banc.transport.ecrire(_table('meals'), [
        _repasLocal(
          'm1',
          supplement: {
            'photo_path': '/data/user/0/fr.assiette/files/meal_photos/m1.jpg',
          },
        ),
      ]);

      final corps = _objetDe(banc.de('POST').first);
      expect(corps.containsKey('photo_path'), isFalse);
    });

    test('les aliments sont rattaches en deux passages, apres avoir relu '
        'l\'uuid', () async {
      final banc = _Banc();
      banc.repondre = _accepter;

      await banc.transport.ecrire(_table('meals'), [
        _repasLocal('m1', aliments: [_alimentLocal('i1')]),
      ]);

      expect(
        [for (final requete in banc.requetes) requete.method],
        ['POST', 'GET', 'DELETE', 'POST'],
      );

      // Le deuxieme passage commence par relire l'`uuid` : c'est la seule fois
      // ou l'appareil l'apprend, et il ne peut pas le deviner.
      final relecture = banc.de('GET').single;
      expect(relecture.url.queryParameters['select'], 'id,client_id');
      expect(relecture.url.queryParameters['client_id'], 'in.("m1")');

      // Les aliments sont reecrits en bloc : un aliment retire du repas
      // disparaitrait sinon du serveur, et les deux agregats ne seraient plus
      // le meme.
      final suppression = banc.de('DELETE').single;
      expect(suppression.url.path, '/rest/v1/meal_items');
      expect(suppression.url.queryParameters['meal_id'], 'in.("uuid-1")');

      final rattachement = banc.de('POST')[1];
      expect(rattachement.url.path, '/rest/v1/meal_items');
      expect(
        rattachement.url.queryParameters['on_conflict'],
        'user_id,client_id',
      );
      final aliment = _objetDe(rattachement);
      expect(aliment['meal_id'], 'uuid-1');
      expect(aliment['user_id'], _utilisateur);
      expect(aliment['client_id'], 'i1');
      expect(aliment['portion_size'], isNull);
      expect(aliment['is_estimate'], isFalse);
      // Le cycle de vie d'un aliment est celui de son repas : lui donner une
      // date ferait apparaitre une valeur que rien ne compare.
      expect(aliment.containsKey('updated_at'), isFalse);
    });

    test(
      'un repas sans aliment efface ses aliments distants sans en creer',
      () async {
        final banc = _Banc();
        banc.repondre = _accepter;

        await banc.transport.ecrire(_table('meals'), [_repasLocal('m1')]);

        expect(banc.de('DELETE'), hasLength(1));
        expect(banc.de('POST'), hasLength(1));
      },
    );

    test('les identifiants sont mis entre guillemets dans in.(...)', () async {
      final banc = _Banc();
      banc.repondre = _accepter;

      // La grammaire de `in` separe par des virgules : un identifiant qui en
      // contiendrait une serait coupe en deux, et le deuxieme passage
      // rattacherait des aliments au mauvais repas.
      await banc.transport.ecrire(_table('meals'), [_repasLocal('a,b')]);

      expect(
        banc.de('GET').single.url.queryParameters['client_id'],
        'in.("a,b")',
      );
    });
  });

  group('les pannes', () {
    test(
      'un 401 et un 403 sont une session refusee, pas une cle d\'analyse',
      () async {
        for (final statut in [401, 403]) {
          final banc = _Banc();
          banc.repondre = (_) async => http.Response('', statut);

          await expectLater(
            banc.transport.lire(_table('templates')),
            throwsA(isA<SessionRefuseeFailure>()),
          );
          // Les confondre enverrait l'utilisateur renseigner une cle d'analyse
          // alors que le remede est de se reconnecter.
          await expectLater(
            banc.transport.lire(_table('templates')),
            throwsA(isNot(isA<MissingCredentialFailure>())),
          );
        }
      },
    );

    test('un 429 est une limite de debit', () async {
      final banc = _Banc();
      banc.repondre = (_) async => http.Response('', 429);

      await expectLater(
        banc.transport.lire(_table('templates')),
        throwsA(isA<RateLimitFailure>()),
      );
    });

    test('un 500 est reessayable, un 400 ne l\'est pas', () async {
      final banc = _Banc();
      banc.repondre = (_) async => http.Response('', 500);

      await expectLater(
        banc.transport.lire(_table('templates')),
        throwsA(
          isA<ProviderFailure>()
              .having((e) => e.isRetryable, 'isRetryable', isTrue)
              .having((e) => e.statusCode, 'statusCode', 500),
        ),
      );

      banc.repondre = (_) async => http.Response('', 400);
      await expectLater(
        banc.transport.lire(_table('templates')),
        throwsA(
          isA<ProviderFailure>()
              .having((e) => e.isRetryable, 'isRetryable', isFalse)
              .having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });

    test('une coupure reseau et un delai depasse sont traduits', () async {
      final banc = _Banc();
      banc.repondre = (_) async => throw http.ClientException('coupure');

      await expectLater(
        banc.transport.lire(_table('templates')),
        throwsA(isA<NetworkFailure>()),
      );

      final lent = _Banc(delai: const Duration(milliseconds: 20));
      lent.repondre = (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return _json(const []);
      };

      await expectLater(
        lent.transport.lire(_table('templates')),
        throwsA(isA<TimeoutFailure>()),
      );
    });
  });

  group('le client', () {
    test('un client injecte n\'est pas ferme', () async {
      final banc = _Banc();
      banc.repondre = (_) async => _json(const []);

      await banc.transport.lire(_table('templates'));
      banc.transport.fermer();

      expect(banc.espion.ferme, isFalse);
      // Et il sert encore : c'est la consequence qui compte pour l'appelant.
      await banc.transport.lire(_table('templates'));
      expect(banc.de('GET'), hasLength(2));
    });
  });
}
