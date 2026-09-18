import '../models/goals.dart';
import '../models/meal.dart';
import '../models/nutrition_values.dart';

/// Une entree du tableau de bord : une date et les totaux correspondants.
class DailyBucket {
  const DailyBucket({required this.date, required this.totals, required this.mealCount});

  final DateTime date;
  final NutritionValues totals;
  final int mealCount;

  /// Jour calendaire, sans composante horaire.
  static DateTime dayOf(DateTime date) => DateTime(date.year, date.month, date.day);
}

/// Calculs nutritionnels agreges.
///
/// Toutes les fonctions sont pures : elles ne lisent ni base de donnees ni
/// reseau, ce qui les rend directement testables et empeche les incoherences
/// entre l'affichage et le stockage.
class NutritionCalculator {
  const NutritionCalculator._();

  /// Totaux d'une liste de repas.
  static NutritionValues totalOf(Iterable<Meal> meals) {
    var total = NutritionValues.zero;
    for (final meal in meals) {
      total = total + meal.totals;
    }
    return total;
  }

  /// Repas compris entre deux instants, bornes incluses a la seconde pres.
  static List<Meal> between(Iterable<Meal> meals, DateTime start, DateTime end) {
    return meals.where((meal) {
      final at = meal.eatenAt;
      return !at.isBefore(start) && !at.isAfter(end);
    }).toList();
  }

  /// Repas d'un jour calendaire donne.
  static List<Meal> forDay(Iterable<Meal> meals, DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1)).subtract(const Duration(microseconds: 1));
    return between(meals, start, end);
  }

  /// Totaux du jour.
  static NutritionSummary summaryForDay(Iterable<Meal> meals, DateTime day) {
    final selected = forDay(meals, day);
    return NutritionSummary(totals: totalOf(selected), mealCount: selected.length);
  }

  /// Serie journaliere sur les [days] derniers jours, du plus ancien au plus recent.
  ///
  /// Les jours sans repas sont presents avec des totaux nuls : le graphique doit
  /// montrer les interruptions, pas les masquer.
  static List<DailyBucket> dailySeries(
    Iterable<Meal> meals,
    DateTime reference, {
    int days = 7,
  }) {
    final end = DailyBucket.dayOf(reference);
    final start = end.subtract(Duration(days: days - 1));

    // Regroupement en une passe : la liste des repas peut devenir longue.
    final grouped = <DateTime, List<Meal>>{};
    for (final meal in between(meals, start, end.add(const Duration(days: 1)))) {
      final key = DailyBucket.dayOf(meal.eatenAt);
      grouped.putIfAbsent(key, () => <Meal>[]).add(meal);
    }

    final buckets = <DailyBucket>[];
    for (var i = 0; i < days; i++) {
      final day = start.add(Duration(days: i));
      final items = grouped[day] ?? const <Meal>[];
      buckets.add(
        DailyBucket(date: day, totals: totalOf(items), mealCount: items.length),
      );
    }
    return buckets;
  }

  /// Serie hebdomadaire sur les [weeks] dernieres semaines.
  ///
  /// Les semaines commencent le lundi.
  static List<DailyBucket> weeklySeries(
    Iterable<Meal> meals,
    DateTime reference, {
    int weeks = 6,
  }) {
    final today = DailyBucket.dayOf(reference);
    final currentMonday = today.subtract(Duration(days: today.weekday - 1));
    final firstMonday = currentMonday.subtract(Duration(days: 7 * (weeks - 1)));

    final buckets = <DailyBucket>[];
    for (var i = 0; i < weeks; i++) {
      final weekStart = firstMonday.add(Duration(days: i * 7));
      final weekEnd = weekStart.add(const Duration(days: 7));
      final items = between(meals, weekStart, weekEnd.subtract(const Duration(microseconds: 1)));
      buckets.add(
        DailyBucket(date: weekStart, totals: totalOf(items), mealCount: items.length),
      );
    }
    return buckets;
  }

  /// Moyenne des totaux sur les jours ou au moins un repas a ete enregistre.
  ///
  /// Les jours vides sont exclus : sans cela, une semaine d'absence ferait
  /// chuter artificiellement la moyenne et donnerait une lecture fausse.
  static NutritionValues averagePerActiveDay(List<DailyBucket> buckets) {
    final active = buckets.where((bucket) => bucket.mealCount > 0).toList();
    if (active.isEmpty) return NutritionValues.zero;

    var total = NutritionValues.zero;
    for (final bucket in active) {
      total = total + bucket.totals;
    }

    final factor = 1 / active.length;
    return NutritionValues(
      kcal: total.kcal * factor,
      carbs: total.carbs * factor,
      sugars: total.sugars * factor,
      starch: total.starch * factor,
      protein: total.protein * factor,
      fat: total.fat * factor,
      saturatedFat: total.saturatedFat * factor,
      fiber: total.fiber * factor,
      salt: total.salt * factor,
    );
  }

  /// Progression vers les objectifs du jour.
  static List<GoalProgress> progress(DailyGoals goals, NutritionSummary summary) =>
      GoalProgress.from(goals, summary.totals);

  /// Repartition des glucides par repas, pour un graphique en anneau.
  static Map<String, double> carbsByMeal(Iterable<Meal> meals) {
    final result = <String, double>{};
    for (final meal in meals) {
      result[meal.name] = (result[meal.name] ?? 0) + meal.totals.carbs;
    }
    return result;
  }

  /// Fourchette d'incertitude autour d'un total de glucides estime.
  ///
  /// L'incertitude grandit avec la part du repas issue d'une estimation
  /// visuelle. Un aliment pese a la main n'ajoute aucune incertitude.
  static (double, double) carbsRange(Meal meal, {double defaultMargin = 0.12}) {
    final totalCarbs = meal.totals.carbs;
    if (totalCarbs <= 0) return (0, 0);

    // Marge par aliment estime, ponderee par la confiance declaree.
    // Un aliment pese a la main ne porte pas de confiance : il n'entre donc pas
    // dans la moyenne et n'elargit pas la fourchette.
    var weightedMargin = 0.0;
    var weight = 0.0;
    for (final item in meal.items) {
      final confidence = item.confidence;
      if (confidence == null) continue;
      final margin = defaultMargin + (1 - confidence) * 0.35;
      weightedMargin += margin * item.total.carbs;
      weight += item.total.carbs;
    }

    final margin = weight > 0 ? weightedMargin / weight : defaultMargin;
    final absolute = totalCarbs * margin;

    return ((totalCarbs - absolute).clamp(0, double.infinity), totalCarbs + absolute);
  }
}
