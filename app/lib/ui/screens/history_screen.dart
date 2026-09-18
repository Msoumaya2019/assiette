import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/meal.dart';
import '../../models/nutrition_values.dart';
import '../../state/providers.dart';
import '../router.dart';
import '../widgets/carb_hero.dart';
import '../widgets/common.dart';
import '../widgets/meal_tile.dart';

/// Historique complet des repas, regroupes par jour.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meals = ref.watch(mealsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique'),
        actions: [
          IconButton(
            onPressed: () => ref.read(mealsProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: SafeArea(
        child: meals.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Lecture impossible',
            message: error.toString(),
            action: FilledButton(
              onPressed: () => ref.read(mealsProvider.notifier).refresh(),
              child: const Text('Reessayer'),
            ),
          ),
          data: (data) {
            if (data.isEmpty) {
              return EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Aucun repas enregistre',
                message:
                    'Vos repas apparaitront ici, jour par jour, avec leurs glucides.',
                action: FilledButton.icon(
                  onPressed: () => context.go(Routes.home),
                  icon: const Icon(Icons.photo_camera_rounded, size: 18),
                  label: const Text('Analyser un repas'),
                ),
              );
            }

            final grouped = _groupByDay(data);
            final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xxl,
              ),
              itemCount: days.length,
              itemBuilder: (context, index) {
                final day = days[index];
                final dayMeals = grouped[day]!;
                return _DaySection(
                  day: day,
                  meals: dayMeals,
                  onOpen: (meal) {
                    ref.read(draftMealProvider.notifier).start(meal);
                    context.push(Routes.review);
                  },
                  onDelete: (meal) => _confirmDelete(context, ref, meal),
                  onDuplicate: (meal) => _duplicate(context, ref, meal),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Map<DateTime, List<Meal>> _groupByDay(List<Meal> meals) {
    final grouped = <DateTime, List<Meal>>{};
    for (final meal in meals) {
      final day = DateTime(
        meal.eatenAt.year,
        meal.eatenAt.month,
        meal.eatenAt.day,
      );
      grouped.putIfAbsent(day, () => []).add(meal);
    }
    return grouped;
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Meal meal,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer ce repas ?'),
        content: Text(
          '${meal.name} — ${Format.carbs(meal.totals.carbs)} g de glucides.\n\n'
          'Cette action est definitive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(mealsProvider.notifier).delete(meal.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Repas supprime.')));
  }

  Future<void> _duplicate(
    BuildContext context,
    WidgetRef ref,
    Meal meal,
  ) async {
    await ref.read(mealsProvider.notifier).duplicate(meal);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('« ${meal.name} » duplique a l\'instant.')),
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.day,
    required this.meals,
    required this.onOpen,
    required this.onDelete,
    required this.onDuplicate,
  });

  final DateTime day;
  final List<Meal> meals;
  final void Function(Meal) onOpen;
  final void Function(Meal) onDelete;
  final void Function(Meal) onDuplicate;

  @override
  Widget build(BuildContext context) {
    final totals = NutritionValues.sum(meals.map((meal) => meal.totals));

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    Format.relativeDay(day),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${Format.carbs(totals.carbs)} g gluc. · ${Format.kcal(totals.kcal)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.palette.carb,
                  ),
                ),
              ],
            ),
          ),
          for (final meal in meals)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Dismissible(
                key: ValueKey(meal.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.danger,
                  ),
                ),
                confirmDismiss: (_) async {
                  // onDelete est synchrone : le `await` n'aurait pas de sens ici.
                  onDelete(meal);
                  return false;
                },
                child: MealTile(
                  meal: meal,
                  showDate: false,
                  onTap: () => onOpen(meal),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, size: 18),
                    onSelected: (action) {
                      switch (action) {
                        case 'open':
                          onOpen(meal);
                        case 'duplicate':
                          onDuplicate(meal);
                        case 'delete':
                          onDelete(meal);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'open',
                        child: Text('Ouvrir et modifier'),
                      ),
                      PopupMenuItem(
                        value: 'duplicate',
                        child: Text('Dupliquer'),
                      ),
                      PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Resume compact des glucides, reutilise dans plusieurs ecrans.
class CompactCarbSummary extends StatelessWidget {
  const CompactCarbSummary({
    super.key,
    required this.totals,
    required this.mealCount,
  });

  final NutritionValues totals;
  final int mealCount;

  @override
  Widget build(BuildContext context) {
    return CarbHero(
      carbs: totals.carbs,
      isEstimate: false,
      compact: true,
      title: 'Total · $mealCount repas',
    );
  }
}
