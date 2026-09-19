import 'dart:convert';
import 'dart:typed_data';

import 'package:assiette/core/failures.dart';
import 'package:assiette/data/vision/proxy_provider.dart';
import 'package:assiette/data/vision/vision_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Le mode proxy est celui de la publication : c'est lui qui portera la cle du
/// fournisseur, cote serveur. Il n'avait aucun test — ni sur ce qu'il transmet,
/// ni sur la facon dont il traduit les refus du serveur.
///
/// Ces tests portent sur la requete **reellement emise** : une constante lue
/// dans le source ne dirait rien de ce qui part sur le fil.
const _repas =
    '{"foods":[{"name":"Riz blanc cuit","estimatedWeightG":150,'
    '"confidence":0.8}],"overallConfidence":0.8}';

const _etiquette = '{"carbohydrates":28,"proteins":2.7,"confidence":0.9}';

const _endpoint = 'https://exemple.test/functions/v1';
const _jeton = 'jeton-de-session-0123456789';

/// Banc d'essai : enregistre chaque requete emise, puis repond une valeur fixe.
class _Banc {
  _Banc({
    this.corps = _repas,
    this.statut = 200,
    String endpoint = _endpoint,
    String? jeton,
  }) {
    provider = ProxyVisionProvider(
      endpoint: endpoint,
      authToken: jeton,
      client: MockClient((requete) async {
        requetes.add(requete);
        if (statut != 200) {
          return http.Response(
            jsonEncode({'message': 'refuse par le serveur', 'retryAfterS': 30}),
            statut,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(
          corps,
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
  }

  final String corps;
  final int statut;
  final List<http.Request> requetes = [];
  late final ProxyVisionProvider provider;

  Map<String, dynamic> get envoye =>
      jsonDecode(requetes.single.body) as Map<String, dynamic>;

  Map<String, String> enTetes() => {
    for (final entree in requetes.single.headers.entries)
      entree.key.toLowerCase(): entree.value,
  };
}

void main() {
  final image = Uint8List.fromList(List<int>.generate(64, (i) => i));

  group('requete transmise', () {
    test('l\'URL vise la fonction demandee', () async {
      final banc = _Banc();
      await banc.provider.analyzeMeal(MealAnalysisRequest(image: image));

      expect(banc.requetes.single.url.toString(), '$_endpoint/analyze-meal');
    });

    test('un slash final dans le point d\'entree ne double pas', () async {
      final banc = _Banc(endpoint: '$_endpoint///');
      await banc.provider.analyzeMeal(MealAnalysisRequest(image: image));

      expect(banc.requetes.single.url.toString(), '$_endpoint/analyze-meal');
    });

    test('l\'etiquette vise sa propre fonction', () async {
      final banc = _Banc(corps: _etiquette);
      await banc.provider.analyzeLabel(LabelAnalysisRequest(image: image));

      expect(banc.requetes.single.url.toString(), '$_endpoint/analyze-label');
    });

    test('l\'image part en base64 avec son type', () async {
      final banc = _Banc();
      await banc.provider.analyzeMeal(MealAnalysisRequest(image: image));

      expect(banc.envoye['mimeType'], 'image/jpeg');
      expect(base64Decode(banc.envoye['imageBase64'] as String), image);
    });

    test('une seconde image ajoute ses deux champs', () async {
      final banc = _Banc();
      await banc.provider.analyzeMeal(
        MealAnalysisRequest(image: image, secondImage: image),
      );

      expect(banc.envoye['secondImageBase64'], isNotNull);
      expect(banc.envoye['secondMimeType'], 'image/jpeg');
    });

    test(
      'les indications facultatives ne partent que si elles existent',
      () async {
        final sans = _Banc();
        await sans.provider.analyzeMeal(MealAnalysisRequest(image: image));
        expect(sans.envoye.containsKey('portionHint'), isFalse);
        expect(sans.envoye.containsKey('userHint'), isFalse);

        final avec = _Banc();
        await avec.provider.analyzeMeal(
          MealAnalysisRequest(
            image: image,
            portionHint: 'large',
            userHint: '  avec du fromage  ',
          ),
        );
        expect(avec.envoye['portionHint'], 'large');
        // Une indication vide n'a pas a etre transmise : elle ferait grossir la
        // requete pour ne rien dire.
        expect(avec.envoye['userHint'], 'avec du fromage');
      },
    );

    test(
      'aucune cle de fournisseur n\'est transmise par l\'application',
      () async {
        final banc = _Banc(jeton: _jeton);
        await banc.provider.analyzeMeal(MealAnalysisRequest(image: image));

        // C'est la promesse du mode proxy : le binaire ne porte aucun secret.
        expect(banc.enTetes()['authorization'], 'Bearer $_jeton');
        final corps = banc.requetes.single.body;
        expect(corps.contains('apiKey'), isFalse);
        expect(corps.contains('sk-'), isFalse);
      },
    );

    test('sans jeton, aucun en-tete d\'autorisation n\'est envoye', () async {
      final banc = _Banc();
      await banc.provider.analyzeMeal(MealAnalysisRequest(image: image));

      expect(banc.enTetes().containsKey('authorization'), isFalse);
    });
  });

  group('refus du serveur', () {
    test('un 401 est signale comme jeton refuse', () async {
      final banc = _Banc(statut: 401);

      await expectLater(
        banc.provider.analyzeMeal(MealAnalysisRequest(image: image)),
        throwsA(
          isA<MissingCredentialFailure>().having(
            (e) => e.rejected,
            'rejected',
            isTrue,
          ),
        ),
      );
    });

    test('un 413 parle de la taille de la photo', () async {
      final banc = _Banc(statut: 413);

      await expectLater(
        banc.provider.analyzeMeal(MealAnalysisRequest(image: image)),
        throwsA(
          isA<ProviderFailure>().having(
            (e) => e.message,
            'message',
            contains('trop volumineuse'),
          ),
        ),
      );
    });

    test('un 415 parle du format', () async {
      final banc = _Banc(statut: 415);

      await expectLater(
        banc.provider.analyzeMeal(MealAnalysisRequest(image: image)),
        throwsA(
          isA<ProviderFailure>().having(
            (e) => e.message,
            'message',
            contains('Format'),
          ),
        ),
      );
    });

    test('un 429 rapporte le delai d\'attente demande', () async {
      final banc = _Banc(statut: 429);

      await expectLater(
        banc.provider.analyzeMeal(MealAnalysisRequest(image: image)),
        throwsA(
          isA<RateLimitFailure>().having(
            (e) => e.retryAfterS,
            'retryAfterS',
            equals(30),
          ),
        ),
      );
    });

    test('un 500 remonte le message du serveur', () async {
      final banc = _Banc(statut: 500);

      await expectLater(
        banc.provider.analyzeMeal(MealAnalysisRequest(image: image)),
        throwsA(isA<ProviderFailure>()),
      );
    });

    test('un point d\'entree vide n\'emet aucune requete', () async {
      final banc = _Banc(endpoint: '   ');

      await expectLater(
        banc.provider.analyzeMeal(MealAnalysisRequest(image: image)),
        throwsA(isA<MissingCredentialFailure>()),
      );
      expect(banc.requetes, isEmpty);
    });
  });

  group('reponse exploitable', () {
    test('une reponse sans aliment est signalee comme telle', () async {
      final banc = _Banc(corps: '{"foods":[]}');

      await expectLater(
        banc.provider.analyzeMeal(MealAnalysisRequest(image: image)),
        throwsA(isA<NoFoodDetectedFailure>()),
      );
    });

    test('un corps vide n\'est pas confondu avec une analyse valide', () async {
      final banc = _Banc(corps: '');

      await expectLater(
        banc.provider.analyzeMeal(MealAnalysisRequest(image: image)),
        throwsA(isA<NoFoodDetectedFailure>()),
      );
    });
  });
}
