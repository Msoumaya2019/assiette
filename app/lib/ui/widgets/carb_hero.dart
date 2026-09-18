import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';

/// Affichage principal des glucides.
///
/// C'est l'element le plus visible de l'application : un chiffre tres grand,
/// sur une carte coloree, avec une fourchette d'incertitude lorsque la quantite
/// provient d'une estimation. Aucun autre bloc de l'interface n'utilise cette
/// couleur, pour que l'oeil identifie les glucides sans lire le libelle.
class CarbHero extends StatelessWidget {
  const CarbHero({
    super.key,
    required this.carbs,
    this.rangeLow,
    this.rangeHigh,
    this.isEstimate = true,
    this.goalG,
    this.title = 'Glucides estimes',
    this.compact = false,
  });

  /// Quantite de glucides en grammes.
  final double carbs;

  /// Borne basse de la fourchette estimee, si connue.
  final double? rangeLow;

  /// Borne haute de la fourchette estimee, si connue.
  final double? rangeHigh;

  /// Vrai lorsque la quantite est une estimation visuelle.
  final bool isEstimate;

  /// Objectif quotidien, si defini par l'utilisateur.
  final double? goalG;

  final String title;

  /// Version reduite, utilisee dans les listes.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final carb = palette.carb;
    final hasRange = rangeLow != null && rangeHigh != null && rangeHigh! > rangeLow!;
    final ratio = goalG != null && goalG! > 0 ? (carbs / goalG!).clamp(0.0, 1.0) : null;

    return Semantics(
      label: '$title : ${Format.carbs(carbs)} grammes'
          '${hasRange ? ', fourchette ${Format.range(rangeLow!, rangeHigh!)}' : ''}'
          '${isEstimate ? ', estimation' : ''}',
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              carb.withValues(alpha: 0.18),
              carb.withValues(alpha: 0.07),
            ],
          ),
          border: Border.all(color: carb.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.grain_rounded, size: compact ? 16 : 20, color: carb),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      fontSize: compact ? 11 : 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: carb,
                    ),
                  ),
                ),
                if (isEstimate)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: carb.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '≈ estimation',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: carb),
                    ),
                  ),
              ],
            ),
            SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  Format.carbs(carbs),
                  style: TextStyle(
                    fontSize: compact ? 40 : 68,
                    fontWeight: FontWeight.w800,
                    height: 0.95,
                    letterSpacing: -2,
                    color: context.colors.onSurface,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: EdgeInsets.only(bottom: compact ? 4 : 8),
                  child: Text(
                    'g',
                    style: TextStyle(
                      fontSize: compact ? 20 : 30,
                      fontWeight: FontWeight.w700,
                      color: palette.mutedText,
                    ),
                  ),
                ),
              ],
            ),
            if (hasRange) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Fourchette estimee : ${Format.range(rangeLow!, rangeHigh!)}',
                style: TextStyle(
                  fontSize: compact ? 12 : 14,
                  fontWeight: FontWeight.w600,
                  color: palette.mutedText,
                ),
              ),
            ],
            if (ratio != null) ...[
              SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 8,
                  backgroundColor: carb.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(carb),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${Format.percent(ratio)} de l\'objectif de ${Format.grams(goalG!)}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.mutedText),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
