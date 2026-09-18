import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/local/app_database.dart';
import '../../state/providers.dart';
import '../router.dart';
import '../widgets/common.dart';

/// Repas types : des ensembles d'aliments reutilisables en un geste.
class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Repas enregistres'),
        actions: [
          IconButton(
            onPressed: () => context.push(Routes.search),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Composer un repas',
          ),
        ],
      ),
      body: SafeArea(
        child: templates.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Lecture impossible',
            message: error.toString(),
          ),
          data: (items) {
            if (items.isEmpty) {
              return EmptyState(
                icon: Icons.bookmark_border_rounded,
                title: 'Aucun repas enregistre',
                message:
                    'Composez un repas, puis enregistrez-le comme modele depuis '
                    'l\'ecran de verification. Vous pourrez le reutiliser en un geste.',
                action: FilledButton.icon(
                  onPressed: () => context.push(Routes.search),
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Composer un repas'),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xxl,
              ),
              itemCount: items.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) => _TemplateCard(
                template: items[index],
                onUse: () => _use(context, ref, items[index]),
                onEdit: () {
                  ref
                      .read(draftMealProvider.notifier)
                      .start(
                        ref
                            .read(templatesProvider.notifier)
                            .instantiate(items[index]),
                      );
                  context.push(Routes.review);
                },
                onDelete: () => _confirmDelete(context, ref, items[index]),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _use(
    BuildContext context,
    WidgetRef ref,
    MealTemplate template,
  ) async {
    final meal = ref.read(templatesProvider.notifier).instantiate(template);
    await ref.read(mealsProvider.notifier).save(meal);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '« ${template.name} » ajoute : ${Format.carbs(meal.totals.carbs)} g de glucides.',
        ),
      ),
    );
    context.go(Routes.home);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    MealTemplate template,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer ce repas type ?'),
        content: Text('« ${template.name} » sera retire de vos modeles.'),
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
    await ref.read(templatesProvider.notifier).remove(template.id);
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.onUse,
    required this.onEdit,
    required this.onDelete,
  });

  final MealTemplate template;
  final VoidCallback onUse;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final totals = template.totals;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    template.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: palette.carb.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${Format.carbs(totals.carbs)} g gluc.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: palette.carb,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${template.items.length} aliment${template.items.length > 1 ? 's' : ''} · '
              '${Format.grams(template.totalGrams)} · ${Format.kcal(totals.kcal)}',
              style: TextStyle(fontSize: 12, color: palette.mutedText),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final item in template.items.take(4))
                  Chip(
                    label: Text(
                      '${item.food.name} ${Format.grams(item.quantityG)}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                if (template.items.length > 4)
                  Chip(
                    label: Text(
                      '+${template.items.length - 4}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onUse,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Ajouter'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton.outlined(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  tooltip: 'Modifier avant d\'ajouter',
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton.outlined(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  tooltip: 'Supprimer',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
