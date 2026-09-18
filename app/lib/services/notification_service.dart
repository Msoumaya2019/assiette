import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/app_settings.dart';

/// Rappels de repas et resume quotidien.
///
/// Deux choix meritent d'etre expliques, car ils s'ecartent de ce que font
/// souvent les applications :
///
/// **1. Une fenetre glissante de rappels ponctuels, pas une repetition.**
/// La repetition quotidienne du greffon s'appuie sur un fuseau horaire nomme
/// qu'il faut connaitre (`Europe/Paris`). Obtenir ce nom demanderait une
/// dependance supplementaire, et le resultat derive d'une heure au changement
/// d'heure. On programme donc quatorze rappels ponctuels, chacun calcule a
/// partir de l'heure locale du systeme — qui, elle, gere correctement les
/// changements d'heure. La fenetre est reconstruite a chaque ouverture de
/// l'application et a chaque modification des reglages.
///
/// **2. Planification « inexacte ».**
/// Une alarme exacte exigerait la permission `SCHEDULE_EXACT_ALARM`, que Google
/// Play reserve aux reveils et aux agendas. Un rappel de repas peut arriver avec
/// quelques minutes de retard sans inconsequence : on demande donc le mode
/// inexact, et aucune permission supplementaire.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Identifiants de base. Chaque jour de la fenetre decale l'identifiant,
  /// ce qui permet de reprogrammer sans collision.
  static const int _mealReminderBaseId = 1000;
  static const int _dailySummaryBaseId = 2000;

  /// Nombre de jours programmes d'avance.
  static const int daysAhead = 14;

  /// Heure du resume quotidien, en fin de journee.
  ///
  /// Le rappel de repas suit l'heure choisie par l'utilisateur ; le resume a une
  /// heure fixe, faute d'un second reglage d'heure dans l'interface.
  static const int summaryHour = 20;
  static const int summaryMinute = 30;

  static const String _mealChannelId = 'rappels_repas';
  static const String _summaryChannelId = 'resume_quotidien';

  bool _initialized = false;
  bool _available = true;

  /// Vrai si les notifications sont utilisables sur cet appareil.
  bool get isAvailable => _available;

  /// Prepare le greffon. Sans effet si deja fait.
  ///
  /// Ne demande aucune autorisation : la demande est faite explicitement, au
  /// moment ou l'utilisateur active un rappel, jamais au demarrage.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      tzdata.initializeTimeZones();

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestSoundPermission: false,
        requestBadgePermission: false,
      );

      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: darwin),
      );
      _initialized = true;
    } catch (_) {
      // Un appareil sans service de notifications ne doit pas empecher
      // l'application de fonctionner : on desactive simplement la fonction.
      _available = false;
    }
  }

  /// Demande l'autorisation a l'utilisateur.
  ///
  /// Retourne `false` si elle est refusee ou si la plateforme ne permet pas de
  /// la demander. L'appelant doit alors decocher le reglage correspondant.
  Future<bool> requestPermission() async {
    await initialize();
    if (!_available) return false;

    try {
      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        return await android?.requestNotificationsPermission() ?? false;
      }
      if (Platform.isIOS) {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        return await ios?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  /// Reprogramme les rappels d'apres les reglages.
  ///
  /// Reconstruit toujours la fenetre entiere : c'est ce qui rend le changement
  /// d'heure inoffensif et le changement de reglage immediat.
  Future<void> applySettings(AppSettings settings) async {
    await initialize();
    if (!_available) return;

    try {
      await _plugin.cancelAll();

      if (!settings.mealRemindersEnabled && !settings.dailySummaryEnabled) {
        return;
      }

      final maintenant = DateTime.now();

      if (settings.mealRemindersEnabled) {
        await _scheduleDailyWindow(
          baseId: _mealReminderBaseId,
          hour: settings.reminderHour,
          minute: settings.reminderMinute,
          channelId: _mealChannelId,
          channelName: 'Rappels de repas',
          channelDescription:
              'Vous rappelle de photographier votre repas pour en suivre les glucides.',
          title: 'Pense a ton repas',
          body: 'Une photo suffit pour estimer les glucides.',
          from: maintenant,
        );
      }

      if (settings.dailySummaryEnabled) {
        await _scheduleDailyWindow(
          baseId: _dailySummaryBaseId,
          hour: summaryHour,
          minute: summaryMinute,
          channelId: _summaryChannelId,
          channelName: 'Resume quotidien',
          channelDescription:
              'Fait le point sur les glucides de la journee en fin de soiree.',
          title: 'Tes glucides du jour',
          body: 'Ouvre Assiette pour voir ou tu en es.',
          from: maintenant,
        );
      }
    } catch (_) {
      // Un echec de programmation ne doit jamais faire echouer l'application.
    }
  }

  /// Supprime tous les rappels en attente.
  Future<void> cancelAll() async {
    await initialize();
    if (!_available) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {
      // Sans consequence : au pire un rappel de trop se declenche.
    }
  }

  Future<void> _scheduleDailyWindow({
    required int baseId,
    required int hour,
    required int minute,
    required String channelId,
    required String channelName,
    required String channelDescription,
    required String title,
    required String body,
    required DateTime from,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: const DarwinNotificationDetails(),
    );

    for (var decalage = 0; decalage < daysAhead; decalage++) {
      // Construit l'heure locale du jour vise. Le constructeur de DateTime
      // normalise les debordements de mois et applique les regles de changement
      // d'heure du systeme : l'instant absolu reste juste.
      final heureLocale = DateTime(
        from.year,
        from.month,
        from.day + decalage,
        hour,
        minute,
      );
      if (!heureLocale.isAfter(from)) continue;

      await _plugin.zonedSchedule(
        baseId + decalage,
        title,
        body,
        // Le fuseau du systeme n'est pas nomme ici : on transmet l'instant
        // absolu, exprime dans la zone UTC. L'interpretation « absoluteTime »
        // indique au systeme de traiter cette date comme un instant precis.
        tz.TZDateTime.from(heureLocale, tz.UTC),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }
}
