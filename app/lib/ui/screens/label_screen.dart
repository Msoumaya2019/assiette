import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/failures.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/vision/vision_provider.dart';
import '../../models/analysis_result.dart';
import '../../models/food.dart';
import '../../models/meal.dart';
import '../../models/nutrition_values.dart';
import '../../services/image_service.dart';
import '../../state/providers.dart';
import '../router.dart';
import '../widgets/common.dart';
import '../widgets/quantity_editor.dart';

/// Lecture d'une etiquette nutritionnelle.
///
/// L'extraction automatique sert de point de depart : chaque valeur reste
/// modifiable, et rien n'est enregistre sans validation. Une valeur illisible
/// reste vide plutot que d'etre devinee.
class LabelScreen extends ConsumerStatefulWidget {
  const LabelScreen({super.key});

  @override
  ConsumerState<LabelScreen> createState() => _LabelScreenState();
}

class _LabelScreenState extends ConsumerState<LabelScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _kcalController = TextEditingController();
  final _carbsController = TextEditingController();
  final _sugarsController = TextEditingController();
  final _proteinController = TextEditingController();
  final _fatController = TextEditingController();
  final _fiberController = TextEditingController();
  final _saltController = TextEditingController();

  CapturedImage? _photo;
  LabelExtraction? _extraction;
  AppFailure? _failure;
  bool _busy = false;
  bool _analyzed = false;

  @override
  void dispose() {
    for (final controller in [
      _nameController,
      _kcalController,
      _carbsController,
      _sugarsController,
      _proteinController,
      _fatController,
      _fiberController,
      _saltController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _capture({required bool fromCamera}) async {
    setState(() {
      _busy = true;
      _failure = null;
    });

    try {
      final service = ref.read(imageServiceProvider);
      final photo = fromCamera
          ? await service.pickFromCamera()
          : await service.pickFromGallery();
      if (!mounted) return;
      if (photo == null) {
        setState(() => _busy = false);
        return;
      }
      setState(() {
        _photo = photo;
        _busy = false;
        _analyzed = false;
      });
      await _analyze();
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = AppFailure.from(error);
        _busy = false;
      });
    }
  }

  Future<void> _analyze() async {
    final photo = _photo;
    if (photo == null) return;

    setState(() {
      _busy = true;
      _failure = null;
    });

    try {
      final vision = await ref.read(visionProviderProvider.future);
      final extraction = await vision.analyzeLabel(
        LabelAnalysisRequest(image: photo.bytes, mimeType: photo.mimeType),
      );
      if (!mounted) return;

      _applyExtraction(extraction);
      setState(() {
        _extraction = extraction;
        _analyzed = true;
        _busy = false;
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = AppFailure.from(error);
        _busy = false;
      });
    }
  }

  void _applyExtraction(LabelExtraction extraction) {
    final values = extraction.per100g;

    String text(double value) => value == 0 ? '' : Format.number(value);

    _nameController.text = extraction.suggestedName;
    _kcalController.text = text(values.kcal);
    _carbsController.text = text(values.carbs);
    _sugarsController.text = text(values.sugars);
    _proteinController.text = text(values.protein);
    _fatController.text = text(values.fat);
    _fiberController.text = text(values.fiber);
    _saltController.text = text(values.salt);
  }

  double _read(TextEditingController controller) {
    final parsed = double.tryParse(controller.text.replaceAll(',', '.'));
    return parsed == null || parsed < 0 ? 0 : parsed;
  }

  Future<void> _addToMeal() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final food = Food(
      name: name,
      per100g: NutritionValues(
        kcal: _read(_kcalController),
        carbs: _read(_carbsController),
        sugars: _read(_sugarsController),
        protein: _read(_proteinController),
        fat: _read(_fatController),
        fiber: _read(_fiberController),
        salt: _read(_saltController),
        saturatedFat: _extraction?.saturatedFat ?? 0,
      ),
      source: _analyzed ? FoodSource.label : FoodSource.manual,
      brand: _extraction?.brand,
    );

    if (!mounted) return;
    final grams = await showQuantityDialog(context, initial: 100);
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
              source: MealSource.label,
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
      appBar: AppBar(title: const Text('Lire une etiquette')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xxl,
            ),
            children: [
              const EstimateBanner(
                message:
                    'Visez le tableau nutritionnel du produit, en entier et bien eclaire. '
                    'Verifiez chaque valeur : une lecture peut se tromper.',
              ),

              const SizedBox(height: AppSpacing.lg),

              if (_photo == null)
                Column(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _capture(fromCamera: true),
                      icon: const Icon(Icons.photo_camera_rounded, size: 20),
                      label: const Text(
                        'Photographier le tableau nutritionnel',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _capture(fromCamera: false),
                      icon: const Icon(Icons.photo_library_rounded, size: 20),
                      label: const Text('Choisir dans la galerie'),
                    ),
                  ],
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  child: Stack(
                    children: [
                      Image.memory(
                        _photo!.bytes,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                      if (_busy)
                        Positioned.fill(
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.45),
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                  SizedBox(height: AppSpacing.md),
                                  Text(
                                    'Lecture de l\'etiquette…',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

              if (_busy && _photo != null) ...[
                const SizedBox(height: AppSpacing.md),
                const LinearProgressIndicator(),
              ],

              if (_failure != null) ...[
                const SizedBox(height: AppSpacing.md),
                EstimateBanner(
                  message: _failure!.hint == null
                      ? _failure!.message
                      : '${_failure!.message}. ${_failure!.hint}',
                  severity: EstimateSeverity.danger,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_failure!.isRetryable)
                  OutlinedButton.icon(
                    onPressed: _analyze,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Reessayer la lecture'),
                  ),
              ],

              const SizedBox(height: AppSpacing.lg),

              SectionCard(
                title: 'Valeurs pour 100 g',
                subtitle: _extraction?.basis == '100ml'
                    ? 'Etiquette exprimee pour 100 ml'
                    : null,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nom du produit',
                        hintText: 'Cereales au chocolat',
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: AppSpacing.md),

                    _NumericField(
                      controller: _carbsController,
                      label: 'Glucides',
                      unit: 'g',
                      highlighted: true,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _NumericField(
                      controller: _kcalController,
                      label: 'Energie',
                      unit: 'kcal',
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _NumericField(
                      controller: _sugarsController,
                      label: 'dont sucres',
                      unit: 'g',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _NumericField(
                      controller: _proteinController,
                      label: 'Proteines',
                      unit: 'g',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _NumericField(
                      controller: _fatController,
                      label: 'Lipides',
                      unit: 'g',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _NumericField(
                      controller: _fiberController,
                      label: 'Fibres',
                      unit: 'g',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _NumericField(
                      controller: _saltController,
                      label: 'Sel',
                      unit: 'g',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              if (_analyzed && _extraction != null)
                EstimateBanner(
                  message: _extraction!.confidence >= 0.6
                      ? 'Lecture automatique (confiance ${Format.confidence(_extraction!.confidence)}). '
                            'Verifiez avant d\'ajouter.'
                      : 'Lecture peu fiable (confiance ${Format.confidence(_extraction!.confidence)}). '
                            'Corrigez les valeurs ci-dessus.',
                  severity: _extraction!.confidence >= 0.6
                      ? EstimateSeverity.info
                      : EstimateSeverity.warning,
                ),

              const SizedBox(height: AppSpacing.lg),

              FilledButton.icon(
                onPressed: _busy ? null : _addToMeal,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Ajouter au repas'),
              ),

              const SizedBox(height: AppSpacing.sm),

              if (_photo != null)
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() {
                            _photo = null;
                            _extraction = null;
                            _analyzed = false;
                            _failure = null;
                          });
                        },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Reprendre la photo'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumericField extends StatelessWidget {
  const _NumericField({
    required this.controller,
    required this.label,
    required this.unit,
    this.highlighted = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String unit;
  final bool highlighted;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      onChanged: (_) => onChanged?.call(),
      style: TextStyle(
        fontSize: highlighted ? 18 : 15,
        fontWeight: highlighted ? FontWeight.w800 : FontWeight.w500,
        color: highlighted ? palette.carb : null,
      ),
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit,
        labelStyle: highlighted
            ? TextStyle(color: palette.carb, fontWeight: FontWeight.w700)
            : null,
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return null;
        final parsed = double.tryParse(value.replaceAll(',', '.'));
        if (parsed == null) return 'Valeur non reconnue';
        if (parsed < 0 || parsed > 100000) return 'Valeur hors limites';
        return null;
      },
    );
  }
}
