import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/food.dart';
import '../models/nutrition_values.dart';

/// Acces a la table de composition nutritionnelle Ciqual (ANSES).
///
/// Les donnees sont embarquees dans l'application : la recherche fonctionne
/// hors ligne, instantanement, sans requete reseau et sans limite de debit.
///
/// Source : Ciqual 2020, Agence nationale de securite sanitaire de l'alimentation,
/// de l'environnement et du travail. Licence Ouverte / Open Licence 2.0.
class CiqualRepository {
  CiqualRepository({this.assetPath = 'assets/nutrition/ciqual.json'});

  final String assetPath;

  List<Food> _foods = const [];
  Map<String, Food> _byCode = const {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  int get count => _foods.length;

  String get attribution => 'Table Ciqual 2020 — ANSES — Licence Ouverte 2.0';

  /// Charge la table en memoire. Idempotent : un second appel ne relit pas l'actif.
  Future<void> load() async {
    if (_loaded) return;
    final raw = await rootBundle.loadString(assetPath);
    loadFromJsonString(raw);
  }

  /// Charge la table depuis une chaine JSON.
  ///
  /// Expose separement de [load] pour que les tests puissent fournir un jeu de
  /// donnees maitrise, sans dependre du contenu exact de la table embarquee.
  void loadFromJsonString(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final entries = (decoded['foods'] as List).cast<Map<String, dynamic>>();

    final foods = <Food>[];
    final byCode = <String, Food>{};

    for (final entry in entries) {
      final food = _toFood(entry);
      foods.add(food);
      final code = food.sourceRef;
      if (code != null) byCode[code] = food;
    }

    _foods = foods;
    _byCode = byCode;
    _searchKeyCache.clear();
    _loaded = true;
  }

  Food _toFood(Map<String, dynamic> entry) {
    double read(String key) => (entry[key] as num?)?.toDouble() ?? 0;

    return Food(
      name: (entry['name'] as String).trim(),
      per100g: NutritionValues(
        kcal: read('kcal'),
        carbs: read('carbs'),
        sugars: read('sugars'),
        starch: read('starch'),
        protein: read('protein'),
        fat: read('fat'),
        fiber: read('fiber'),
        salt: read('salt'),
      ),
      source: FoodSource.ciqual,
      sourceRef: entry['code'] as String?,
      category: (entry['groupName'] as String?)?.trim().isEmpty ?? true
          ? null
          : (entry['groupName'] as String).trim(),
    );
  }

  /// Recherche par nom, insensible aux accents et a la casse.
  ///
  /// Le classement privilegie les noms qui commencent par la requete, puis ceux
  /// qui la contiennent : « riz » remonte « Riz blanc cuit » avant
  /// « Galette de riz ».
  List<Food> search(String query, {int limit = 30}) {
    final needle = normalizeForSearch(query);
    if (needle.isEmpty) return const [];

    final starts = <Food>[];
    final contains = <Food>[];

    for (final food in _foods) {
      final haystack = _searchKey(food);
      if (haystack.startsWith(needle)) {
        starts.add(food);
      } else if (haystack.contains(needle)) {
        contains.add(food);
      }
      if (starts.length >= limit) break;
    }

    final results = <Food>[...starts, ...contains];
    return results.length > limit ? results.sublist(0, limit) : results;
  }

  /// Retrouve un aliment par son code Ciqual.
  Food? byCode(String code) => _byCode[code];

  /// Retrouve l'aliment Ciqual le plus proche d'un nom detecte par l'analyse.
  ///
  /// Retourne `null` si aucun candidat n'est suffisamment proche : il vaut mieux
  /// demander une confirmation a l'utilisateur que d'attribuer de fausses
  /// valeurs nutritionnelles.
  Food? findBestMatch(String detectedName, {double minimumScore = 0.55}) {
    final needle = normalizeForSearch(detectedName);
    if (needle.isEmpty) return null;

    final tokens = needle.split(' ').where((token) => token.length > 2).toList();

    Food? best;
    var bestScore = 0.0;

    for (final food in _foods) {
      final haystack = _searchKey(food);
      var score = 0.0;

      if (haystack == needle) {
        score = 1.0;
      } else if (haystack.startsWith(needle)) {
        score = 0.9;
      } else if (haystack.contains(needle)) {
        score = 0.75;
      } else if (tokens.isNotEmpty) {
        final matched = tokens.where(haystack.contains).length;
        if (matched > 0) {
          score = 0.4 + (0.4 * matched / tokens.length);
        }
      }

      // Un aliment sans glucides ni energie n'aide pas : on le deprioritise.
      if (score > 0 && food.per100g.carbs == 0 && food.per100g.kcal == 0) {
        score -= 0.1;
      }

      if (score > bestScore) {
        bestScore = score;
        best = food;
      }
    }

    return bestScore >= minimumScore ? best : null;
  }

  /// Tous les aliments, tries par nom. Utilise pour l'exploration par categorie.
  List<Food> all() => _foods;

  /// Noms de groupes d'aliments presents dans la table.
  List<String> get categories {
    final set = <String>{};
    for (final food in _foods) {
      final category = food.category;
      if (category != null && category.isNotEmpty) set.add(category);
    }
    final list = set.toList()..sort();
    return list;
  }

  // La cle de recherche est calculee une fois puis mise en cache : la table
  // fait plusieurs milliers d'entrees et la recherche doit rester instantanee.
  final Map<String, String> _searchKeyCache = {};

  String _searchKey(Food food) =>
      _searchKeyCache.putIfAbsent(food.sourceRef ?? food.name, () => normalizeForSearch(food.name));
}

/// Minuscule sans accents, espaces normalises.
///
/// Implemente sans dependance externe pour rester testable et previsible sur
/// toutes les plateformes.
String normalizeForSearch(String input) {
  const replacements = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
    'ç': 'c',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ñ': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'ý': 'y', 'ÿ': 'y',
    'ß': 'ss',
    'œ': 'oe', 'æ': 'ae',
  };

  final lower = input.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(replacements[char] ?? char);
  }

  return buffer
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}
