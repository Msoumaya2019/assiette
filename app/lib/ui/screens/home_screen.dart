import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/goals.dart';
import '../../models/nutrition_values.dart';
import '../../state/providers.dart';
import '../router.dart';
import '../widgets/carb_hero.dart';
import '../widgets/common.dart';
import '../widgets/meal_tile.dart';

/// Ecran d'accueil.
///
/// Trois actions principales, immediatement visibles : analyser un repas,
/// scanner un produit, rechercher un aliment. Le reste de l'application est
/// accessible mais volontairement secondaire.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final summary = ref.watch(todaySummaryProvider);
    final meals = ref.watch(mealsProvider);
    final now = DateTime.now();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => ref.read(mealsProvider.notifier).refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xxl,
            ),
            children: [
              _Header(date: now),
              const SizedBox(height: AppSpacing.lg),

              // Bloc principal : les glucides du jour.
              summary.when(
                loading: () => const _CarbSkeleton(),
                error: (error, _) => EstimateBanner(
                  message: 'Impossible de lire vos repas : ${error.toString()}',
                  severity: EstimateSeverity.danger,
                ),
                data: (data) => CarbHero(
                  carbs: data.totals.carbs,
                  goalG: settings.goals.carbsG,
                  isEstimate: false,
                  title: 'Glucides aujourd\'hui',
                ),
              ),

              const SizedBox(height: AppSpacing.lg),
              const _PrimaryActions(),
              const SizedBox(height: AppSpacing.lg),

              summary.maybeWhen(
                data: (data) => MacroGrid(
                  totals: data.totals,
                  goal: _goalValues(settings.goals),
                ),
                orElse: () => const SizedBox.shrink(),
              ),

              const SizedBox(height: AppSpacing.lg),
              const _QuickAccess(),
              const SizedBox(height: AppSpacing.lg),

              meals.when(
                loading: () => const SizedBox(
                  height: 80,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => SectionCard(
                  title: 'Repas recents',
                  child: Text('Lecture impossible : ${error.toString()}'),
                ),
                data: (data) {
                  final recent = data.take(4).toList();
                  if (recent.isEmpty) {
                    return const _FirstMealHint();
                  }
                  return SectionCard(
                    title: 'Repas recents',
                    subtitle: '${data.length} repas enregistres',
                    trailing: TextButton(
                      onPressed: () => context.go(Routes.history),
                      child: const Text('Tout voir'),
                    ),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.sm,
                    ),
                    child: Column(
                      children: [
                        for (final meal in recent) ...[
                          MealTile(
                            meal: meal,
                            onTap: () {
                              ref.read(draftMealProvider.notifier).start(meal);
                              context.push(Routes.review);
                            },
                          ),
                          if (meal != recent.last)
                            const SizedBox(height: AppSpacing.sm),
                        ],
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: AppSpacing.md),
              const _AttributionFooter(),
            ],
          ),
        ),
      ),
    );
  }

  /// Convertit les objectifs quotidiens en valeurs de reference pour l'affichage
  /// de la progression. Les objectifs non definis restent a zero, ce qui
  /// desactive la barre correspondante.
  NutritionValues _goalValues(DailyGoals goals) {
    return NutritionValues(
      kcal: goals.kcal ?? 0,
      protein: goals.proteinG ?? 0,
      fat: goals.fatG ?? 0,
      fiber: goals.fiberG ?? 0,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final hour = date.hour;
    final greeting = hour < 12
        ? 'Bonjour'
        : hour < 18
        ? 'Bon apres-midi'
        : 'Bonsoir';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.palette.mutedText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                Format.weekdayDayMonth(date),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: () => context.go(Routes.goals),
          icon: const Icon(Icons.flag_rounded),
          tooltip: 'Objectifs quotidiens',
        ),
      ],
    );
  }
}

/// Les trois actions principales de l'application.
class _PrimaryActions extends ConsumerWidget {
  const _PrimaryActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _ActionCard(
          icon: Icons.photo_camera_rounded,
          title: 'Analyser mon repas',
          subtitle: 'Prenez une photo, l\'application estime les glucides',
          highlighted: true,
          onTap: () => _startPhotoFlow(context, ref),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                icon: Icons.qr_code_scanner_rounded,
                title: 'Scanner un produit',
                subtitle: 'Code-barres',
                onTap: () => context.push(Routes.barcode),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _ActionCard(
                icon: Icons.search_rounded,
                title: 'Rechercher',
                subtitle: 'Aliment ou plat',
                onTap: () => context.push(Routes.search),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _startPhotoFlow(BuildContext context, WidgetRef ref) {
    ref.read(draftMealProvider.notifier).clear();
    context.push(Routes.capture);
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Material(
      color: highlighted ? colors.primary : colors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: highlighted
                ? null
                : Border.all(color: context.palette.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: highlighted
                      ? colors.onPrimary.withValues(alpha: 0.18)
                      : colors.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: highlighted ? 26 : 20,
                  color: highlighted
                      ? colors.onPrimary
                      : colors.onPrimaryContainer,
                ),
              ),
              SizedBox(height: highlighted ? AppSpacing.md : AppSpacing.sm),
              Text(
                title,
                style: TextStyle(
                  fontSize: highlighted ? 19 : 14,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  color: highlighted ? colors.onPrimary : colors.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: highlighted ? 13 : 11,
                  height: 1.3,
                  color: highlighted
                      ? colors.onPrimary.withValues(alpha: 0.85)
                      : context.palette.mutedText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAccess extends StatelessWidget {
  const _QuickAccess();

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String)>[
      (Icons.bookmark_rounded, 'Repas enregistres', Routes.templates),
      (Icons.document_scanner_rounded, 'Lire une etiquette', Routes.label),
      (Icons.star_rounded, 'Mes favoris', Routes.favorites),
      (Icons.insights_rounded, 'Statistiques', Routes.stats),
    ];

    return SectionCard(
      title: 'Acces rapide',
      child: Column(
        children: [
          for (final (icon, label, route) in items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon, size: 20),
              title: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () => context.go(route),
              dense: true,
            ),
        ],
      ),
    );
  }
}

class _FirstMealHint extends StatelessWidget {
  const _FirstMealHint();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Bienvenue',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Photographiez votre prochain repas : l\'application identifie les aliments '
            'et estime les glucides. Vous pourrez corriger chaque quantite avant '
            'd\'enregistrer.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: context.palette.mutedText,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: () => context.push(Routes.onboarding),
            icon: const Icon(Icons.help_outline_rounded, size: 18),
            label: const Text('Comment ca marche'),
          ),
        ],
      ),
    );
  }
}

class _CarbSkeleton extends StatelessWidget {
  const _CarbSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
    );
  }
}

class _AttributionFooter extends StatelessWidget {
  const _AttributionFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Text(
        'Valeurs nutritionnelles : table Ciqual 2020 (ANSES, Licence Ouverte 2.0) '
        'et base Open Food Facts (ODbL).\n'
        'Les quantites deduites d\'une photo sont des estimations, pas des mesures.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          height: 1.5,
          color: context.palette.mutedText,
        ),
      ),
    );
  }
}
