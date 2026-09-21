import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/apercu_aliment.dart';
import '../../models/food.dart';
import '../../models/meal.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/quantity_editor.dart';

/// Recherche d'aliments.
///
/// Deux sources complementaires, presentees separement pour que l'utilisateur
/// sache d'ou vient la valeur : la table Ciqual pour les aliments courants
/// (locale, instantanee, hors ligne) et Open Food Facts pour les produits
/// industriels (en ligne).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  Timer? _debounce;
  List<Food> _localResults = const [];
  List<Food> _productResults = const [];
  bool _searchingProducts = false;
  AppFailure? _productError;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();

    // Recherche locale immediate : elle est instantanee, inutile d'attendre.
    setState(() {
      _localResults = query.trim().length < 2
          ? const []
          : ref.read(ciqualRepositoryProvider).search(query, limit: 40);
    });

    if (query.trim().length < 3) {
      setState(() {
        _productResults = const [];
        _productError = null;
      });
      return;
    }

    // La recherche distante est differee : l'API Open Food Facts limite le
    // nombre de requetes par minute.
    _debounce = Timer(
      const Duration(milliseconds: 600),
      () => _searchProducts(query),
    );
  }

  Future<void> _searchProducts(String query) async {
    setState(() {
      _searchingProducts = true;
      _productError = null;
    });

    try {
      final results = await ref
          .read(openFoodFactsProvider)
          .search(query, limit: 20);
      if (!mounted || _controller.text.trim() != query.trim()) return;
      setState(() {
        _productResults = results;
        _searchingProducts = false;
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _productError = failure;
        _searchingProducts = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _productError = AppFailure.from(error);
        _searchingProducts = false;
      });
    }
  }

  Future<void> _selectFood(Food food) async {
    final portion = await ref.read(appDatabaseProvider).portionPour(food);
    if (!mounted) return;

    final grams = await showQuantityDialog(
      context,
      initial: food.servingSizeG ?? portion?.grams ?? 100,
      portion: portion,
    );
    if (grams == null || grams <= 0) return;

    final item = MealItem(
      food: food,
      quantityG: grams,
      portion: portion,
      isEstimate: false,
      portionSize: null,
    );

    final draft = ref.read(draftMealProvider);

    // Deux situations : completer un repas en cours, ou en demarrer un nouveau.
    if (draft == null) {
      final meal = Meal(
        eatenAt: DateTime.now(),
        name: _suggestName(DateTime.now()),
        items: [item],
        source: MealSource.search,
        isEstimate: false,
      );
      ref.read(draftMealProvider.notifier).start(meal);
    } else {
      ref.read(draftMealProvider.notifier).addItem(item);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${food.name} ajoute (${Format.grams(grams)}).'),
        action: SnackBarAction(
          label: 'Voir le repas',
          onPressed: () => context.push('/verification'),
        ),
      ),
    );
    context.pop();
  }

  static String _suggestName(DateTime at) {
    final hour = at.hour;
    if (hour < 11) return 'Petit-dejeuner';
    if (hour < 15) return 'Dejeuner';
    if (hour < 18) return 'Collation';
    return 'Diner';
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Rechercher un aliment')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: 'Riz, poulet, yaourt…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _controller.clear();
                            _onChanged('');
                          },
                          icon: const Icon(Icons.clear_rounded),
                          tooltip: 'Effacer',
                        ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: SegmentedButton<int>(
                segments: [
                  ButtonSegment(
                    value: 0,
                    label: Text('Aliments (${_localResults.length})'),
                    icon: const Icon(Icons.eco_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text('Produits (${_productResults.length})'),
                    icon: const Icon(Icons.qr_code_rounded, size: 16),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: (selection) =>
                    setState(() => _tab = selection.first),
              ),
            ),

            const SizedBox(height: AppSpacing.sm),

            Expanded(
              child: query.length < 2
                  ? const _SearchHint()
                  : _tab == 0
                  ? _LocalResults(results: _localResults, onSelect: _selectFood)
                  : _ProductResults(
                      results: _productResults,
                      loading: _searchingProducts,
                      error: _productError,
                      onSelect: _selectFood,
                      onRetry: () => _searchProducts(query),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.search_rounded,
      title: 'Cherchez un aliment',
      message:
          'Tapez au moins deux lettres. Les aliments courants sont disponibles '
          'hors ligne ; les produits emballes viennent d\'Open Food Facts.',
    );
  }
}

class _LocalResults extends StatelessWidget {
  const _LocalResults({required this.results, required this.onSelect});

  final List<Food> results;
  final void Function(Food) onSelect;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Aucun aliment trouve',
        message:
            'Essayez un mot plus simple, par exemple « riz » plutot que '
            '« riz basmati long grain ».',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      itemCount: results.length + 1,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        if (index == results.length) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Text(
              'Source : table Ciqual 2020 — ANSES — Licence Ouverte 2.0',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: context.palette.mutedText),
            ),
          );
        }
        return _FoodTile(
          food: results[index],
          onTap: () => onSelect(results[index]),
        );
      },
    );
  }
}

class _ProductResults extends StatelessWidget {
  const _ProductResults({
    required this.results,
    required this.loading,
    required this.error,
    required this.onSelect,
    required this.onRetry,
  });

  final List<Food> results;
  final bool loading;
  final AppFailure? error;
  final void Function(Food) onSelect;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!.message, textAlign: TextAlign.center),
              if (error!.hint != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  error!.hint!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.palette.mutedText),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              FilledButton(onPressed: onRetry, child: const Text('Reessayer')),
            ],
          ),
        ),
      );
    }

    if (results.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Aucun produit trouve',
        message:
            'La base de produits est collaborative : un produit recent peut '
            'ne pas y figurer. Utilisez l\'onglet Aliments ou lisez l\'etiquette.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      itemCount: results.length + 1,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        if (index == results.length) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Text(
              'Source : Open Food Facts — licence ODbL',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: context.palette.mutedText),
            ),
          );
        }
        return _FoodTile(
          food: results[index],
          onTap: () => onSelect(results[index]),
        );
      },
    );
  }
}

/// Ligne de resultat, avec un apercu des valeurs pour une portion ou 100 g.
class _FoodTile extends ConsumerWidget {
  const _FoodTile({required this.food, required this.onTap});

  final Food food;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

    // Les valeurs suivent la portion connue pour cet aliment — retenue par
    // l'utilisateur ou annoncee par la source — et retombent sur 100 g sinon.
    // Elles viennent du meme appel que leur reference : c'est ce qui garantit
    // que le nombre et l'unite parlent bien de la meme chose.
    ref.watch(portionsProvider);
    final portion = ref.read(portionsProvider.notifier).pour(food);
    final apercu = apercuDePortion(food, portion);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              if (food.imageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    food.imageUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) =>
                        _PlaceholderIcon(food: food),
                    loadingBuilder: (context, child, progress) =>
                        progress == null ? child : _PlaceholderIcon(food: food),
                  ),
                )
              else
                _PlaceholderIcon(food: food),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      food.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (food.brand != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        food.brand!,
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.mutedText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        _MiniValue(
                          label: 'glucides',
                          value: '${Format.number(apercu.valeurs.carbs)} g',
                          color: palette.carb,
                        ),
                        _MiniValue(
                          label: 'kcal',
                          value: Format.number(apercu.valeurs.kcal),
                          color: palette.mutedText,
                        ),
                        _MiniValue(
                          label: 'prot.',
                          value: '${Format.number(apercu.valeurs.protein)} g',
                          color: palette.protein,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      apercu.reference,
                      style: TextStyle(fontSize: 11, color: palette.mutedText),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                Icons.add_circle_outline_rounded,
                color: context.colors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceholderIcon extends StatelessWidget {
  const _PlaceholderIcon({required this.food});

  final Food food;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        food.source == FoodSource.openFoodFacts
            ? Icons.inventory_2_outlined
            : Icons.restaurant_rounded,
        size: 20,
        color: context.palette.mutedText,
      ),
    );
  }
}

class _MiniValue extends StatelessWidget {
  const _MiniValue({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 11, color: color),
        children: [
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          TextSpan(
            text: ' $label',
            style: TextStyle(color: context.palette.mutedText),
          ),
        ],
      ),
    );
  }
}
