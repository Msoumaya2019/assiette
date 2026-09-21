import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/meal.dart';
import '../../models/nutrition_values.dart';

/// Ligne d'un repas dans une liste.
///
/// Les glucides sont mis en avant a droite, avec la meme couleur que le bloc
/// principal : c'est l'information que l'oeil doit trouver en premier.
class MealTile extends StatelessWidget {
  const MealTile({
    super.key,
    required this.meal,
    this.onTap,
    this.trailing,
    this.showDate = false,
  });

  final Meal meal;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Affiche la date en plus de l'heure.
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final totals = meal.totals;
    final palette = context.palette;

    final subtitleParts = <String>[
      if (showDate) Format.dayMonth(meal.eatenAt),
      Format.time(meal.eatenAt),
      '${meal.items.length} aliment${meal.items.length > 1 ? 's' : ''}',
      Format.kcal(totals.kcal),
    ];

    return Semantics(
      button: onTap != null,
      label:
          '${meal.name}, ${Format.carbs(totals.carbs)} grammes de glucides, '
          '${Format.time(meal.eatenAt)}',
      child: Material(
        color: context.colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                _LeadingIcon(meal: meal),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        meal.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitleParts.join(' · '),
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.mutedText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _CarbBadge(carbs: totals.carbs, isEstimate: meal.isEstimate),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({required this.meal});

  final Meal meal;

  @override
  Widget build(BuildContext context) {
    final icon = switch (meal.source) {
      MealSource.photo => Icons.photo_camera_rounded,
      MealSource.barcode => Icons.qr_code_rounded,
      MealSource.search => Icons.search_rounded,
      MealSource.label => Icons.document_scanner_rounded,
      MealSource.template => Icons.bookmark_rounded,
      MealSource.manual => Icons.edit_rounded,
    };

    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.palette.cardBorder),
      ),
      child: Icon(icon, size: 18, color: context.palette.mutedText),
    );
  }
}

/// Pastille des glucides d'un repas.
class _CarbBadge extends StatelessWidget {
  const _CarbBadge({required this.carbs, required this.isEstimate});

  final double carbs;
  final bool isEstimate;

  @override
  Widget build(BuildContext context) {
    final carb = context.palette.carb;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: carb.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: carb.withValues(alpha: 0.28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (isEstimate)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Text('≈', style: TextStyle(fontSize: 12, color: carb)),
                ),
              Text(
                Format.carbs(carbs),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: carb,
                  height: 1,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                'g',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: carb,
                ),
              ),
            ],
          ),
          Text(
            'glucides',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: carb.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

/// Detail d'un aliment dans un repas, avec sa quantite et ses glucides.
class MealItemRow extends StatelessWidget {
  const MealItemRow({
    super.key,
    required this.name,
    required this.quantityG,
    required this.totals,
    this.portionLabel,
    this.sourceLabel,
    this.confidence,
    this.onTap,
    this.trailing,
  });

  final String name;
  final double quantityG;

  /// « 2 gateaux (130 g) », quand une portion est definie.
  ///
  /// Remplace alors l'affichage en grammes : les deux cote a cote diraient la
  /// meme chose deux fois, et l'utilisateur qui compte en gateaux n'a pas
  /// besoin de relire les grammes a chaque ligne.
  final String? portionLabel;

  final NutritionValues totals;
  final String? sourceLabel;
  final double? confidence;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        portionLabel ?? Format.grams(quantityG),
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.mutedText,
                        ),
                      ),
                      if (sourceLabel != null) ...[
                        Text(
                          ' · ',
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.mutedText,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            sourceLabel!,
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.mutedText,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      Format.carbs(totals.carbs),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: palette.carb,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      'g gluc.',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: palette.carb,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  Format.kcal(totals.kcal),
                  style: TextStyle(fontSize: 11, color: palette.mutedText),
                ),
              ],
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.xs),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
