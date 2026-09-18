import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/meal.dart';

/// Reglage de la quantite d'un aliment.
///
/// Trois moyens complementaires, du plus rapide au plus precis : les boutons
/// d'ajustement, le curseur, et la saisie directe du poids reel. Le resultat est
/// identique quel que soit le chemin — la quantite en grammes reste la seule
/// valeur stockee.
class QuantityEditor extends StatefulWidget {
  const QuantityEditor({
    super.key,
    required this.quantityG,
    required this.onChange,
    this.onReplace,
    this.onRemove,
    this.sourceLabel,
    this.isEstimate = false,
  });

  final double quantityG;
  final void Function(double) onChange;
  final VoidCallback? onReplace;
  final VoidCallback? onRemove;
  final String? sourceLabel;
  final bool isEstimate;

  @override
  State<QuantityEditor> createState() => _QuantityEditorState();
}

class _QuantityEditorState extends State<QuantityEditor> {
  late double _value;

  /// Bornes du curseur. Au-dela, la saisie directe prend le relais.
  static const double _min = 0;
  static const double _max = 800;

  @override
  void initState() {
    super.initState();
    _value = widget.quantityG.clamp(_min, _max);
  }

  @override
  void didUpdateWidget(QuantityEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quantityG != widget.quantityG) {
      _value = widget.quantityG.clamp(_min, _max);
    }
  }

  void _apply(double grams) {
    final clamped = grams.clamp(0.0, 5000.0);
    setState(() => _value = clamped.clamp(_min, _max));
    widget.onChange(clamped);
  }

  Future<void> _openNumericInput() async {
    final grams = await showQuantityDialog(context, initial: widget.quantityG);
    if (grams != null) _apply(grams);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Quantite',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: palette.mutedText,
                ),
              ),
              const Spacer(),
              if (widget.isEstimate)
                Text(
                  'estimee',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: palette.carb,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          Row(
            children: [
              _StepButton(
                icon: Icons.remove_rounded,
                onTap: () => _apply(widget.quantityG - 10),
                semanticLabel: 'Reduire de 10 grammes',
              ),
              Expanded(
                child: Center(
                  child: TextButton(
                    onPressed: _openNumericInput,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          Format.grams(widget.quantityG),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: null,
                          ),
                        ),
                        Text(
                          'Appuyez pour saisir le poids reel',
                          style: TextStyle(
                            fontSize: 10,
                            color: palette.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _StepButton(
                icon: Icons.add_rounded,
                onTap: () => _apply(widget.quantityG + 10),
                semanticLabel: 'Augmenter de 10 grammes',
              ),
            ],
          ),

          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            ),
            child: Slider(
              value: _value.clamp(_min, _max),
              min: _min,
              max: _max,
              divisions: 160,
              label: Format.grams(_value),
              onChanged: (value) => _apply(value),
            ),
          ),

          const SizedBox(height: AppSpacing.xs),

          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final portion in PortionSize.values)
                ActionChip(
                  label: Text(portion.label),
                  onPressed: () => _apply(widget.quantityG * portion.factor),
                ),
            ],
          ),

          if (widget.sourceLabel != null ||
              widget.onReplace != null ||
              widget.onRemove != null) ...[
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            Row(
              children: [
                if (widget.sourceLabel != null)
                  Expanded(
                    child: Text(
                      'Source : ${widget.sourceLabel}',
                      style: TextStyle(fontSize: 11, color: palette.mutedText),
                    ),
                  ),
                if (widget.onReplace != null)
                  TextButton.icon(
                    onPressed: widget.onReplace,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                    label: const Text('Remplacer'),
                  ),
                if (widget.onRemove != null)
                  TextButton.icon(
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('Retirer'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.danger,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onTap,
      icon: Icon(icon),
      tooltip: semanticLabel,
    );
  }
}

/// Boite de saisie du poids reel, en grammes.
///
/// Retourne `null` si l'utilisateur annule.
Future<double?> showQuantityDialog(
  BuildContext context, {
  required double initial,
}) {
  final controller = TextEditingController(
    text: initial == initial.roundToDouble()
        ? initial.round().toString()
        : initial.toStringAsFixed(1),
  );

  return showDialog<double>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Poids reel'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: const InputDecoration(suffixText: 'g', hintText: '180'),
            onSubmitted: (value) {
              final parsed = double.tryParse(value.replaceAll(',', '.'));
              if (parsed != null) Navigator.of(dialogContext).pop(parsed);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Utilisez cette option lorsque vous avez pese l\'aliment : la valeur '
            'remplace l\'estimation et le total est recalcule.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: context.palette.mutedText,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            final parsed = double.tryParse(
              controller.text.replaceAll(',', '.'),
            );
            Navigator.of(dialogContext).pop(parsed);
          },
          child: const Text('Valider'),
        ),
      ],
    ),
  );
}
