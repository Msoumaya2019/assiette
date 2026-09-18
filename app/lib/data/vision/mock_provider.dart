import 'dart:math';

import '../../models/analysis_result.dart';
import '../../models/nutrition_values.dart';
import 'vision_provider.dart';

/// Fournisseur de developpement, utilise uniquement pour travailler l'interface
/// sans consommer d'appels payants.
///
/// Les aliments renvoyes sont des **donnees de test**, clairement signalees
/// comme telles dans l'interface (bandeau « mode demonstration »). Ce
/// fournisseur n'est jamais selectionne en production : il n'est disponible que
/// lorsque la compilation est en mode developpement.
class MockVisionProvider implements VisionProvider {
  MockVisionProvider({this.delay = const Duration(milliseconds: 1200)});

  final Duration delay;
  final Random _random = Random(42);

  @override
  String get id => 'mock';

  @override
  String get label => 'Mode demonstration (donnees de test)';

  @override
  bool get isConfigured => true;

  @override
  Future<MealAnalysisResult> analyzeMeal(MealAnalysisRequest request) async {
    await Future<void>.delayed(delay);

    const candidates = <(String, double)>[
      ('Riz blanc cuit', 180),
      ('Poulet grille', 140),
      ('Haricots verts', 120),
      ('Pain baguette', 55),
      ('Tomate', 90),
      ('Pomme de terre vapeur', 200),
      ('Salade verte', 70),
      ('Fromage a pate dure', 35),
    ];

    final count = 2 + _random.nextInt(2);
    final picked = <DetectedFood>[];
    final used = <int>{};

    while (picked.length < count) {
      final index = _random.nextInt(candidates.length);
      if (used.contains(index)) continue;
      used.add(index);

      final (name, weight) = candidates[index];
      picked.add(
        DetectedFood(
          name: name,
          estimatedWeightG: weight.toDouble(),
          confidence: 0.55 + _random.nextDouble() * 0.4,
        ),
      );
    }

    return MealAnalysisResult(
      foods: picked,
      overallConfidence: picked.map((f) => f.confidence).reduce((a, b) => a + b) / picked.length,
      notes: 'Donnees de demonstration : aucune analyse reelle n\'a ete effectuee.',
      promptVersion: 'mock',
    );
  }

  @override
  Future<LabelExtraction> analyzeLabel(LabelAnalysisRequest request) async {
    await Future<void>.delayed(delay);

    return const LabelExtraction(
      per100g: NutritionValues(
        kcal: 412,
        carbs: 66.3,
        sugars: 24.1,
        protein: 7.8,
        fat: 12.5,
        fiber: 5.4,
        salt: 0.62,
      ),
      confidence: 0.72,
      productName: 'Produit de demonstration',
      brand: 'Donnees de test',
      packageQuantity: '375 g',
      notes: 'Donnees de demonstration : aucune lecture reelle n\'a ete effectuee.',
      saturatedFat: 4.2,
    );
  }
}
