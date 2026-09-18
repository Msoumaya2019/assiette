import '../core/failures.dart';
import '../data/ciqual_repository.dart';
import '../data/vision/vision_provider.dart';
import '../models/analysis_result.dart';
import '../models/food.dart';
import '../models/meal.dart';
import '../models/nutrition_values.dart';

/// Resultat de l'analyse d'un repas par photo, pret a etre presente.
class MealAnalysisOutcome {
  const MealAnalysisOutcome({
    required this.meal,
    required this.result,
    required this.unmatched,
  });

  /// Repas pret a etre affiche et modifie. Les quantites restent des estimations.
  final Meal meal;

  /// Reponse brute du moteur, conservee pour l'affichage de la confiance.
  final MealAnalysisResult result;

  /// Noms d'aliments detectes mais absents de la table de reference. Ils sont
  /// conserves sans valeurs nutritionnelles plutot que d'inventer des chiffres.
  final List<String> unmatched;

  bool get hasUnmatched => unmatched.isNotEmpty;
}

/// Orchestre l'analyse d'un repas : detection visuelle, puis correspondance avec
/// la table de reference.
///
/// La separation est volontaire. Le modele d'analyse ne fournit que des noms et
/// des poids ; les valeurs nutritionnelles viennent toujours d'une base de
/// reference. Une estimation visuelle ne peut donc jamais produire un chiffre
/// de glucides invente.
class MealAnalysisService {
  MealAnalysisService({required this.vision, required this.ciqual});

  final VisionProvider vision;
  final CiqualRepository ciqual;

  Future<MealAnalysisOutcome> analyze(MealAnalysisRequest request, {DateTime? eatenAt}) async {
    await ciqual.load();

    final result = await vision.analyzeMeal(request);
    if (result.isEmpty) {
      throw const NoFoodDetectedFailure();
    }

    final items = <MealItem>[];
    final unmatched = <String>[];

    for (var index = 0; index < result.foods.length; index++) {
      final detected = result.foods[index];
      final match = ciqual.findBestMatch(detected.name);

      if (match == null) {
        unmatched.add(detected.name);
        // On conserve tout de meme l'aliment, sans valeurs : l'utilisateur peut
        // le rechercher lui-meme et completer les donnees.
        items.add(
          MealItem(
            food: Food(
              name: detected.name,
              per100g: NutritionValues.zero,
              source: FoodSource.ai,
            ),
            quantityG: detected.estimatedWeightG > 0 ? detected.estimatedWeightG : 100,
            confidence: detected.confidence,
            isEstimate: true,
            sortOrder: index,
          ),
        );
        continue;
      }

      items.add(
        MealItem(
          food: match,
          quantityG: detected.estimatedWeightG > 0 ? detected.estimatedWeightG : 100,
          confidence: detected.confidence,
          isEstimate: true,
          sortOrder: index,
        ),
      );
    }

    final meal = Meal(
      eatenAt: eatenAt ?? DateTime.now(),
      name: _suggestMealName(eatenAt ?? DateTime.now()),
      items: items,
      source: MealSource.photo,
      isEstimate: true,
    );

    return MealAnalysisOutcome(meal: meal, result: result, unmatched: unmatched);
  }

  /// Nom de repas propose d'apres l'heure : l'utilisateur n'a presque jamais a
  /// le corriger.
  static String _suggestMealName(DateTime at) {
    final hour = at.hour;
    if (hour < 11) return 'Petit-dejeuner';
    if (hour < 15) return 'Dejeuner';
    if (hour < 18) return 'Collation';
    return 'Diner';
  }
}
