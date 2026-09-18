import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/local/app_database.dart';
import '../../models/food.dart';
import '../../models/meal.dart';
import '../../state/providers.dart';
import '../router.dart';
import '../widgets/common.dart';
import '../widgets/quantity_editor.dart';

/// Favoris : aliments, produits et repas types, accessibles en un geste.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favoris'),
        actions: [
          IconButton(
            onPressed: () => context.push(Routes.templates),
            icon: const Icon(Icons.bookmark_rounded),
            tooltip: 'Repas enregistres',
          ),
        ],
      ),
      body: SafeArea(
        child: favorites.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Lecture impossible',
            message: error.toString(),
          ),
          data: (items) {
            if (items.isEmpty) {
              return EmptyState(
                icon: Icons.star_outline_rounded,
                title: 'Aucun favori',
                message:
                    'Touchez l\'etoile sur un aliment ou un produit pour le '
                    'retrouver ici, sans avoir a le rechercher a chaque fois.',
                action: FilledButton.icon(
                  onPressed: () => context.push(Routes.search),
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Chercher un aliment'),
                ),
              );
            }

            final foods = items
                .where((item) => item.kind != 'template')
                .toList();
            final templates = items
                .where((item) => item.kind == 'template')
                .toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xxl,
              ),
              children: [
                if (foods.isNotEmpty) ...[
                  SectionCard(
                    title: 'Aliments et produits',
                    subtitle:
                        '${foods.length} favori${foods.length > 1 ? 's' : ''}',
                    child: Column(
                      children: [
                        for (final favorite in foods)
                          _FavoriteTile(
                            favorite: favorite,
                            onAdd: () => _addFood(context, ref, favorite),
                            onRemove: () => ref
                                .read(favoritesProvider.notifier)
                                .remove(favorite.id),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (templates.isNotEmpty)
                  SectionCard(
                    title: 'Repas types',
                    subtitle:
                        '${templates.length} repas enregistre${templates.length > 1 ? 's' : ''}',
                    child: Column(
                      children: [
                        for (final favorite in templates)
                          _FavoriteTile(
                            favorite: favorite,
                            onAdd: () => _addTemplate(context, ref, favorite),
                            onRemove: () => ref
                                .read(favoritesProvider.notifier)
                                .remove(favorite.id),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _addFood(
    BuildContext context,
    WidgetRef ref,
    Favorite favorite,
  ) async {
    final food = favorite.asFood;
    if (food == null) return;

    final grams = await showQuantityDialog(
      context,
      initial: food.servingSizeG ?? 100,
    );
    if (grams == null || grams <= 0) return;

    final item = MealItem(food: food, quantityG: grams, isEstimate: false);
    final draft = ref.read(draftMealProvider);

    if (draft == null) {
      ref
          .read(draftMealProvider.notifier)
          .start(
            Meal(
              eatenAt: DateTime.now(),
              name: _suggestName(DateTime.now()),
              items: [item],
              source: MealSource.search,
              isEstimate: false,
            ),
          );
    } else {
      ref.read(draftMealProvider.notifier).addItem(item);
    }

    if (!context.mounted) return;
    context.push(Routes.review);
  }

  Future<void> _addTemplate(
    BuildContext context,
    WidgetRef ref,
    Favorite favorite,
  ) async {
    final raw = favorite.payload['items'];
    if (raw is! List) return;

    final items = raw
        .map((item) => MealItem.fromJson((item as Map).cast<String, dynamic>()))
        .toList();

    ref
        .read(draftMealProvider.notifier)
        .start(
          Meal(
            eatenAt: DateTime.now(),
            name: favorite.label,
            items: items,
            source: MealSource.template,
            isEstimate: false,
          ),
        );

    if (!context.mounted) return;
    context.push(Routes.review);
  }

  static String _suggestName(DateTime at) {
    final hour = at.hour;
    if (hour < 11) return 'Petit-dejeuner';
    if (hour < 15) return 'Dejeuner';
    if (hour < 18) return 'Collation';
    return 'Diner';
  }
}

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({
    required this.favorite,
    required this.onAdd,
    required this.onRemove,
  });

  final Favorite favorite;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final food = favorite.asFood;
    final palette = context.palette;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          favorite.kind == 'template'
              ? Icons.bookmark_rounded
              : favorite.kind == 'product'
              ? Icons.inventory_2_outlined
              : Icons.restaurant_rounded,
          size: 18,
          color: palette.mutedText,
        ),
      ),
      title: Text(
        favorite.label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: food == null
          ? null
          : Text(
              '${Format.carbs(food.per100g.carbs)} g glucides / 100 g · ${food.source.displayLabel}',
              style: TextStyle(fontSize: 12, color: palette.mutedText),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onAdd,
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: 'Ajouter a un repas',
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.star_rounded, color: AppColors.carbAmber),
            tooltip: 'Retirer des favoris',
          ),
        ],
      ),
    );
  }
}

/// Bouton d'ajout ou de retrait des favoris, utilise dans les autres ecrans.
class FavoriteButton extends ConsumerWidget {
  const FavoriteButton({
    super.key,
    required this.id,
    required this.kind,
    required this.label,
    required this.payload,
  });

  final String id;
  final String kind;
  final String label;
  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    final isFavorite = favorites.maybeWhen(
      data: (items) => items.any((item) => item.id == id),
      orElse: () => false,
    );

    return IconButton(
      onPressed: () => ref
          .read(favoritesProvider.notifier)
          .toggle(id: id, kind: kind, label: label, payload: payload),
      icon: Icon(isFavorite ? Icons.star_rounded : Icons.star_outline_rounded),
      color: isFavorite ? AppColors.carbAmber : null,
      tooltip: isFavorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
    );
  }
}

/// Convertit un aliment en charge utile de favori.
Map<String, dynamic> foodFavoritePayload(Food food) => {'food': food.toJson()};
