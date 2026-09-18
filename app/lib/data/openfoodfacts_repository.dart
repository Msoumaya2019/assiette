import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/failures.dart';
import '../models/food.dart';
import '../models/nutrition_values.dart';

/// Acces a la base Open Food Facts pour les produits industriels.
///
/// Deux usages : lecture d'un produit par code-barres, et recherche par nom.
///
/// L'API v3.6 renvoie les nutriments sous `product.nutrition.aggregated_set.nutrients`,
/// alors que l'API v2 (encore servie) utilise un dictionnaire plat suffixe
/// `_100g`. Les deux formes sont acceptees : le format de reponse a deja change
/// une fois, la lecture ne doit pas casser au prochain changement.
///
/// Base de donnees publiee sous licence ODbL ; attribution obligatoire.
class OpenFoodFactsRepository {
  OpenFoodFactsRepository({http.Client? client, this.baseUrl = 'https://world.openfoodfacts.org'})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  static const Duration _timeout = Duration(seconds: 20);

  /// L'API limite a 15 requetes par minute et par IP pour la lecture produit,
  /// et 10 pour la recherche. Un cache memoire evite de gaspiller ce quota
  /// lorsque l'utilisateur revient sur un produit deja consulte.
  final Map<String, Food> _productCache = {};
  final Map<String, List<Food>> _searchCache = {};

  String get attribution => 'Donnees Open Food Facts — ODbL';

  Map<String, String> get _headers => {
        'User-Agent': AppConfig.openFoodFactsUserAgent,
        'Accept': 'application/json',
      };

  /// Lit un produit par son code-barres.
  ///
  /// Leve [ProductNotFoundFailure] si le code est absent de la base.
  Future<Food> fetchByBarcode(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) throw ProductNotFoundFailure(barcode);

    final cached = _productCache[code];
    if (cached != null) return cached;

    final uri = Uri.parse('$baseUrl/api/v3.6/product/$code.json');

    final Map<String, dynamic> payload;
    try {
      final response = await _client.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode == 404) throw ProductNotFoundFailure(code);
      if (response.statusCode == 429) throw const RateLimitFailure();
      if (response.statusCode >= 500) {
        throw const ProviderFailure(
          'La base de produits est momentanement indisponible',
          hint: 'Reessayez dans un instant, ou saisissez l\'aliment a la main.',
          isRetryable: true,
        );
      }
      if (response.statusCode != 200) {
        throw ProviderFailure('Reponse inattendue de la base de produits', statusCode: response.statusCode);
      }
      payload = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on AppFailure {
      rethrow;
    } on SocketException {
      throw const NetworkFailure();
    } on http.ClientException {
      throw const NetworkFailure();
    } on FormatException {
      throw const InvalidResponseFailure();
    }

    final product = payload['product'];
    if (product is! Map) throw ProductNotFoundFailure(code);

    final food = _toFood(product.cast<String, dynamic>(), barcode: code);
    if (food == null) throw ProductNotFoundFailure(code);

    _productCache[code] = food;
    return food;
  }

  /// Recherche des produits par nom.
  ///
  /// Utilise Search-a-licious, le moteur de recherche plein texte d'Open Food
  /// Facts : l'API historique ne sait faire que des recherches structurees.
  Future<List<Food>> search(String query, {int limit = 20}) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];

    final cacheKey = '$trimmed/$limit';
    final cached = _searchCache[cacheKey];
    if (cached != null) return cached;

    final uri = Uri.parse(
      'https://search.openfoodfacts.org/search'
      '?q=${Uri.encodeQueryComponent(trimmed)}'
      '&page_size=$limit'
      '&fields=code,product_name,product_name_fr,brands,image_front_small_url,quantity,serving_size,nutriments',
    );

    try {
      final response = await _client.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode == 429) throw const RateLimitFailure();
      if (response.statusCode != 200) return const [];

      final payload = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final hits = (payload['hits'] as List?) ?? const [];

      final foods = <Food>[];
      for (final hit in hits) {
        if (hit is! Map) continue;
        final food = _toFood(hit.cast<String, dynamic>(), requireNutrients: true);
        if (food != null) foods.add(food);
      }

      // Les produits complets et francais d'abord : c'est le cas d'usage courant.
      foods.sort((a, b) {
        final aScore = _relevance(a, trimmed);
        final bScore = _relevance(b, trimmed);
        return bScore.compareTo(aScore);
      });

      _searchCache[cacheKey] = foods;
      return foods;
    } on AppFailure {
      rethrow;
    } on SocketException {
      throw const NetworkFailure();
    } on http.ClientException {
      throw const NetworkFailure();
    } on FormatException {
      throw const InvalidResponseFailure();
    }
  }

  double _relevance(Food food, String query) {
    var score = 0.0;
    if (food.per100g.isNotEmpty) score += 2;
    if (food.imageUrl != null) score += 0.5;
    if (food.servingSizeG != null) score += 0.3;
    final name = food.name.toLowerCase();
    if (name.startsWith(query.toLowerCase())) score += 1;
    return score;
  }

  /// Convertit un produit brut en [Food]. Retourne `null` si inexploitable.
  Food? _toFood(
    Map<String, dynamic> product, {
    String? barcode,
    bool requireNutrients = false,
  }) {
    final name = _firstNonEmpty([
      product['product_name_fr'],
      product['product_name'],
      product['generic_name_fr'],
    ]);
    if (name == null) return null;

    final per100g = _readNutrients(product);
    if (requireNutrients && per100g.isNotEmpty == false) return null;

    final brands = product['brands']?.toString().trim();
    final code = (product['code']?.toString() ?? barcode ?? '').trim();

    return Food(
      name: name,
      per100g: per100g,
      source: FoodSource.openFoodFacts,
      sourceRef: code.isEmpty ? null : code,
      brand: brands == null || brands.isEmpty ? null : brands.split(',').first.trim(),
      imageUrl: _firstNonEmpty([
        product['image_front_small_url'],
        product['image_front_url'],
        product['image_url'],
      ]),
      servingSizeG: _parseServingSize(product['serving_size']?.toString()),
      servingLabel: _firstNonEmpty([product['serving_size']?.toString()]),
    );
  }

  /// Lit les nutriments, en acceptant la forme v3 et la forme v2.
  NutritionValues _readNutrients(Map<String, dynamic> product) {
    // Forme v3 : product.nutrition.aggregated_set.nutrients.<cle>.value
    final nutrition = product['nutrition'];
    if (nutrition is Map) {
      final aggregated = nutrition['aggregated_set'];
      if (aggregated is Map) {
        final nutrients = aggregated['nutrients'];
        if (nutrients is Map && nutrients.isNotEmpty) {
          double read(String key) {
            final entry = nutrients[key];
            if (entry is Map) {
              final value = entry['value'];
              if (value is num) return value.toDouble();
            }
            return 0;
          }

          final values = NutritionValues(
            kcal: read('energy-kcal'),
            carbs: read('carbohydrates'),
            sugars: read('sugars'),
            starch: read('starch'),
            protein: read('proteins'),
            fat: read('fat'),
            saturatedFat: read('saturated-fat'),
            fiber: read('fiber'),
            salt: read('salt'),
          );
          if (values.isNotEmpty) return values;
        }
      }
    }

    // Forme v2 : dictionnaire plat suffixe `_100g`.
    final flat = product['nutriments'];
    if (flat is Map && flat.isNotEmpty) {
      double read(String key) {
        final value = flat['${key}_100g'] ?? flat[key];
        if (value is num) return value.toDouble();
        if (value is String) return double.tryParse(value) ?? 0;
        return 0;
      }

      final values = NutritionValues(
        kcal: read('energy-kcal'),
        carbs: read('carbohydrates'),
        sugars: read('sugars'),
        starch: read('starch'),
        protein: read('proteins'),
        fat: read('fat'),
        saturatedFat: read('saturated-fat'),
        fiber: read('fiber'),
        salt: read('salt'),
      );
      if (values.isNotEmpty) return values;
    }

    return NutritionValues.zero;
  }

  /// Analyse « 125 g », « 1 pot (125 g) », « 250ml ».
  double? _parseServingSize(String? text) {
    if (text == null || text.isEmpty) return null;
    final match = RegExp(r'(\d+(?:[.,]\d+)?)\s*(g|ml)\b', caseSensitive: false).firstMatch(text);
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!.replaceAll(',', '.'));
    if (value == null || value <= 0 || value > 5000) return null;
    return value;
  }

  String? _firstNonEmpty(List<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return null;
  }
}
