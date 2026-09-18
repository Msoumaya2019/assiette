import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'state/providers.dart';
import 'ui/router.dart';

/// Racine de l'application : themes, localisation et navigation.
class AssietteApp extends ConsumerWidget {
  const AssietteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,

      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,

      routerConfig: router,

      // Le francais est la langue de reference ; l'anglais sert de repli pour
      // les widgets Material non traduits.
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      builder: (context, child) {
        // Le texte ne doit jamais depasser la taille demandee par l'utilisateur,
        // mais il doit pouvoir grandir : les mises en page utilisent des
        // conteneurs souples plutot que des hauteurs fixes.
        final scaler = MediaQuery.textScalerOf(context);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: scaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.6),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
