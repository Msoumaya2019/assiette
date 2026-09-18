import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/meal.dart';
import '../../services/nutrition_calculator.dart';
import '../../state/providers.dart';
import '../router.dart';
import '../widgets/carb_hero.dart';
import '../widgets/common.dart';
import '../widgets/meal_tile.dart';
import '../widgets/quantity_editor.dart';

/// Ecran de verification et de correction d'un repas.
///
/// C'est l'etape ou l'utilisateur reprend la main : chaque aliment peut etre
/// ajuste, remplace, supprime ou complete. Le total est recalcule a chaque
/// geste, sans jamais etre saisi directement.
class MealReviewScreen extends ConsumerStatefulWidget {
  const MealReviewScreen({super.key});

  @override
  ConsumerState<MealReviewScreen> createState() => _MealReviewScreenState();
}

class _MealReviewScreenState extends ConsumerState<MealReviewScreen> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final meal = ref.watch(draftMealProvider);
    final settings = ref.watch(settingsProvider);

    if (meal == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Repas')),
        body: EmptyState(
          icon: Icons.no_meals_rounded,
          title: 'Aucun repas en cours',
          message: 'Commencez par analyser une photo ou rechercher un aliment.',
          action: FilledButton(
            onPressed: () => context.go(Routes.home),
            child: const Text('Revenir a l\'accueil'),
          ),
        ),
      );
    }

    final totals = meal.totals;
    final (rangeLow, rangeHigh) = NutritionCalculator.carbsRange(meal);
    final notifier = ref.read(draftMealProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verifier le repas'),
        actions: [
          IconButton(
            onPressed: () => _showMoreActions(context, meal),
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'Autres actions',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xxl,
          ),
          children: [
            CarbHero(
              carbs: totals.carbs,
              rangeLow: rangeLow,
              rangeHigh: rangeHigh,
              isEstimate: meal.isEstimate,
              goalG: settings.goals.carbsG,
              title: 'Glucides de ce repas',
            ),

            const SizedBox(height: AppSpacing.md),

            if (meal.needsReview)
              const EstimateBanner(
                message:
                    'La confiance de l\'analyse est faible. Verifiez les quantites '
                    'avant d\'enregistrer : un poids errone change beaucoup le total.',
                severity: EstimateSeverity.warning,
              )
            else
              const EstimateBanner(),

            const SizedBox(height: AppSpacing.lg),

            MacroGrid(totals: totals),

            const SizedBox(height: AppSpacing.lg),

            _MealDetailsCard(
              meal: meal,
              onRename: notifier.rename,
              onSetTime: notifier.setEatenAt,
            ),

            const SizedBox(height: AppSpacing.lg),

            SectionCard(
              title: 'Aliments detectes',
              subtitle: '${meal.items.length} aliment${meal.items.length > 1 ? 's' : ''} · '
                  '${Format.grams(meal.totalGrams)} au total',
              child: Column(
                children: [
                  for (final item in meal.items)
                    _EditableItem(
                      item: item,
                      onQuantityChanged: (grams) => notifier.setQuantity(item.id, grams),
                      onRemove: () => notifier.removeItem(item.id),
                      onReplace: () => _replaceItem(context, item),
                    ),
                  if (meal.items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                      child: Text(
                        'Aucun aliment dans ce repas. Ajoutez-en un ci-dessous.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.palette.mutedText),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            OutlinedButton.icon(
              onPressed: () => context.push('${Routes.search}?mode=add'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter un aliment'),
            ),

            const SizedBox(height: AppSpacing.sm),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(Routes.barcode),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Code-barres'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(Routes.label),
                    icon: const Icon(Icons.document_scanner_rounded, size: 18),
                    label: const Text('Etiquette'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),

            _ScaleAllCard(onApply: notifier.applyFactorToAll),

            const SizedBox(height: AppSpacing.lg),

            FilledButton.icon(
              onPressed: _saving ? null : () => _save(context, meal),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? 'Enregistrement…' : 'Enregistrer ce repas'),
            ),

            const SizedBox(height: AppSpacing.sm),

            TextButton(
              onPressed: () {
                ref.read(draftMealProvider.notifier).clear();
                ref.read(pendingCaptureProvider.notifier).clear();
                context.go(Routes.home);
              },
              child: const Text('Abandonner'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context, Meal meal) async {
    if (meal.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoutez au moins un aliment avant d\'enregistrer.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(mealsProvider.notifier).save(meal);
      ref.read(draftMealProvider.notifier).clear();
      ref.read(pendingCaptureProvider.notifier).clear();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Repas enregistre : ${Format.carbs(meal.totals.carbs)} g de glucides.',
          ),
        ),
      );
      context.go(Routes.home);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enregistrement impossible : $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _replaceItem(BuildContext context, MealItem item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                item.food.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.search_rounded),
              title: const Text('Remplacer par un autre aliment'),
              onTap: () => Navigator.of(sheetContext).pop('replace'),
            ),
            ListTile(
              leading: const Icon(Icons.scale_rounded),
              title: const Text('Saisir le poids reel'),
              onTap: () => Navigator.of(sheetContext).pop('weight'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Supprimer cet aliment'),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted || action == null) return;

    switch (action) {
      case 'replace':
        context.push('${Routes.search}?mode=replace&item=${item.id}');
      case 'weight':
        final grams = await showQuantityDialog(context, initial: item.quantityG);
        if (grams != null) {
          ref.read(draftMealProvider.notifier).setQuantity(item.id, grams);
        }
      case 'delete':
        ref.read(draftMealProvider.notifier).removeItem(item.id);
    }
  }

  Future<void> _showMoreActions(BuildContext context, Meal meal) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.bookmark_add_outlined),
              title: const Text('Enregistrer comme repas type'),
              subtitle: const Text('Reutilisable en un geste'),
              onTap: () => Navigator.of(sheetContext).pop('template'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Dupliquer ce repas'),
              onTap: () => Navigator.of(sheetContext).pop('duplicate'),
            ),
            ListTile(
              leading: const Icon(Icons.note_alt_outlined),
              title: const Text('Ajouter une note'),
              onTap: () => Navigator.of(sheetContext).pop('note'),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted || action == null) return;

    switch (action) {
      case 'template':
        await _saveAsTemplate(context, meal);
      case 'duplicate':
        ref.read(draftMealProvider.notifier).start(
              Meal(
                eatenAt: DateTime.now(),
                name: meal.name,
                items: meal.items
                    .map((item) => MealItem(food: item.food, quantityG: item.quantityG))
                    .toList(),
                source: meal.source,
              ),
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Copie creee : modifiez-la puis enregistrez.')),
          );
        }
      case 'note':
        final controller = TextEditingController(text: meal.notes ?? '');
        final note = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Note'),
            content: TextField(
              controller: controller,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Par exemple : restaurant, invite…'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(controller.text),
                child: const Text('Valider'),
              ),
            ],
          ),
        );
        if (note != null) ref.read(draftMealProvider.notifier).setNotes(note);
    }
  }

  Future<void> _saveAsTemplate(BuildContext context, Meal meal) async {
    final controller = TextEditingController(text: meal.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nom du repas type'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Mon petit-dejeuner'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    await ref.read(templatesProvider.notifier).save(
          DateTime.now().microsecondsSinceEpoch.toString(),
          name,
          meal.items,
        );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('« $name » enregistre dans vos repas types.')),
    );
  }
}

/// Carte de modification du nom et de l'heure du repas.
class _MealDetailsCard extends StatelessWidget {
  const _MealDetailsCard({required this.meal, required this.onRename, required this.onSetTime});

  final Meal meal;
  final void Function(String) onRename;
  final void Function(DateTime) onSetTime;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Details',
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.label_outline_rounded, size: 20),
            title: const Text('Nom du repas', style: TextStyle(fontSize: 14)),
            subtitle: Text(meal.name),
            trailing: const Icon(Icons.edit_rounded, size: 18),
            onTap: () async {
              final controller = TextEditingController(text: meal.name);
              final name = await showDialog<String>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Nom du repas'),
                  content: TextField(controller: controller, autofocus: true),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Annuler'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
                      child: const Text('Valider'),
                    ),
                  ],
                ),
              );
              if (name != null && name.isNotEmpty) onRename(name);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_rounded, size: 20),
            title: const Text('Date et heure', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              '${Format.relativeDay(meal.eatenAt)} a ${Format.time(meal.eatenAt)}',
            ),
            trailing: const Icon(Icons.edit_rounded, size: 18),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: meal.eatenAt,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              );
              if (date == null || !context.mounted) return;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(meal.eatenAt),
              );
              if (time == null) return;
              onSetTime(DateTime(date.year, date.month, date.day, time.hour, time.minute));
            },
          ),
        ],
      ),
    );
  }
}

/// Ligne d'aliment modifiable, avec reglage rapide de la quantite.
class _EditableItem extends StatefulWidget {
  const _EditableItem({
    required this.item,
    required this.onQuantityChanged,
    required this.onRemove,
    required this.onReplace,
  });

  final MealItem item;
  final void Function(double) onQuantityChanged;
  final VoidCallback onRemove;
  final VoidCallback onReplace;

  @override
  State<_EditableItem> createState() => _EditableItemState();
}

class _EditableItemState extends State<_EditableItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final totals = item.total;

    return Column(
      children: [
        MealItemRow(
          name: item.food.name,
          quantityG: item.quantityG,
          totals: totals,
          sourceLabel: item.food.source.displayLabel,
          confidence: item.confidence,
          onTap: () => setState(() => _expanded = !_expanded),
          trailing: Icon(
            _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            size: 18,
            color: context.palette.mutedText,
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: QuantityEditor(
              quantityG: item.quantityG,
              onChange: widget.onQuantityChanged,
              onReplace: widget.onReplace,
              onRemove: widget.onRemove,
              sourceLabel: item.food.source.displayLabel,
              isEstimate: item.isEstimate,
            ),
          ),
        Divider(color: context.palette.cardBorder, height: 1),
      ],
    );
  }
}

/// Application d'un coefficient a l'ensemble du repas.
class _ScaleAllCard extends StatelessWidget {
  const _ScaleAllCard({required this.onApply});

  final void Function(double) onApply;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Ajuster tout le repas',
      subtitle: 'Utile lorsque l\'assiette etait plus grande ou plus petite que prevu',
      child: Wrap(
        spacing: AppSpacing.sm,
        children: [
          for (final (label, factor) in const [
            ('Moitie', 0.5),
            ('Un peu moins', 0.8),
            ('Inchange', 1.0),
            ('Un peu plus', 1.25),
            ('Presque double', 1.8),
          ])
            ActionChip(
              label: Text(label),
              onPressed: () => onApply(factor),
            ),
        ],
      ),
    );
  }
}
