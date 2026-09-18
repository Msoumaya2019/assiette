import 'dart:convert';
import 'dart:typed_data';

import '../../core/failures.dart';
import '../../models/analysis_result.dart';
import '../../models/nutrition_values.dart';

/// Demande d'analyse d'un repas.
class MealAnalysisRequest {
  const MealAnalysisRequest({
    required this.image,
    this.mimeType = 'image/jpeg',
    this.secondImage,
    this.secondMimeType,
    this.portionHint,
    this.userHint,
  });

  final Uint8List image;
  final String mimeType;
  final Uint8List? secondImage;
  final String? secondMimeType;

  /// « small », « medium » ou « large ».
  final String? portionHint;

  /// Precision libre saisie par l'utilisateur.
  final String? userHint;

  bool get hasSecondImage => secondImage != null && secondImage!.isNotEmpty;
}

/// Demande d'analyse d'une etiquette nutritionnelle.
class LabelAnalysisRequest {
  const LabelAnalysisRequest({
    required this.image,
    this.mimeType = 'image/jpeg',
    this.secondImage,
    this.secondMimeType,
  });

  final Uint8List image;
  final String mimeType;
  final Uint8List? secondImage;
  final String? secondMimeType;

  bool get hasSecondImage => secondImage != null && secondImage!.isNotEmpty;
}

/// Contrat du moteur d'analyse d'image.
///
/// Deux implementations coexistent : l'appel direct avec la cle de
/// l'utilisateur, et l'appel a une fonction serveur qui detient la cle. Le reste
/// de l'application ne connait que cette interface, ce qui permet de changer de
/// fournisseur sans toucher a l'interface utilisateur.
abstract class VisionProvider {
  /// Identifiant technique, utilise pour la journalisation.
  String get id;

  /// Nom affiche dans les reglages.
  String get label;

  /// Vrai si le fournisseur dispose de tout ce qu'il faut pour fonctionner.
  bool get isConfigured;

  Future<MealAnalysisResult> analyzeMeal(MealAnalysisRequest request);

  Future<LabelExtraction> analyzeLabel(LabelAnalysisRequest request);
}

// ---------------------------------------------------------------------------
// Normalisation des reponses
//
// Le modele est une source non fiable : tout ce qui en sort est valide,
// borne et nettoye avant d'atteindre le reste de l'application.
// ---------------------------------------------------------------------------

double _readDouble(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.replaceAll(',', '.')) ?? fallback;
  }
  return fallback;
}

double? _readNullableDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.replaceAll(',', '.'));
  return null;
}

/// Extrait un objet JSON d'une reponse de modele, en tolerant le balisage
/// Markdown et le texte parasite autour de l'objet.
Object? extractJsonObject(String raw) {
  final cleaned = raw.replaceFirst('\uFEFF', '').trim();
  final withoutFence = cleaned
      .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\s*```$'), '')
      .trim();

  try {
    return jsonDecode(withoutFence);
  } on FormatException {
    // Repli : premier objet equilibre du texte, en respectant les chaines.
    final start = withoutFence.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < withoutFence.length; i++) {
      final char = withoutFence[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == '"') inString = !inString;
      if (inString) continue;
      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) {
          try {
            return jsonDecode(withoutFence.substring(start, i + 1));
          } on FormatException {
            return null;
          }
        }
      }
    }
    return null;
  }
}

/// Convertit la reponse brute du modele en resultat exploitable.
MealAnalysisResult parseMealAnalysis(String raw, {String? promptVersion}) {
  final decoded = extractJsonObject(raw);
  if (decoded is! Map) {
    throw const InvalidResponseFailure();
  }

  final rawFoods = decoded['foods'];
  final foods = <DetectedFood>[];

  if (rawFoods is List) {
    for (final entry in rawFoods.take(25)) {
      if (entry is! Map) continue;
      final name = (entry['name'] as Object?)?.toString().trim() ?? '';
      if (name.isEmpty) continue;

      final weight = _readDouble(entry['estimatedWeightG']);
      final confidence = _readDouble(
        entry['confidence'],
        fallback: 0.5,
      ).clamp(0.0, 1.0);

      foods.add(
        DetectedFood(
          name: name.length > 120 ? name.substring(0, 120) : name,
          estimatedWeightG: weight > 0 ? weight.clamp(1, 5000) : 0,
          confidence: confidence,
        ),
      );
    }
  }

  var overall = _readDouble(decoded['overallConfidence'], fallback: -1);
  if (overall < 0) {
    overall = foods.isEmpty
        ? 0
        : foods.map((f) => f.confidence).reduce((a, b) => a + b) / foods.length;
  }

  final notes = (decoded['notes'] as Object?)?.toString().trim();

  return MealAnalysisResult(
    foods: foods,
    overallConfidence: overall.clamp(0.0, 1.0),
    notes: notes == null || notes.isEmpty
        ? null
        : (notes.length > 500 ? notes.substring(0, 500) : notes),
    promptVersion: promptVersion,
  );
}

/// Convertit la reponse brute du modele en valeurs d'etiquette.
LabelExtraction parseLabelExtraction(String raw, {String? promptVersion}) {
  final decoded = extractJsonObject(raw);
  if (decoded is! Map) {
    throw const InvalidResponseFailure();
  }

  String? text(Object? value, int max) {
    final string = value?.toString().trim();
    if (string == null || string.isEmpty || string == 'null') return null;
    return string.length > max ? string.substring(0, max) : string;
  }

  double? positive(Object? value) {
    final parsed = _readNullableDouble(value);
    if (parsed == null || parsed < 0 || parsed > 100000) return null;
    return parsed;
  }

  final per100g = NutritionValues(
    kcal: positive(decoded['energyKcal']) ?? 0,
    carbs: positive(decoded['carbohydrates']) ?? 0,
    sugars: positive(decoded['sugars']) ?? 0,
    protein: positive(decoded['proteins']) ?? 0,
    fat: positive(decoded['fat']) ?? 0,
    fiber: positive(decoded['fiber']) ?? 0,
    salt: positive(decoded['salt']) ?? 0,
  );

  return LabelExtraction(
    per100g: per100g,
    confidence: _readDouble(
      decoded['confidence'],
      fallback: 0.5,
    ).clamp(0.0, 1.0),
    productName: text(decoded['productName'], 120),
    brand: text(decoded['brand'], 80),
    packageQuantity: text(decoded['packageQuantity'], 40),
    basis: decoded['basis'] == '100ml' ? '100ml' : '100g',
    notes: text(decoded['notes'], 400),
    saturatedFat: positive(decoded['saturatedFat']),
  );
}
