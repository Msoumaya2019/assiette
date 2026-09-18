import 'dart:math' as math;

/// Valeurs nutritionnelles, toujours stockees **pour 100 g** (ou 100 ml pour
/// les boissons). Le passage a une quantite consommee se fait par [forGrams].
///
/// Ce choix est delibere : modifier une portion ne doit jamais dependre d'un
/// total deja calcule, sinon les erreurs d'arrondi s'accumulent.
class NutritionValues {
  const NutritionValues({
    this.kcal = 0,
    this.carbs = 0,
    this.sugars = 0,
    this.starch = 0,
    this.protein = 0,
    this.fat = 0,
    this.saturatedFat = 0,
    this.fiber = 0,
    this.salt = 0,
  });

  static const NutritionValues zero = NutritionValues();

  /// Energie en kilocalories.
  final double kcal;

  /// Glucides totaux en grammes. **Donnee principale de l'application.**
  final double carbs;

  /// Sucres en grammes (sous-ensemble des glucides).
  final double sugars;

  /// Amidon en grammes (sous-ensemble des glucides).
  final double starch;

  /// Proteines en grammes.
  final double protein;

  /// Lipides en grammes.
  final double fat;

  /// Acides gras satures en grammes.
  final double saturatedFat;

  /// Fibres alimentaires en grammes.
  final double fiber;

  /// Sel en grammes.
  final double salt;

  /// Valeurs pour une quantite donnee, proportionnelles au poids.
  NutritionValues forGrams(double grams) {
    if (grams <= 0) return zero;
    final factor = grams / 100.0;
    return NutritionValues(
      kcal: kcal * factor,
      carbs: carbs * factor,
      sugars: sugars * factor,
      starch: starch * factor,
      protein: protein * factor,
      fat: fat * factor,
      saturatedFat: saturatedFat * factor,
      fiber: fiber * factor,
      salt: salt * factor,
    );
  }

  NutritionValues operator +(NutritionValues other) => NutritionValues(
        kcal: kcal + other.kcal,
        carbs: carbs + other.carbs,
        sugars: sugars + other.sugars,
        starch: starch + other.starch,
        protein: protein + other.protein,
        fat: fat + other.fat,
        saturatedFat: saturatedFat + other.saturatedFat,
        fiber: fiber + other.fiber,
        salt: salt + other.salt,
      );

  NutritionValues operator -(NutritionValues other) => NutritionValues(
        kcal: kcal - other.kcal,
        carbs: carbs - other.carbs,
        sugars: sugars - other.sugars,
        starch: starch - other.starch,
        protein: protein - other.protein,
        fat: fat - other.fat,
        saturatedFat: saturatedFat - other.saturatedFat,
        fiber: fiber - other.fiber,
        salt: salt - other.salt,
      );

  /// Addition en ignorant les valeurs nulles, sans risque d'erreur d'arrondi.
  static NutritionValues sum(Iterable<NutritionValues> values) {
    var total = zero;
    for (final value in values) {
      total = total + value;
    }
    return total;
  }

  /// Energie estimee par la formule d'Atwater, utilisee uniquement pour detecter
  /// une incoherence entre l'energie declaree et les macronutriments.
  double get atwaterKcal => carbs * 4 + protein * 4 + fat * 9;

  /// Vrai si l'energie declaree s'ecarte fortement de la valeur calculee.
  /// Sert d'indicateur de qualite des donnees, jamais de correction automatique.
  bool get energyIsInconsistent {
    if (kcal <= 0 || atwaterKcal <= 0) return false;
    final deviation = (kcal - atwaterKcal).abs() / math.max(kcal, atwaterKcal);
    return deviation > 0.35;
  }

  /// Part des glucides provenant des sucres, entre 0 et 1. Utile pour signaler
  /// les aliments a index glycemique eleve sans formuler de conseil medical.
  double get sugarShare => carbs <= 0 ? 0 : (sugars / carbs).clamp(0.0, 1.0);

  bool get isNotEmpty =>
      kcal > 0 || carbs > 0 || protein > 0 || fat > 0 || fiber > 0 || sugars > 0 || salt > 0;

  Map<String, dynamic> toJson() => {
        'kcal': kcal,
        'carbs': carbs,
        'sugars': sugars,
        'starch': starch,
        'protein': protein,
        'fat': fat,
        'saturatedFat': saturatedFat,
        'fiber': fiber,
        'salt': salt,
      };

  factory NutritionValues.fromJson(Map<String, dynamic> json) {
    double read(String key) {
      final value = json[key];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0;
      return 0;
    }

    return NutritionValues(
      kcal: read('kcal'),
      carbs: read('carbs'),
      sugars: read('sugars'),
      starch: read('starch'),
      protein: read('protein'),
      fat: read('fat'),
      saturatedFat: read('saturatedFat'),
      fiber: read('fiber'),
      salt: read('salt'),
    );
  }

  @override
  String toString() =>
      'NutritionValues(kcal: $kcal, carbs: $carbs, protein: $protein, fat: $fat, fiber: $fiber)';
}
