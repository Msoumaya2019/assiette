import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/formatters.dart';
import 'data/ciqual_repository.dart';
import 'data/local/app_database.dart';
import 'models/app_settings.dart';
import 'services/notification_service.dart';
import 'services/secure_store.dart';
import 'state/providers.dart';

/// Point d'entree.
///
/// La base de donnees, la table Ciqual et les reglages sont prepares avant le
/// premier affichage. Le cout est de quelques dizaines de millisecondes, en
/// echange de quoi aucun ecran n'a besoin d'un etat de chargement initial.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Le formatage des dates doit connaitre le francais, sinon les mois
  // s'affichent en anglais sans qu'aucune erreur ne soit levee.
  await initializeFormatting();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final database = AppDatabase();
  await database.open();

  final ciqual = CiqualRepository();
  await ciqual.load();

  final secureStore = SecureStore();
  final settings = await _loadSettings(database, secureStore);

  // La fenetre de rappels est reconstruite a chaque ouverture : c'est ce qui
  // la maintient juste malgre les changements d'heure et les redemarrages.
  final notifications = NotificationService();
  await notifications.initialize();
  await notifications.applySettings(settings);

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        ciqualRepositoryProvider.overrideWithValue(ciqual),
        secureStoreProvider.overrideWithValue(secureStore),
        notificationServiceProvider.overrideWithValue(notifications),
        initialSettingsProvider.overrideWithValue(settings),
      ],
      child: const AssietteApp(),
    ),
  );
}

/// Relit les reglages persistes.
///
/// Une valeur illisible ou absente retombe sur la valeur par defaut : un
/// reglage corrompu ne doit jamais empecher l'application de demarrer.
Future<AppSettings> _loadSettings(
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
