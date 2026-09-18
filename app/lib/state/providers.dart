import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../data/ciqual_repository.dart';
import '../data/local/app_database.dart';
import '../data/openfoodfacts_repository.dart';
import '../data/vision/deepseek_provider.dart';
import '../data/vision/mock_provider.dart';
import '../data/vision/proxy_provider.dart';
import '../data/vision/vision_provider.dart';
import '../models/app_settings.dart';
import '../models/goals.dart';
import '../models/meal.dart';
import '../models/nutrition_values.dart';
import '../services/image_service.dart';
import '../services/meal_analysis_service.dart';
import '../services/notification_service.dart';
import '../services/nutrition_calculator.dart';
import '../services/secure_store.dart';

// ---------------------------------------------------------------------------
// Dependances chargees au demarrage
//
// La base de donnees, la table Ciqual et les reglages sont ouverts avant
// `runApp` puis injectes ici. Les providers restent ainsi synchrones, ce qui
// evite les etats de chargement partout dans l'interface.
// ---------------------------------------------------------------------------

final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('appDatabaseProvider doit etre surcharge au demarrage'),
);

final ciqualRepositoryProvider = Provider<CiqualRepository>(
  (ref) => throw UnimplementedError('ciqualRepositoryProvider doit etre surcharge au demarrage'),
);

final secureStoreProvider = Provider<SecureStore>(
  (ref) => throw UnimplementedError('secureStoreProvider doit etre surcharge au demarrage'),
);

/// Reglages charges avant le premier affichage.
final initialSettingsProvider = Provider<AppSettings>(
  (ref) => throw UnimplementedError('initialSettingsProvider doit etre surcharge au demarrage'),
);

final openFoodFactsProvider = Provider<OpenFoodFactsRepository>((ref) => OpenFoodFactsRepository());

final imageServiceProvider = Provider<ImageService>((ref) => ImageService());

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => throw UnimplementedError('notificationServiceProvider doit etre surcharge au demarrage'),
);

// ---------------------------------------------------------------------------
// Reglages
// ---------------------------------------------------------------------------

/// Reglages de l'application, persistes a chaque modification.
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(initialSettingsProvider);

  Future<void> _persist(AppSettings next) async {
    // On ne reprogramme les rappels que si un reglage qui les concerne a
    // change : replanifier trente notifications a chaque bascule de theme
    // serait un gaspillage.
    final rappelsModifies = next.mealRemindersEnabled != state.mealRemindersEnabled ||
        next.dailySummaryEnabled != state.dailySummaryEnabled ||
        next.reminderHour != state.reminderHour ||
        next.reminderMinute != state.reminderMinute;

    state = next;
    final database = ref.read(appDatabaseProvider);
    await database.writeSetting('theme_mode', next.themeMode.name);
    await database.writeSetting('analysis_mode', next.analysisMode.name);
    await database.writeSetting('onboarding_done', next.onboardingDone ? '1' : '0');
    await database.writeSetting('keep_photos', next.keepPhotos ? '1' : '0');
    await database.writeSetting('meal_reminders', next.mealRemindersEnabled ? '1' : '0');
    await database.writeSetting('daily_summary', next.dailySummaryEnabled ? '1' : '0');
    await database.writeSetting('reminder_hour', next.reminderHour.toString());
    await database.writeSetting('reminder_minute', next.reminderMinute.toString());
    await database.writeSetting('disclaimer_seen', next.useEstimatesDisclaimerSeen ? '1' : '0');
    if (next.privacyPolicyAcceptedVersion != null) {
      await database.writeSetting('privacy_version', next.privacyPolicyAcceptedVersion!);
    }
    await database.writeGoals(next.goals);

    if (rappelsModifies) {
      await ref.read(notificationServiceProvider).applySettings(next);
    }
  }

  Future<void> setThemeMode(ThemeMode mode) => _persist(state.copyWith(themeMode: mode));

  Future<void> setAnalysisMode(AnalysisModeSetting mode) =>
      _persist(state.copyWith(analysisMode: mode));

  Future<void> setKeepPhotos(bool value) => _persist(state.copyWith(keepPhotos: value));

  Future<void> setMealReminders(bool value) =>
      _persist(state.copyWith(mealRemindersEnabled: value));

  Future<void> setDailySummary(bool value) => _persist(state.copyWith(dailySummaryEnabled: value));

  Future<void> setReminderTime(int hour, int minute) =>
      _persist(state.copyWith(reminderHour: hour, reminderMinute: minute));

  Future<void> completeOnboarding() => _persist(state.copyWith(onboardingDone: true));

  Future<void> acceptPrivacyPolicy(String version) =>
      _persist(state.copyWith(privacyPolicyAcceptedVersion: version));

  Future<void> markDisclaimerSeen() => _persist(state.copyWith(useEstimatesDisclaimerSeen: true));

  Future<void> updateGoals(DailyGoals goals) => _persist(state.copyWith(goals: goals));

  /// Enregistre la cle d'analyse dans le trousseau du systeme.
  Future<void> saveProviderKey(String key) async {
    await ref.read(secureStoreProvider).writeProviderKey(key);
    state = state.copyWith(hasProviderKey: true);
  }

  /// Retire la cle du trousseau.
  Future<void> clearProviderKey() async {
    await ref.read(secureStoreProvider).deleteProviderKey();
    state = state.copyWith(hasProviderKey: false);
  }

  /// Efface toutes les donnees locales et les secrets.
  Future<void> eraseEverything() async {
    await ref.read(appDatabaseProvider).wipe();
    await ref.read(secureStoreProvider).wipe();
    state = const AppSettings();
    ref.invalidate(mealsProvider);
    ref.invalidate(favoritesProvider);
    ref.invalidate(templatesProvider);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// ---------------------------------------------------------------------------
// Moteur d'analyse
// ---------------------------------------------------------------------------

/// Construit le fournisseur d'analyse correspondant aux reglages courants.
///
/// Le mode demonstration n'est accessible qu'en compilation de developpement :
/// une version publiee ne peut pas afficher de fausses donnees.
final visionProviderProvider = FutureProvider<VisionProvider>((ref) async {
  final settings = ref.watch(settingsProvider);

  switch (settings.analysisMode) {
    case AnalysisModeSetting.demo:
      if (AppConfig.buildChannel == 'production') {
        throw StateError('Le mode demonstration est desactive en production.');
      }
      return MockVisionProvider();

    case AnalysisModeSetting.proxy:
      if (AppConfig.analysisEndpoint.isEmpty) {
        throw StateError(
          'Aucun service d\'analyse n\'est configure dans cette compilation. '
          'Utilisez une cle personnelle ou compilez avec ANALYSIS_ENDPOINT.',
        );
      }
      return ProxyVisionProvider(endpoint: AppConfig.analysisEndpoint);

    case AnalysisModeSetting.personal:
      final key = await ref.read(secureStoreProvider).readProviderKey();
      if (key == null || key.isEmpty) {
        throw StateError(
          'Aucune cle d\'analyse enregistree. Ajoutez-la dans Reglages, '
          'section Analyse des repas.',
        );
      }
      return DeepSeekVisionProvider(apiKey: key);
  }
});

/// Service d'analyse pret a l'emploi.
final mealAnalysisServiceProvider = FutureProvider<MealAnalysisService>((ref) async {
  final vision = await ref.watch(visionProviderProvider.future);
  return MealAnalysisService(vision: vision, ciqual: ref.watch(ciqualRepositoryProvider));
});

// ---------------------------------------------------------------------------
// Repas
// ---------------------------------------------------------------------------

/// Historique des repas, charge depuis la base locale.
class MealsNotifier extends AsyncNotifier<List<Meal>> {
  @override
  Future<List<Meal>> build() async {
    final database = ref.watch(appDatabaseProvider);
    return database.recentMeals(limit: 400);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => ref.read(appDatabaseProvider).recentMeals(limit: 400));
  }

  /// Enregistre un repas puis recharge la liste.
  Future<void> save(Meal meal) async {
    await ref.read(appDatabaseProvider).saveMeal(meal);
    await refresh();
  }

  Future<void> delete(String mealId) async {
    await ref.read(appDatabaseProvider).deleteMeal(mealId);
    await refresh();
  }

  /// Duplique un repas a la date du jour.
  Future<Meal> duplicate(Meal meal) async {
    final copy = Meal(
      eatenAt: DateTime.now(),
      name: meal.name,
      items: meal.items.map((item) => MealItem(food: item.food, quantityG: item.quantityG)).toList(),
      source: meal.source,
      notes: meal.notes,
      isEstimate: meal.isEstimate,
    );
    await ref.read(appDatabaseProvider).saveMeal(copy);
    await refresh();
    return copy;
  }
}

final mealsProvider = AsyncNotifierProvider<MealsNotifier, List<Meal>>(MealsNotifier.new);

/// Repas du jour.
final todayMealsProvider = Provider<AsyncValue<List<Meal>>>((ref) {
  return ref.watch(mealsProvider).whenData((meals) => NutritionCalculator.forDay(meals, DateTime.now()));
});

/// Resume du jour : totaux et nombre de repas.
final todaySummaryProvider = Provider<AsyncValue<NutritionSummary>>((ref) {
  return ref.watch(todayMealsProvider).whenData((meals) {
    return NutritionSummary(totals: NutritionCalculator.totalOf(meals), mealCount: meals.length);
  });
});

/// Totaux des glucides du jour, utilises par l'ecran d'accueil.
final todayCarbsProvider = Provider<AsyncValue<double>>((ref) {
  return ref.watch(todaySummaryProvider).whenData((summary) => summary.totals.carbs);
});

/// Serie des sept derniers jours, pour le graphique du tableau de bord.
final weeklySeriesProvider = Provider<AsyncValue<List<DailyBucket>>>((ref) {
  return ref.watch(mealsProvider).whenData(
        (meals) => NutritionCalculator.dailySeries(meals, DateTime.now(), days: 7),
      );
});

/// Serie des six dernieres semaines.
final monthlySeriesProvider = Provider<AsyncValue<List<DailyBucket>>>((ref) {
  return ref.watch(mealsProvider).whenData(
        (meals) => NutritionCalculator.weeklySeries(meals, DateTime.now(), weeks: 6),
      );
});

/// Progression vers les objectifs du jour.
final goalProgressProvider = Provider<AsyncValue<List<GoalProgress>>>((ref) {
  final goals = ref.watch(settingsProvider).goals;
  return ref.watch(todaySummaryProvider).whenData(
        (summary) => NutritionCalculator.progress(goals, summary),
      );
});

// ---------------------------------------------------------------------------
// Capture en attente d'analyse
// ---------------------------------------------------------------------------

/// Photos confirmees par l'utilisateur, en attente d'analyse.
///
/// Transiter par un provider plutot que par les arguments de navigation evite
/// de faire voyager des octets d'image dans l'URL et survit a une
/// reconstruction de l'ecran.
class PendingCapture {
  const PendingCapture({required this.image, this.secondImage, this.portionHint});

  final CapturedImage image;
  final CapturedImage? secondImage;

  /// « small », « medium » ou « large ».
  final String? portionHint;
}

class PendingCaptureNotifier extends Notifier<PendingCapture?> {
  @override
  PendingCapture? build() => null;

  void set(PendingCapture capture) => state = capture;

  void clear() => state = null;
}

final pendingCaptureProvider =
    NotifierProvider<PendingCaptureNotifier, PendingCapture?>(PendingCaptureNotifier.new);

// ---------------------------------------------------------------------------
// Repas en cours de modification
// ---------------------------------------------------------------------------

/// Repas en cours d'edition, entre l'analyse et l'enregistrement.
///
/// Toute modification passe par ce notifier : le total affiche est toujours
/// recalcule a partir des aliments, jamais ajuste a la main.
class DraftMealNotifier extends Notifier<Meal?> {
  @override
  Meal? build() => null;

  void start(Meal meal) => state = meal;

  void clear() => state = null;

  void rename(String name) {
    final meal = state;
    if (meal == null) return;
    state = meal.copyWith(name: name);
  }

  void setEatenAt(DateTime at) {
    final meal = state;
    if (meal == null) return;
    state = meal.copyWith(eatenAt: at);
  }

  void setNotes(String notes) {
    final meal = state;
    if (meal == null) return;
    state = meal.copyWith(notes: notes);
  }

  void setPhotoPath(String? path) {
    final meal = state;
    if (meal == null) return;
    state = meal.copyWith(photoPath: path);
  }

  void addItem(MealItem item) {
    final meal = state;
    if (meal == null) return;
    final items = [...meal.items, item];
    state = _renumber(meal.copyWith(items: items));
  }

  void removeItem(String itemId) {
    final meal = state;
    if (meal == null) return;
    final items = meal.items.where((item) => item.id != itemId).toList();
    state = _renumber(meal.copyWith(items: items));
  }

  void replaceItem(String itemId, MealItem replacement) {
    final meal = state;
    if (meal == null) return;
    final items = meal.items
        .map((item) => item.id == itemId ? replacement.copyWith(sortOrder: item.sortOrder) : item)
        .toList();
    state = _renumber(meal.copyWith(items: items));
  }

  /// Modifie la quantite d'un aliment. Le total se recalcule automatiquement.
  void setQuantity(String itemId, double grams) {
    final meal = state;
    if (meal == null) return;
    final items = meal.items
        .map((item) => item.id == itemId ? item.copyWith(quantityG: grams.clamp(0, 5000)) : item)
        .toList();
    state = meal.copyWith(items: items);
  }

  /// Applique un coefficient de portion a un aliment.
  void applyPortionFactor(String itemId, double factor) {
    final meal = state;
    if (meal == null) return;
    final items = meal.items.map((item) {
      if (item.id != itemId) return item;
      return item.copyWith(quantityG: (item.quantityG * factor).clamp(1, 5000));
    }).toList();
    state = meal.copyWith(items: items);
  }

  /// Applique un coefficient de portion a l'ensemble du repas.
  void applyFactorToAll(double factor) {
    final meal = state;
    if (meal == null) return;
    final items = meal.items
        .map((item) => item.copyWith(quantityG: (item.quantityG * factor).clamp(1, 5000)))
        .toList();
    state = meal.copyWith(items: items);
  }

  Meal _renumber(Meal meal) {
    final items = <MealItem>[];
    for (var index = 0; index < meal.items.length; index++) {
      items.add(meal.items[index].copyWith(sortOrder: index));
    }
    return meal.copyWith(items: items);
  }
}

final draftMealProvider = NotifierProvider<DraftMealNotifier, Meal?>(DraftMealNotifier.new);

/// Totaux du repas en cours, recalcules a chaque modification.
final draftTotalsProvider = Provider<NutritionValues?>((ref) {
  return ref.watch(draftMealProvider)?.totals;
});

// ---------------------------------------------------------------------------
// Favoris et repas enregistres
// ---------------------------------------------------------------------------

class FavoritesNotifier extends AsyncNotifier<List<Favorite>> {
  @override
  Future<List<Favorite>> build() => ref.watch(appDatabaseProvider).favorites();

  Future<void> toggle({
    required String id,
    required String kind,
    required String label,
    required Map<String, dynamic> payload,
  }) async {
    final database = ref.read(appDatabaseProvider);
    if (await database.isFavorite(id)) {
      await database.deleteFavorite(id);
    } else {
      await database.addFavorite(id, kind, label, payload);
    }
    state = await AsyncValue.guard(() => database.favorites());
  }

  Future<void> remove(String id) async {
    final database = ref.read(appDatabaseProvider);
    await database.deleteFavorite(id);
    state = await AsyncValue.guard(() => database.favorites());
  }
}

final favoritesProvider = AsyncNotifierProvider<FavoritesNotifier, List<Favorite>>(FavoritesNotifier.new);

class TemplatesNotifier extends AsyncNotifier<List<MealTemplate>> {
  @override
  Future<List<MealTemplate>> build() => ref.watch(appDatabaseProvider).templates();

  Future<void> save(String id, String name, List<MealItem> items) async {
    final database = ref.read(appDatabaseProvider);
    await database.saveTemplate(id, name, items);
    state = await AsyncValue.guard(() => database.templates());
  }

  Future<void> remove(String id) async {
    final database = ref.read(appDatabaseProvider);
    await database.deleteTemplate(id);
    state = await AsyncValue.guard(() => database.templates());
  }

  /// Cree un repas a partir d'un modele, a l'instant courant.
  Meal instantiate(MealTemplate template, {String? name}) {
    return Meal(
      eatenAt: DateTime.now(),
      name: name ?? template.name,
      items: template.items
          .map((item) => MealItem(food: item.food, quantityG: item.quantityG))
          .toList(),
      source: MealSource.template,
      isEstimate: false,
    );
  }
}

final templatesProvider = AsyncNotifierProvider<TemplatesNotifier, List<MealTemplate>>(TemplatesNotifier.new);
