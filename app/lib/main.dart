import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/formatters.dart';
import 'data/ciqual_repository.dart';
import 'data/local/app_database.dart';
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
  final settings = await lireLesReglages(database, secureStore);

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
