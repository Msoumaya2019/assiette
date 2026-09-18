import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/app_settings.dart';
import 'screens/analysis_screen.dart';
import 'screens/barcode_screen.dart';
import 'screens/capture_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/goals_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/label_screen.dart';
import 'screens/meal_review_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/privacy_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/templates_screen.dart';
import 'widgets/app_shell.dart';

/// Chemins de navigation, centralises pour eviter les chaines dispersees.
class Routes {
  const Routes._();

  static const String home = '/';
  static const String history = '/historique';
  static const String stats = '/statistiques';
  static const String favorites = '/favoris';
  static const String settings = '/reglages';

  static const String capture = '/capture';
  static const String analysis = '/analyse';
  static const String review = '/verification';
  static const String search = '/recherche';
  static const String barcode = '/code-barres';
  static const String label = '/etiquette';
  static const String templates = '/repas-enregistres';
  static const String goals = '/objectifs';
  static const String privacy = '/confidentialite';
  static const String onboarding = '/bienvenue';
}

/// Le routeur est construit une seule fois par le conteneur de providers :
/// le recreer a chaque reconstruction reinitialiserait la pile de navigation.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.history,
                builder: (context, state) => const HistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.stats,
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.favorites,
                builder: (context, state) => const FavoritesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.settings,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),

      // Ecrans plein ecran, hors barre de navigation.
      GoRoute(
        path: Routes.capture,
        builder: (context, state) =>
            CaptureScreen(source: state.uri.queryParameters['source']),
      ),
      GoRoute(
        path: Routes.analysis,
        builder: (context, state) => const AnalysisScreen(),
      ),
      GoRoute(
        path: Routes.review,
        builder: (context, state) => const MealReviewScreen(),
      ),
      GoRoute(
        path: Routes.search,
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        path: Routes.barcode,
        builder: (context, state) => const BarcodeScreen(),
      ),
      GoRoute(
        path: Routes.label,
        builder: (context, state) => const LabelScreen(),
      ),
      GoRoute(
        path: Routes.templates,
        builder: (context, state) => const TemplatesScreen(),
      ),
      GoRoute(
        path: Routes.goals,
        builder: (context, state) => const GoalsScreen(),
      ),
      GoRoute(
        path: Routes.privacy,
        builder: (context, state) => const PrivacyScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page introuvable')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_off_rounded, size: 40),
              const SizedBox(height: 16),
              Text(
                'Cet ecran n\'existe pas.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.go(Routes.home),
                child: const Text('Revenir a l\'accueil'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
});

/// Indique si l'assistant de premiere utilisation doit etre affiche.
bool needsOnboarding(AppSettings settings) =>
    !settings.onboardingDone || !settings.hasAcceptedPrivacyPolicy;
