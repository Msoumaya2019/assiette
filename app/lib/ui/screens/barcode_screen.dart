import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/apercu_aliment.dart';
import '../../models/food.dart';
import '../../models/meal.dart';
import '../../state/providers.dart';
import '../router.dart';
import '../widgets/common.dart';
import '../widgets/quantity_editor.dart';

/// Lecture d'un code-barres produit.
///
/// Le scan declenche la recherche dans Open Food Facts, puis la saisie de la
/// quantite consommee. Si le produit est absent de la base, la saisie manuelle
/// prend le relais sans interrompre le parcours.
class BarcodeScreen extends ConsumerStatefulWidget {
  const BarcodeScreen({super.key});

  @override
  ConsumerState<BarcodeScreen> createState() => _BarcodeScreenState();
}

class _BarcodeScreenState extends ConsumerState<BarcodeScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
  );

  bool _handling = false;
  Food? _product;
  AppFailure? _error;
  String? _lastCode;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;

    final code = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .firstWhere(
          (value) => value != null && value.length >= 8,
          orElse: () => null,
        );

    if (code == null || code == _lastCode) return;

    _lastCode = code;
    setState(() {
      _handling = true;
      _error = null;
      _product = null;
    });

    await _controller.stop();

    try {
      final product = await ref
          .read(openFoodFactsProvider)
          .fetchByBarcode(code);
      if (!mounted) return;
      setState(() {
        _product = product;
        _handling = false;
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure;
        _handling = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AppFailure.from(error);
        _handling = false;
      });
    }
  }

  void _resume() {
    setState(() {
      _product = null;
      _error = null;
      _lastCode = null;
    });
    _controller.start();
  }

  Future<void> _addProduct(Food food) async {
    // La portion retenue pour ce produit est proposee d'emblee : c'est ce qui
    // evite de redire « 1 pot = 150 g » a chaque scan.
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
    );
    final draft = ref.read(draftMealProvider);

    if (draft == null) {
      ref
          .read(draftMealProvider.notifier)
          .start(
            Meal(
              eatenAt: DateTime.now(),
              name: _suggestName(DateTime.now()),
              items: [item],
              source: MealSource.barcode,
              isEstimate: false,
            ),
          );
    } else {
      ref.read(draftMealProvider.notifier).addItem(item);
    }

    if (!mounted) return;
    context.push(Routes.review);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner un produit'),
        actions: [
          IconButton(
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flashlight_on_rounded),
            tooltip: 'Lampe',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(controller: _controller, onDetect: _onDetect),
                  const _ScannerOverlay(),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _buildPanel(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel() {
    if (_product != null) {
      return _ProductPanel(
        food: _product!,
        onAdd: () => _addProduct(_product!),
        onScanAgain: _resume,
      );
    }

    if (_error != null) {
      return _ErrorPanel(
        failure: _error!,
        onRetry: _resume,
        onManual: () => context.push(Routes.search),
        onLabel: () => context.push(Routes.label),
      );
    }

    return const Padding(
      padding: EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          Icon(Icons.center_focus_strong_rounded, size: 30, color: Colors.grey),
          SizedBox(height: AppSpacing.sm),
          Text(
            'Visez le code-barres du produit',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: AppSpacing.xs),
          Text(
            'La recherche interroge la base Open Food Facts.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 260,
          height: 160,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.9),
              width: 2.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductPanel extends ConsumerWidget {
  const _ProductPanel({
    required this.food,
    required this.onAdd,
    required this.onScanAgain,
  });

  final Food food;
  final VoidCallback onAdd;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

    // Les valeurs affichees suivent la portion retenue pour ce produit : le
    // pot annonce « 1 pot (125 g) » vaut ses 125 g, pas ses 100 g. La reference
    // et les valeurs viennent d'un seul appel — c'est ce qui garantit qu'elles
    // parlent de la meme unite.
    ref.watch(portionsProvider);
    final portion = ref.read(portionsProvider.notifier).pour(food);
    final apercu = apercuDePortion(food, portion);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (food.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  food.imageUrl!,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) =>
                      const SizedBox(width: 64, height: 64),
                ),
              ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    food.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (food.brand != null)
                    Text(
                      food.brand!,
                      style: TextStyle(fontSize: 13, color: palette.mutedText),
                    ),
                  const SizedBox(height: 4),
                  const SourceBadge(
                    label: 'Open Food Facts',
                    color: Color(0xFF4A7C94),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: AppSpacing.md),

        if (food.per100g.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: palette.carb.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: palette.carb.withValues(alpha: 0.28)),
            ),
            child: Row(
              children: [
                Text(
                  Format.carbs(apercu.valeurs.carbs),
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: palette.carb,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'g de glucides\n${apercu.reference}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: palette.carb,
                  ),
                ),
                const Spacer(),
                Text(
                  Format.kcal(apercu.valeurs.kcal),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: palette.mutedText,
                  ),
                ),
              ],
            ),
          )
        else
          const EstimateBanner(
            message:
                'Ce produit figure dans la base mais sans valeurs nutritionnelles. '
                'Vous pouvez lire l\'etiquette pour les saisir.',
            severity: EstimateSeverity.warning,
          ),

        const SizedBox(height: AppSpacing.md),

        FilledButton.icon(
          onPressed: food.per100g.isNotEmpty ? onAdd : null,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Ajouter au repas'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: onScanAgain,
          icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
          label: const Text('Scanner un autre produit'),
        ),
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.failure,
    required this.onRetry,
    required this.onManual,
    required this.onLabel,
  });

  final AppFailure failure;
  final VoidCallback onRetry;
  final VoidCallback onManual;
  final VoidCallback onLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EstimateBanner(
          message: failure.hint == null
              ? failure.message
              : '${failure.message}. ${failure.hint}',
          severity: EstimateSeverity.warning,
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Scanner a nouveau'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: onManual,
          icon: const Icon(Icons.search_rounded, size: 18),
          label: const Text('Chercher l\'aliment a la main'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: onLabel,
          icon: const Icon(Icons.document_scanner_rounded, size: 18),
          label: const Text('Lire l\'etiquette du produit'),
        ),
      ],
    );
  }
}
