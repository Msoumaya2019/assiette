import 'nutrition_values.dart';

/// Objectifs quotidiens personnels.
///
/// L'application ne propose aucun objectif par defaut et ne suggere jamais de
/// valeur : ces chiffres sont fournis par l'utilisateur ou par un professionnel
/// qui le suit. Aucun conseil therapeutique n'est genere a partir de ces
/// valeurs, et aucun objectif n'est presente comme une recommandation medicale.
class DailyGoals {
  const DailyGoals({
    this.carbsG,
    this.kcal,
    this.proteinG,
    this.fatG,
    this.fiberG,
  });

  static const DailyGoals none = DailyGoals();

  final double? carbsG;
  final double? kcal;
  final double? proteinG;
  final double? fatG;
  final double? fiberG;

  bool get isEmpty =>
      carbsG == null &&
      kcal == null &&
      proteinG == null &&
      fatG == null &&
      fiberG == null;

  bool get isNotEmpty => !isEmpty;

  DailyGoals copyWith({
    double? carbsG,
    double? kcal,
    double? proteinG,
    double? fatG,
    double? fiberG,
    bool clearCarbs = false,
    bool clearKcal = false,
    bool clearProtein = false,
    bool clearFat = false,
    bool clearFiber = false,
  }) {
    return DailyGoals(
      carbsG: clearCarbs ? null : (carbsG ?? this.carbsG),
      kcal: clearKcal ? null : (kcal ?? this.kcal),
      proteinG: clearProtein ? null : (proteinG ?? this.proteinG),
      fatG: clearFat ? null : (fatG ?? this.fatG),
      fiberG: clearFiber ? null : (fiberG ?? this.fiberG),
    );
  }

  Map<String, dynamic> toJson() => {
    'carbsG': carbsG,
    'kcal': kcal,
    'proteinG': proteinG,
    'fatG': fatG,
    'fiberG': fiberG,
  };

  factory DailyGoals.fromJson(Map<String, dynamic> json) {
    double? read(String key) => (json[key] as num?)?.toDouble();

    return DailyGoals(
      carbsG: read('carbsG'),
      kcal: read('kcal'),
      proteinG: read('proteinG'),
      fatG: read('fatG'),
      fiberG: read('fiberG'),
    );
  }
}

/// Progression vers un objectif, pour l'affichage.
class GoalProgress {
  const GoalProgress({
    required this.label,
    required this.consumed,
    required this.target,
    required this.unit,
  });

  final String label;
  final double consumed;
  final double target;
  final String unit;

  /// Ratio consomme / objectif. Peut depasser 1.
  double get ratio => target <= 0 ? 0 : consumed / target;

  /// Ratio borne a 1, pour le remplissage d'une barre de progression.
  double get clampedRatio => ratio.clamp(0.0, 1.0);

  double get remaining => target - consumed;

  bool get isExceeded => consumed > target;

  /// Construit la liste des progressions a afficher, en ignorant les objectifs
  /// non definis.
  static List<GoalProgress> from(DailyGoals goals, NutritionValues consumed) {
    final list = <GoalProgress>[];
    if (goals.carbsG != null) {
      list.add(
        GoalProgress(
          label: 'Glucides',
          consumed: consumed.carbs,
          target: goals.carbsG!,
          unit: 'g',
        ),
      );
    }
    if (goals.kcal != null) {
      list.add(
        GoalProgress(
          label: 'Calories',
          consumed: consumed.kcal,
          target: goals.kcal!,
          unit: 'kcal',
        ),
      );
    }
    if (goals.proteinG != null) {
      list.add(
        GoalProgress(
          label: 'Proteines',
          consumed: consumed.protein,
          target: goals.proteinG!,
          unit: 'g',
        ),
      );
    }
    if (goals.fatG != null) {
      list.add(
        GoalProgress(
          label: 'Lipides',
          consumed: consumed.fat,
          target: goals.fatG!,
          unit: 'g',
        ),
      );
    }
    if (goals.fiberG != null) {
      list.add(
        GoalProgress(
          label: 'Fibres',
          consumed: consumed.fiber,
          target: goals.fiberG!,
          unit: 'g',
        ),
      );
    }
    return list;
  }
}
