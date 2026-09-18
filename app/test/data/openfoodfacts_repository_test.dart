import 'dart:convert';

import 'package:assiette/core/failures.dart';
import 'package:assiette/data/openfoodfacts_repository.dart';
import 'package:assiette/models/food.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Reponse au format v3.6 : les nutriments sont sous
/// `product.nutrition.aggregated_set.nutrients`.
String v3Payload() => jsonEncode({
      'status': 'success',
      'product': {
        'code': '3017620422003',
        'product_name_fr': 'Pate a tartiner',
        'brands': 'Exemple, Autre marque',
        'quantity': '400 g',
        'serving_size': '15 g',
        'image_front_small_url': 'https://images.example.org/front.jpg',
        'nutrition': {
          'aggregated_set': {
            'nutrients': {
              'energy-kcal': {'value': 539, 'unit': 'kcal'},
              'carbohydrates': {'value': 57.5, 'unit': 'g'},
              'sugars': {'value': 56.3, 'unit': 'g'},
              'proteins': {'value': 6.3, 'unit': 'g'},
              'fat': {'value': 30.9, 'unit': 'g'},
              'saturated-fat': {'value': 10.6, 'unit': 'g'},
              'fiber': {'value': 0, 'unit': 'g'},
              'salt': {'value': 0.107, 'unit': 'g'},
            },
          },
        },
      },
    });

/// Reponse au format v2 : dictionnaire plat suffixe `_100g`.
String v2Payload() => jsonEncode({
      'status': 'success',
      'product': {
        'code': '3017620422003',
        'product_name': 'Pate a tartiner',
        'brands': 'Exemple',
        'nutriments': {
          'energy-kcal_100g': 539,
          'carbohydrates_100g': 57.5,
          'sugars_100g': 56.3,
          'proteins_100g': 6.3,
          'fat_100g': 30.9,
          'saturated-fat_100g': 10.6,
          'fiber_100g': 0,
          'salt_100g': 0.107,
        },
      },
    });

OpenFoodFactsRepository repositoryReturning(String body, {int status = 200}) {
  final client = MockClient((request) async {
    return http.Response(body, status, headers: {'content-type': 'application/json; charset=utf-8'});
  });
  return OpenFoodFactsRepository(client: client);
}

void main() {
  group('Lecture par code-barres', () {
    test('lit la forme v3 et renvoie les valeurs pour 100 g', () async {
      final repository = repositoryReturning(v3Payload());
      final food = await repository.fetchByBarcode('3017620422003');

      expect(food.name, 'Pate a tartiner');
      expect(food.source, FoodSource.openFoodFacts);
      expect(food.sourceRef, '3017620422003');
      expect(food.per100g.carbs, closeTo(57.5, 1e-9));
      expect(food.per100g.sugars, closeTo(56.3, 1e-9));
      expect(food.per100g.kcal, closeTo(539, 1e-9));
      expect(food.per100g.protein, closeTo(6.3, 1e-9));
      expect(food.per100g.fat, closeTo(30.9, 1e-9));
      expect(food.per100g.saturatedFat, closeTo(10.6, 1e-9));
      expect(food.per100g.salt, closeTo(0.107, 1e-9));
    });

    test('lit aussi la forme v2 si le fournisseur la renvoie', () async {
      final repository = repositoryReturning(v2Payload());
      final food = await repository.fetchByBarcode('3017620422003');

      expect(food.per100g.carbs, closeTo(57.5, 1e-9));
      expect(food.per100g.kcal, closeTo(539, 1e-9));
      expect(food.per100g.salt, closeTo(0.107, 1e-9));
    });

    test('la marque affichee est la premiere de la liste', () async {
      final repository = repositoryReturning(v3Payload());
      final food = await repository.fetchByBarcode('3017620422003');
      expect(food.brand, 'Exemple');
      expect(food.displayName, 'Pate a tartiner — Exemple');
    });

    test('la taille de portion est extraite de son libelle', () async {
      final repository = repositoryReturning(v3Payload());
      final food = await repository.fetchByBarcode('3017620422003');
      expect(food.servingSizeG, 15);
    });

    test('un code inconnu leve une erreur de produit introuvable', () async {
      final repository = repositoryReturning(jsonEncode({'status': 0, 'product': null}));
      expect(
        () => repository.fetchByBarcode('0000000000000'),
        throwsA(isA<ProductNotFoundFailure>()),
      );
    });

    test('un code vide leve immediatement une erreur', () async {
      final repository = repositoryReturning(v3Payload());
      expect(() => repository.fetchByBarcode('   '), throwsA(isA<ProductNotFoundFailure>()));
    });

    test('un produit sans nom est traite comme introuvable', () async {
      final repository = repositoryReturning(jsonEncode({
        'product': {'code': '123', 'nutrition': {'aggregated_set': {'nutrients': {}}}},
      }));
      expect(() => repository.fetchByBarcode('123'), throwsA(isA<ProductNotFoundFailure>()));
    });

    test('un code 429 est traduit en limitation de debit', () async {
      final repository = repositoryReturning('{}', status: 429);
      expect(() => repository.fetchByBarcode('123'), throwsA(isA<RateLimitFailure>()));
    });

    test('une erreur serveur est signalee comme reessayable', () async {
      final repository = repositoryReturning('{}', status: 503);
      expect(
        () => repository.fetchByBarcode('123'),
        throwsA(isA<ProviderFailure>().having((failure) => failure.isRetryable, 'reessayable', isTrue)),
      );
    });

    test('une reponse illisible leve une erreur de format', () async {
      final repository = repositoryReturning('ceci n\'est pas du json');
      expect(() => repository.fetchByBarcode('123'), throwsA(isA<InvalidResponseFailure>()));
    });

    test('un second appel sur le meme code ne refait pas de requete', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(v3Payload(), 200);
      });
      final repository = OpenFoodFactsRepository(client: client);

      await repository.fetchByBarcode('3017620422003');
      await repository.fetchByBarcode('3017620422003');

      expect(calls, 1);
    });

    test('le nom anglais sert de repli lorsque le nom francais manque', () async {
      final repository = repositoryReturning(jsonEncode({
        'product': {
          'code': '123',
          'product_name': 'Chocolate spread',
          'nutrition': {
            'aggregated_set': {
              'nutrients': {
                'carbohydrates': {'value': 57.5},
              },
            },
          },
        },
      }));

      final food = await repository.fetchByBarcode('123');
      expect(food.name, 'Chocolate spread');
    });
  });

  group('Recherche de produits', () {
    String searchPayload() => jsonEncode({
          'count': 2,
          'hits': [
            {
              'code': '111',
              'product_name_fr': 'Yaourt nature',
              'brands': ['Marque A'],
              'nutriments': {'carbohydrates_100g': 4.5, 'energy-kcal_100g': 58},
            },
            {
              'code': '222',
              'product_name_fr': 'Yaourt aux fruits',
              'nutriments': {'carbohydrates_100g': 12.0, 'energy-kcal_100g': 90},
            },
          ],
        });

    test('les produits sans valeurs nutritionnelles sont ecartes', () async {
      final repository = repositoryReturning(jsonEncode({
        'hits': [
          {'code': '111', 'product_name_fr': 'Produit sans donnees'},
          {'code': '222', 'product_name_fr': 'Produit complet', 'nutriments': {'carbohydrates_100g': 10}},
        ],
      }));

      final results = await repository.search('yaourt');
      expect(results.length, 1);
      expect(results.first.name, 'Produit complet');
    });

    test('les resultats sont renvoyes quand ils portent des valeurs', () async {
      final repository = repositoryReturning(searchPayload());
      final results = await repository.search('yaourt');
      expect(results.length, 2);
      expect(results.map((food) => food.name), contains('Yaourt nature'));
    });

    test('une requete trop courte ne declenche aucune recherche', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('{"hits": []}', 200);
      });
      final repository = OpenFoodFactsRepository(client: client);

      expect(await repository.search('y'), isEmpty);
      expect(await repository.search(' '), isEmpty);
      expect(calls, 0);
    });

    test('une recherche deja effectuee est servie depuis le cache', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(searchPayload(), 200);
      });
      final repository = OpenFoodFactsRepository(client: client);

      await repository.search('yaourt');
      await repository.search('yaourt');

      expect(calls, 1);
    });

    test('une limitation de debit est signalee', () async {
      final repository = repositoryReturning('{}', status: 429);
      expect(() => repository.search('yaourt'), throwsA(isA<RateLimitFailure>()));
    });
  });
}
