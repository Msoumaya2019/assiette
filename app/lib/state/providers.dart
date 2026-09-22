import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/config.dart';
import '../core/failures.dart';
import '../data/ciqual_repository.dart';
import '../data/local/app_database.dart';
import '../data/openfoodfacts_repository.dart';
import '../data/vision/deepseek_provider.dart';
import '../data/vision/mock_provider.dart';
import '../data/vision/proxy_provider.dart';
import '../data/vision/vision_provider.dart';
import '../models/app_settings.dart';
import '../models/food.dart';
import '../models/goals.dart';
import '../models/meal.dart';
import '../models/nutrition_values.dart';
import '../models/portion.dart';
import '../models/session.dart';
import '../models/suivi_poids.dart';
import '../services/backup_service.dart';
import '../services/client_authentification.dart';
import '../services/image_service.dart';
import '../services/meal_analysis_service.dart';
import '../services/notification_service.dart';
import '../services/nutrition_calculator.dart';
import '../services/secure_store.dart';
import '../services/synchronisation_service.dart';
import '../services/transport_supabase.dart';

// ---------------------------------------------------------------------------
// Dependances chargees au demarrage
//
// La base de donnees, la table Ciqual et les reglages sont ouverts avant
// `runApp` puis injectes ici. Les providers restent ainsi synchrones, ce qui
// evite les etats de chargement partout dans l'interface.
// ---------------------------------------------------------------------------

final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError(
    'appDatabaseProvider doit etre surcharge au demarrage',
  ),
);

final ciqualRepositoryProvider = Provider<CiqualRepository>(
  (ref) => throw UnimplementedError(
    'ciqualRepositoryProvider doit etre surcharge au demarrage',
  ),
);

final secureStoreProvider = Provider<SecureStore>(
  (ref) => throw UnimplementedError(
    'secureStoreProvider doit etre surcharge au demarrage',
  ),
);

/// Reglages charges avant le premier affichage.
final initialSettingsProvider = Provider<AppSettings>(
  (ref) => throw UnimplementedError(
    'initialSettingsProvider doit etre surcharge au demarrage',
  ),
);

final openFoodFactsProvider = Provider<OpenFoodFactsRepository>(
  (ref) => OpenFoodFactsRepository(),
);

final imageServiceProvider = Provider<ImageService>((ref) => ImageService());

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => throw UnimplementedError(
    'notificationServiceProvider doit etre surcharge au demarrage',
  ),
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    database: ref.watch(appDatabaseProvider),
    appVersion: AppConfig.version,
  ),
);

/// Relit les reglages persistes.
///
/// Une valeur illisible ou absente retombe sur la valeur par defaut : un
/// reglage corrompu ne doit jamais empecher l'application de demarrer.
///
/// Vit ici, et non dans `main.dart` : la restauration d'une sauvegarde reecrit
/// la table `settings` et doit relire exactement la meme chose. Deux copies de
/// cette lecture divergeraient, et la divergence se verrait au redemarrage —
/// c'est-a-dire trop tard pour la comprendre.
Future<AppSettings> lireLesReglages(
  AppDatabase database,
  SecureStore secureStore,
) async {
  try {
    final themeMode = await database.readSetting('theme_mode');
    final analysisMode = await database.readSetting('analysis_mode');
    final onboardingDone = await database.readSetting('onboarding_done');
    final keepPhotos = await database.readSetting('keep_photos');
    final mealReminders = await database.readSetting('meal_reminders');
    final dailySummary = await database.readSetting('daily_summary');
    final reminderHour = await database.readSetting('reminder_hour');
    final reminderMinute = await database.readSetting('reminder_minute');
    final disclaimerSeen = await database.readSetting('disclaimer_seen');
    final privacyVersion = await database.readSetting('privacy_version');
    final goals = await database.readGoals();
    final hasKey = await secureStore.hasProviderKey();

    return AppSettings(
      themeMode: _themeMode(themeMode),
      analysisMode: _analysisMode(analysisMode),
      hasProviderKey: hasKey,
      onboardingDone: onboardingDone == '1',
      keepPhotos: keepPhotos != '0',
      mealRemindersEnabled: mealReminders == '1',
      dailySummaryEnabled: dailySummary == '1',
      reminderHour: int.tryParse(reminderHour ?? '') ?? 20,
      reminderMinute: int.tryParse(reminderMinute ?? '') ?? 0,
      privacyPolicyAcceptedVersion: privacyVersion,
      goals: goals,
      useEstimatesDisclaimerSeen: disclaimerSeen == '1',
    );
  } catch (_) {
    return const AppSettings();
  }
}

ThemeMode _themeMode(String? value) => ThemeMode.values.firstWhere(
  (mode) => mode.name == value,
  orElse: () => ThemeMode.system,
);

AnalysisModeSetting _analysisMode(String? value) {
  if (value == null) {
    // Aucun reglage enregistre : on suit ce que la compilation permet.
    //
    // Source unique de verite : AppConfig. Un build qui embarque un point
    // d'entree serveur doit demarrer en mode proxy, sinon on demanderait a
    // l'utilisateur une cle dont ce build n'a precisement pas besoin.
    return switch (AppConfig.defaultAnalysisMode) {
      AnalysisMode.proxy => AnalysisModeSetting.proxy,
      AnalysisMode.personal => AnalysisModeSetting.personal,
    };
  }
  return AnalysisModeSetting.fromId(value);
}

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
    final rappelsModifies =
        next.mealRemindersEnabled != state.mealRemindersEnabled ||
        next.dailySummaryEnabled != state.dailySummaryEnabled ||
        next.reminderHour != state.reminderHour ||
        next.reminderMinute != state.reminderMinute;

    state = next;
    final database = ref.read(appDatabaseProvider);
    await database.writeSetting('theme_mode', next.themeMode.name);
    await database.writeSetting('analysis_mode', next.analysisMode.name);
    await database.writeSetting(
      'onboarding_done',
      next.onboardingDone ? '1' : '0',
    );
    await database.writeSetting('keep_photos', next.keepPhotos ? '1' : '0');
    await database.writeSetting(
      'meal_reminders',
      next.mealRemindersEnabled ? '1' : '0',
    );
    await database.writeSetting(
      'daily_summary',
      next.dailySummaryEnabled ? '1' : '0',
    );
    await database.writeSetting('reminder_hour', next.reminderHour.toString());
    await database.writeSetting(
      'reminder_minute',
      next.reminderMinute.toString(),
    );
    await database.writeSetting(
      'disclaimer_seen',
      next.useEstimatesDisclaimerSeen ? '1' : '0',
    );
    if (next.privacyPolicyAcceptedVersion != null) {
      await database.writeSetting(
        'privacy_version',
        next.privacyPolicyAcceptedVersion!,
      );
    }
    await database.writeGoals(next.goals);

    if (rappelsModifies) {
      await ref.read(notificationServiceProvider).applySettings(next);
    }
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      _persist(state.copyWith(themeMode: mode));

  Future<void> setAnalysisMode(AnalysisModeSetting mode) =>
      _persist(state.copyWith(analysisMode: mode));

  Future<void> setKeepPhotos(bool value) =>
      _persist(state.copyWith(keepPhotos: value));

  Future<void> setMealReminders(bool value) =>
      _persist(state.copyWith(mealRemindersEnabled: value));

  Future<void> setDailySummary(bool value) =>
      _persist(state.copyWith(dailySummaryEnabled: value));

  Future<void> setReminderTime(int hour, int minute) =>
      _persist(state.copyWith(reminderHour: hour, reminderMinute: minute));

  Future<void> completeOnboarding() =>
      _persist(state.copyWith(onboardingDone: true));

  Future<void> acceptPrivacyPolicy(String version) =>
      _persist(state.copyWith(privacyPolicyAcceptedVersion: version));

  Future<void> markDisclaimerSeen() =>
      _persist(state.copyWith(useEstimatesDisclaimerSeen: true));

  Future<void> updateGoals(DailyGoals goals) =>
      _persist(state.copyWith(goals: goals));

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
    // Les photos ne sont pas dans la base : sans cet appel, elles resteraient
    // sur le telephone apres une demande d'effacement.
    await ref.read(imageServiceProvider).deleteAll();
    state = const AppSettings();
    // La session de compte vient de partir avec le reste : `wipe` efface **tout**
    // le trousseau. L'etat doit suivre, sans quoi l'ecran continuerait
    // d'afficher un compte connecte dont il ne reste plus rien sur l'appareil.
    ref.invalidate(compteProvider);
    ref.invalidate(mealsProvider);
    ref.invalidate(favoritesProvider);
    ref.invalidate(templatesProvider);
    ref.invalidate(suiviProvider);
    ref.invalidate(portionsProvider);
  }

  /// Relit les reglages et recharge les listes apres une restauration.
  ///
  /// Sans cette relecture, l'ecran continuerait d'afficher les reglages d'avant
  /// la restauration jusqu'au prochain demarrage : les donnees seraient bien
  /// revenues, mais l'application les ignorerait — theme, objectifs, rappels.
  Future<void> rechargerApresRestauration() async {
    state = await lireLesReglages(
      ref.read(appDatabaseProvider),
      ref.read(secureStoreProvider),
    );
    ref.invalidate(mealsProvider);
    ref.invalidate(favoritesProvider);
    ref.invalidate(templatesProvider);
    ref.invalidate(suiviProvider);
    ref.invalidate(portionsProvider);
    // Les rappels programmes decoulent des reglages : ils doivent suivre.
    await ref.read(notificationServiceProvider).applySettings(state);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

// ---------------------------------------------------------------------------
// Compte
// ---------------------------------------------------------------------------

/// Vrai si cette compilation porte un projet Supabase.
///
/// La decision passe par un provider au lieu d'etre lue directement depuis
/// `AppConfig` par l'ecran, et c'est ce qui rend la section Compte eprouvable :
/// `AppConfig` est une constante de compilation, donc sans cette couture le
/// formulaire et l'etat connecte seraient **inatteignables en test**. Une
/// interface qu'aucun test ne traverse est une interface qu'on ne sait pas
/// cassee — et les tests d'interface de ce projet ont deja trouve deux defauts
/// qu'aucun test de modele ne pouvait voir.
final projetConfigureProvider = Provider<bool>(
  (ref) => AppConfig.supabaseConfigured,
);

/// Le client du serveur d'authentification.
///
/// L'adresse du projet et la cle publique viennent de la **compilation**
/// (`--dart-define`), pas de la base locale : ce ne sont pas des reglages que
/// l'utilisateur peut changer, et les y ranger laisserait croire le contraire.
///
/// **Leve** quand la compilation ne porte pas de projet. Un exemplaire sans
/// projet ne peut ouvrir aucune session : le dire ici vaut mieux que de laisser
/// partir une requete vers une adresse vide, qui echouerait plus loin avec un
/// message qui ne dirait rien de la cause. C'est le meme choix que le moteur
/// d'analyse, qui refuse de se construire sans point d'entree.
final clientAuthentificationProvider = Provider<ClientAuthentification>((ref) {
  if (!ref.watch(projetConfigureProvider)) {
    throw StateError(
      'Aucun projet n\'est configure dans cette compilation : recompiler avec '
      'SUPABASE_URL et SUPABASE_ANON_KEY.',
    );
  }
  return ClientAuthentification(
    url: AppConfig.supabaseUrl,
    clePublique: AppConfig.supabaseAnonKey,
  );
});

/// La session du compte, lue dans le trousseau.
///
/// `null` veut dire « aucun compte connecte », et rien d'autre. Un echec de
/// connexion ne se range pas ici : c'est l'ecran qui le montre, le temps d'une
/// tentative. Le ranger dans l'etat ferait dire « deconnecte » a une
/// application qui n'a jamais ete connectee — ce qui est vrai, mais effacerait
/// la raison du refus, qui est la seule chose utile a ce moment-la.
class CompteNotifier extends AsyncNotifier<Session?> {
  @override
  Future<Session?> build() => ref.watch(secureStoreProvider).lireSession();

  /// Ouvre une session, puis la range dans le trousseau.
  ///
  /// **Rien n'est ecrit avant que le serveur ait repondu.** Une session de
  /// secours serait pire qu'aucune session : elle ferait croire a une connexion
  /// qui n'existe pas, et l'erreur ne se verrait qu'a la premiere requete de
  /// donnees, loin d'ici. L'echec remonte tel quel — l'appelant sait quel
  /// message montrer, et `AppFailure` porte deja le bon.
  Future<void> connecter({
    required String email,
    required String motDePasse,
  }) async {
    await remplacer(
      await ref
          .read(clientAuthentificationProvider)
          .connecter(email: email, motDePasse: motDePasse),
    );
  }

  /// Range une session deja obtenue, et publie l'etat.
  ///
  /// **Le trousseau d'abord, l'etat ensuite.** Cet ordre est le seul qui ne
  /// mente pas : publier une session que le trousseau ne porte pas encore la
  /// ferait disparaitre au redemarrage suivant, sans que rien n'explique
  /// l'ecart — l'utilisateur se retrouverait deconnecte sans avoir rien fait.
  ///
  /// Ecrit **une seule fois**, et lu par deux chemins : la connexion, et le
  /// renouvellement d'un jeton perime. Deux copies de cet ordre finiraient par
  /// diverger, et la divergence ne se verrait qu'au redemarrage — c'est-a-dire
  /// trop tard pour la comprendre.
  Future<void> remplacer(Session session) async {
    await ref.read(secureStoreProvider).ecrireSession(session);
    state = AsyncData(session);
  }

  /// Ferme la session : **le trousseau d'abord, l'etat ensuite**.
  ///
  /// Cet ordre est le seul qui ne mente pas. Effacer l'etat d'abord laisserait,
  /// si l'effacement echouait, une application qui se dit deconnectee alors que
  /// le trousseau porte encore une session — et le redemarrage suivant lui
  /// donnerait tort, sans que rien n'explique l'ecart. Ici, un effacement rate
  /// laisse l'ecran dire la verite : le compte est toujours connecte.
  Future<void> deconnecter() async {
    await ref.read(secureStoreProvider).effacerSession();
    state = const AsyncData(null);
  }
}

final compteProvider = AsyncNotifierProvider<CompteNotifier, Session?>(
  CompteNotifier.new,
);

// ---------------------------------------------------------------------------
// Synchronisation
// ---------------------------------------------------------------------------
//
// C'est ici que les deux pieces eprouvees mais **inatteignables** deviennent
// vivantes : `ServiceSynchronisation` et `TransportSupabase` existaient, etaient
// entierement falsifies, et n'etaient instancies que par leurs propres tests.
// Une regle qu'aucune mesure ne separe est un passif ; une regle qu'aucun
// appelant n'atteint en est un aussi, et celui-la ne se voyait qu'en cherchant
// qui appelait — c'est-a-dire personne.

/// Le transport qui parle au projet, construit sur la session courante.
///
/// **Leve** quand la compilation ne porte pas de projet, ou quand aucun compte
/// n'est connecte : les deux sont des etats ou une synchronisation n'a pas de
/// sens, et le dire ici vaut mieux que de laisser partir des requetes sans
/// jeton, qui reviendraient refusees sans que la cause soit lisible.
///
/// La session est **regardee**, et pas seulement lue : quand un renouvellement
/// publie une session neuve, ce fournisseur se reconstruit avec le nouveau
/// jeton, et le service qui s'en sert aussi. C'est ce qui rend l'ordre du
/// renouvellement mesurable — voir `SynchronisationNotifier._sessionUtilisable`.
final transportSynchronisationProvider = Provider<TransportSynchronisation>((
  ref,
) {
  if (!ref.watch(projetConfigureProvider)) {
    throw StateError(
      'Aucun projet n\'est configure dans cette compilation : la '
      'synchronisation ne peut pas s\'ouvrir.',
    );
  }

  final session = ref.watch(compteProvider).value;
  if (session == null) {
    throw StateError(
      'Aucun compte connecte : la synchronisation demande une session.',
    );
  }

  return TransportSupabase(
    url: AppConfig.supabaseUrl,
    clePublique: AppConfig.supabaseAnonKey,
    utilisateur: session.utilisateur,
    jeton: session.jetonAcces,
  );
});

/// Le service qui fait converger la base locale et le projet.
///
/// Rien n'est decide ici : le service porte la regle d'arbitrage, le transport
/// porte les conversions. Ce fournisseur ne fait que les assembler, et c'est
/// exactement ce qui manquait.
///
/// **L'horloge vient de la base, et pas d'une neuve.** C'est elle qui estampille
/// les modifications : le service doit corriger celle-la meme. Une instance
/// distincte mesurerait l'ecart d'un cote et continuerait d'estampiller faux de
/// l'autre, sans que rien ne le signale.
final serviceSynchronisationProvider = Provider<ServiceSynchronisation>((ref) {
  final base = ref.watch(appDatabaseProvider);
  return ServiceSynchronisation(
    db: base.db,
    transport: ref.watch(transportSynchronisationProvider),
    horloge: base.horloge,
  );
});

/// Le dernier passage, ou `null` tant qu'aucun n'a tourne.
///
/// `null` et « rien n'a bouge » ne veulent pas dire la meme chose, et l'ecran
/// doit pouvoir les distinguer : afficher « tout est a jour » avant toute
/// tentative ferait passer une absence de mesure pour un resultat.
class SynchronisationNotifier extends AsyncNotifier<RapportSynchronisation?> {
  @override
  Future<RapportSynchronisation?> build() async => null;

  /// Un passage complet, table par table.
  ///
  /// **Ne leve pas** : l'echec est publie dans l'etat, ou l'ecran le lit. Le
  /// service, lui, ne leve deja pas pour une table en echec — il la rapporte, et
  /// laisse les autres converger. Ce qui peut echouer avant le passage, en
  /// revanche, est une session absente ou un renouvellement refuse, et cela
  /// merite d'etre dit a l'utilisateur plutot que compte comme zero ligne.
  Future<void> synchroniser() async {
    state = const AsyncLoading();
    try {
      await _sessionUtilisable();
      state = AsyncData(
        await ref.read(serviceSynchronisationProvider).synchroniser(),
      );
    } on Object catch (erreur, pile) {
      state = AsyncError(erreur, pile);
    }
  }

  /// La session a utiliser, renouvelee si elle est perimee.
  ///
  /// **Le renouvellement precede la lecture du service**, et c'est toute la
  /// raison d'etre de cette fonction : le transport est construit a partir de la
  /// session rangee, donc un service lu avant le renouvellement porterait le
  /// jeton perime — et **chaque table** serait refusee, avec un message de
  /// session qui n'expliquerait pas pourquoi. Une relecture ne verrait pas cette
  /// faute : les deux ecritures sont justes, c'est leur ordre qui compte.
  ///
  /// Sans compte, le refus est celui d'une session : c'est le meme geste pour
  /// l'utilisateur, et `SessionRefuseeFailure` porte deja le bon conseil.
  ///
  /// Un renouvellement **refuse** n'efface pas la session rangee. La
  /// deconnexion est un geste de l'utilisateur, pas un effet de bord d'un
  /// passage rate : l'effacer ici lui retirerait un compte qu'il n'a pas demande
  /// a quitter, et le refus, lui, est deja affiche.
  Future<Session> _sessionUtilisable() async {
    final session = await ref.read(compteProvider.future);
    if (session == null) throw const SessionRefuseeFailure();

    if (!session.estExpireeA(DateTime.now().millisecondsSinceEpoch)) {
      return session;
    }

    final neuve = await ref
        .read(clientAuthentificationProvider)
        .rafraichir(session.jetonRafraichissement);
    // Rangee avant d'etre publiee : meme ordre que la connexion, meme raison.
    await ref.read(compteProvider.notifier).remplacer(neuve);
    return neuve;
  }
}

final synchronisationProvider =
    AsyncNotifierProvider<SynchronisationNotifier, RapportSynchronisation?>(
      SynchronisationNotifier.new,
    );

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
final mealAnalysisServiceProvider = FutureProvider<MealAnalysisService>((
  ref,
) async {
  final vision = await ref.watch(visionProviderProvider.future);
  return MealAnalysisService(
    vision: vision,
    ciqual: ref.watch(ciqualRepositoryProvider),
  );
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
    state = await AsyncValue.guard(
      () => ref.read(appDatabaseProvider).recentMeals(limit: 400),
    );
  }

  /// Enregistre un repas puis recharge la liste.
  ///
  /// C'est **ici**, et non au moment ou la portion est definie, que les portions
  /// sont retenues pour les prochaines fois. Une portion definie sur un repas
  /// que l'utilisateur finit par abandonner ne doit pas s'installer dans la
  /// base : retenir ce qui a ete valide, c'est retenir ce que l'utilisateur a
  /// effectivement garde.
  Future<void> save(Meal meal) async {
    final database = ref.read(appDatabaseProvider);
    await database.saveMeal(meal);

    for (final item in meal.items) {
      final portion = item.portion;
      if (portion == null) continue;
      await database.writePortion(AppDatabase.cleDePortion(item.food), portion);
    }

    // Les listes de resultats lisent les portions depuis `portionsProvider` :
    // sans cette invalidation, une portion tout juste definie n'apparaitrait
    // qu'au prochain demarrage.
    ref.invalidate(portionsProvider);

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
      items: meal.items
          .map((item) => MealItem(food: item.food, quantityG: item.quantityG))
          .toList(),
      source: meal.source,
      notes: meal.notes,
      isEstimate: meal.isEstimate,
    );
    await ref.read(appDatabaseProvider).saveMeal(copy);
    await refresh();
    return copy;
  }
}

final mealsProvider = AsyncNotifierProvider<MealsNotifier, List<Meal>>(
  MealsNotifier.new,
);

/// Repas du jour.
final todayMealsProvider = Provider<AsyncValue<List<Meal>>>((ref) {
  return ref
      .watch(mealsProvider)
      .whenData((meals) => NutritionCalculator.forDay(meals, DateTime.now()));
});

/// Resume du jour : totaux et nombre de repas.
final todaySummaryProvider = Provider<AsyncValue<NutritionSummary>>((ref) {
  return ref.watch(todayMealsProvider).whenData((meals) {
    return NutritionSummary(
      totals: NutritionCalculator.totalOf(meals),
      mealCount: meals.length,
    );
  });
});

/// Totaux des glucides du jour, utilises par l'ecran d'accueil.
final todayCarbsProvider = Provider<AsyncValue<double>>((ref) {
  return ref
      .watch(todaySummaryProvider)
      .whenData((summary) => summary.totals.carbs);
});

/// Serie des sept derniers jours, pour le graphique du tableau de bord.
final weeklySeriesProvider = Provider<AsyncValue<List<DailyBucket>>>((ref) {
  return ref
      .watch(mealsProvider)
      .whenData(
        (meals) =>
            NutritionCalculator.dailySeries(meals, DateTime.now(), days: 7),
      );
});

/// Serie des six dernieres semaines.
final monthlySeriesProvider = Provider<AsyncValue<List<DailyBucket>>>((ref) {
  return ref
      .watch(mealsProvider)
      .whenData(
        (meals) =>
            NutritionCalculator.weeklySeries(meals, DateTime.now(), weeks: 6),
      );
});

/// Progression vers les objectifs du jour.
final goalProgressProvider = Provider<AsyncValue<List<GoalProgress>>>((ref) {
  final goals = ref.watch(settingsProvider).goals;
  return ref
      .watch(todaySummaryProvider)
      .whenData((summary) => NutritionCalculator.progress(goals, summary));
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
  const PendingCapture({
    required this.image,
    this.secondImage,
    this.portionHint,
  });

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
    NotifierProvider<PendingCaptureNotifier, PendingCapture?>(
      PendingCaptureNotifier.new,
    );

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
        .map(
          (item) => item.id == itemId
              ? replacement.copyWith(sortOrder: item.sortOrder)
              : item,
        )
        .toList();
    state = _renumber(meal.copyWith(items: items));
  }

  /// Modifie la quantite d'un aliment. Le total se recalcule automatiquement.
  void setQuantity(String itemId, double grams) {
    final meal = state;
    if (meal == null) return;
    final items = meal.items
        .map(
          (item) => item.id == itemId
              ? item.copyWith(quantityG: grams.clamp(0, 5000))
              : item,
        )
        .toList();
    state = meal.copyWith(items: items);
  }

  /// Definit ou retire la portion nommee d'un aliment.
  ///
  /// La quantite en grammes n'est **pas** touchee. Declarer « 1 gateau = 65 g »
  /// alors que 130 g sont deja saisis doit afficher « 2 gateaux », pas reecrire
  /// la quantite : changer un total que l'utilisateur n'a pas demande de
  /// changer serait une perte silencieuse.
  void setPortion(String itemId, Portion? portion) {
    final meal = state;
    if (meal == null) return;
    final items = meal.items
        .map(
          (item) => item.id == itemId
              ? item.copyWith(portion: portion, effacerPortion: portion == null)
              : item,
        )
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
        .map(
          (item) => item.copyWith(
            quantityG: (item.quantityG * factor).clamp(1, 5000),
          ),
        )
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

final draftMealProvider = NotifierProvider<DraftMealNotifier, Meal?>(
  DraftMealNotifier.new,
);

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

final favoritesProvider =
    AsyncNotifierProvider<FavoritesNotifier, List<Favorite>>(
      FavoritesNotifier.new,
    );

class TemplatesNotifier extends AsyncNotifier<List<MealTemplate>> {
  @override
  Future<List<MealTemplate>> build() =>
      ref.watch(appDatabaseProvider).templates();

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

final templatesProvider =
    AsyncNotifierProvider<TemplatesNotifier, List<MealTemplate>>(
      TemplatesNotifier.new,
    );

// ---------------------------------------------------------------------------
// Suivi du poids
// ---------------------------------------------------------------------------

const _uuidSuivi = Uuid();

/// Pesees, mesures et objectif de poids, lus ensemble.
///
/// Une seule source pour l'ecran : la courbe a besoin des pesees **et** de
/// l'objectif pour se cadrer. Deux providers separes obligeraient l'ecran a
/// gerer deux etats de chargement pour un affichage unique, et l'objectif
/// pourrait arriver apres la courbe — qui se recadrerait alors sous les yeux de
/// l'utilisateur.
class SuiviNotifier extends AsyncNotifier<SuiviPoids> {
  @override
  Future<SuiviPoids> build() async {
    final database = ref.watch(appDatabaseProvider);
    return _lire(database);
  }

  Future<SuiviPoids> _lire(AppDatabase database) async {
    return SuiviPoids(
      pesees: await database.pesees(),
      mesures: await database.mesures(),
      objectif: await database.readObjectifPoids(),
    );
  }

  Future<void> _rafraichir() async {
    final database = ref.read(appDatabaseProvider);
    state = await AsyncValue.guard(() => _lire(database));
  }

  /// Enregistre une pesee. La date par defaut est maintenant.
  Future<void> ajouterPesee({
    required double poidsKg,
    DateTime? le,
    String? note,
  }) async {
    if (poidsKg <= 0) return;
    await ref
        .read(appDatabaseProvider)
        .savePesee(
          Pesee(
            id: _uuidSuivi.v4(),
            le: le ?? DateTime.now(),
            poidsKg: poidsKg,
            note: (note ?? '').trim().isEmpty ? null : note!.trim(),
          ),
        );
    await _rafraichir();
  }

  Future<void> supprimerPesee(String id) async {
    await ref.read(appDatabaseProvider).deletePesee(id);
    await _rafraichir();
  }

  Future<void> ajouterMesure({
    required TypeMesure type,
    required double valeurCm,
    DateTime? le,
  }) async {
    if (valeurCm <= 0) return;
    await ref
        .read(appDatabaseProvider)
        .saveMesure(
          Mesure(
            id: _uuidSuivi.v4(),
            le: le ?? DateTime.now(),
            type: type,
            valeurCm: valeurCm,
          ),
        );
    await _rafraichir();
  }

  Future<void> supprimerMesure(String id) async {
    await ref.read(appDatabaseProvider).deleteMesure(id);
    await _rafraichir();
  }

  /// Definit ou efface l'objectif de poids.
  ///
  /// L'application ne propose aucune valeur : `null` efface, il ne remplace
  /// jamais par une cible inventee.
  Future<void> definirObjectif(double? cibleKg) async {
    final objectif = cibleKg == null || cibleKg <= 0
        ? ObjectifPoids.aucun
        : ObjectifPoids(cibleKg: cibleKg);
    await ref.read(appDatabaseProvider).writeObjectifPoids(objectif);
    await _rafraichir();
  }
}

final suiviProvider = AsyncNotifierProvider<SuiviNotifier, SuiviPoids>(
  SuiviNotifier.new,
);

/// Courbe de poids, prete a dessiner.
final seriePoidsProvider = Provider<AsyncValue<SeriePoids>>((ref) {
  return ref.watch(suiviProvider).whenData((suivi) => suivi.serie());
});

// ---------------------------------------------------------------------------
// Portions retenues
// ---------------------------------------------------------------------------

/// Portions retenues, par cle d'aliment.
///
/// Chargees **d'un bloc** plutot qu'a la demande : une liste de resultats en
/// affiche plusieurs dizaines a la fois, et une lecture disque par ligne ferait
/// autant d'acces pendant le defilement. La table reste petite — quelques
/// dizaines de lignes pour un usage soutenu — donc la garder en memoire coute
/// moins que de la relire sans arret.
///
/// Lecture des portions **vivantes** : la table porte aussi des pierres
/// tombales, que la sauvegarde lit de son cote, mais qui ne doivent pas
/// remonter ici.
class PortionsNotifier extends AsyncNotifier<Map<String, Portion>> {
  @override
  Future<Map<String, Portion>> build() =>
      ref.watch(appDatabaseProvider).portionsVivantes();

  /// Portion a proposer pour un aliment.
  ///
  /// Celle que l'utilisateur a retenue prime ; a defaut, celle annoncee par la
  /// source. Avant le premier chargement, seule la seconde est disponible —
  /// c'est acceptable, et mieux que de n'afficher aucune portion.
  Portion? pour(Food food) {
    final retenue = state.valueOrNull?[AppDatabase.cleDePortion(food)];
    if (retenue != null) return retenue;
    return Portion.depuisEtiquette(food.servingLabel, food.servingSizeG);
  }

  Future<void> recharger() async {
    final database = ref.read(appDatabaseProvider);
    state = await AsyncValue.guard(() => database.portionsVivantes());
  }
}

final portionsProvider =
    AsyncNotifierProvider<PortionsNotifier, Map<String, Portion>>(
      PortionsNotifier.new,
    );
