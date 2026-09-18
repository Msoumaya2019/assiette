import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/nutrition_values.dart';

/// Carte de section, avec titre optionnel et contenu.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding,
    this.onTap,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title!,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(fontSize: 13, color: context.palette.mutedText),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          child,
        ],
      ),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// Bandeau signalant qu'une valeur est une estimation.
///
/// Il est volontairement visible et non masquable : l'application ne doit
/// jamais laisser croire qu'une estimation visuelle est une mesure exacte.
class EstimateBanner extends StatelessWidget {
  const EstimateBanner({
    super.key,
    this.message =
        'Les quantites deduites d\'une photo sont des estimations. '
        'Verifiez-les lorsque la precision compte.',
    this.onDismiss,
    this.severity = EstimateSeverity.info,
  });

  final String message;
  final VoidCallback? onDismiss;
  final EstimateSeverity severity;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (color, icon) = switch (severity) {
      EstimateSeverity.info => (palette.carb, Icons.info_outline_rounded),
      EstimateSeverity.warning => (AppColors.warning, Icons.warning_amber_rounded),
      EstimateSeverity.danger => (AppColors.danger, Icons.error_outline_rounded),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: context.colors.onSurface,
              ),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 18),
              visualDensity: VisualDensity.compact,
              tooltip: 'Masquer',
            ),
        ],
      ),
    );
  }
}

enum EstimateSeverity { info, warning, danger }

/// Petite tuile affichant un nutriment secondaire.
class MacroTile extends StatelessWidget {
  const MacroTile({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.icon,
    this.target,
  });

  final String label;
  final double value;
  final String unit;
  final Color color;
  final IconData icon;

  /// Objectif quotidien, si defini.
  final double? target;

  @override
  Widget build(BuildContext context) {
    final ratio = target != null && target! > 0 ? (value / target!).clamp(0.0, 1.0) : null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: context.palette.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.palette.mutedText,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  Format.number(value),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.palette.mutedText,
                ),
              ),
            ],
          ),
          if (ratio != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 4,
                backgroundColor: color.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Grille des nutriments secondaires, sous le bloc des glucides.
class MacroGrid extends StatelessWidget {
  const MacroGrid({super.key, required this.totals, this.goal});

  final NutritionValues totals;

  /// Objectifs quotidiens, pour afficher la progression.
  final NutritionValues? goal;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final tiles = <Widget>[
      MacroTile(
        label: 'Calories',
        value: totals.kcal,
        unit: 'kcal',
        color: context.colors.primary,
        icon: Icons.local_fire_department_rounded,
        target: goal?.kcal,
      ),
      MacroTile(
        label: 'Proteines',
        value: totals.protein,
        unit: 'g',
        color: palette.protein,
        icon: Icons.fitness_center_rounded,
        target: goal?.protein,
      ),
      MacroTile(
        label: 'Lipides',
        value: totals.fat,
        unit: 'g',
        color: palette.fat,
        icon: Icons.water_drop_rounded,
        target: goal?.fat,
      ),
      MacroTile(
        label: 'Fibres',
        value: totals.fiber,
        unit: 'g',
        color: palette.fiber,
        icon: Icons.eco_rounded,
        target: goal?.fiber,
      ),
      MacroTile(
        label: 'Sucres',
        value: totals.sugars,
        unit: 'g',
        color: palette.carb,
        icon: Icons.cake_rounded,
      ),
      MacroTile(
        label: 'Sel',
        value: totals.salt,
        unit: 'g',
        color: palette.mutedText,
        icon: Icons.grain_rounded,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Deux colonnes sur telephone, trois au-dela : la largeur dicte la
        // grille plutot qu'une taille d'ecran supposee.
        final columns = constraints.maxWidth > 620 ? 3 : 2;
        const spacing = AppSpacing.sm;
        final itemWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: tiles.map((tile) => SizedBox(width: itemWidth, child: tile)).toList(),
        );
      },
    );
  }
}

/// Etat vide, avec message et action facultative.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: context.colors.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: context.palette.mutedText),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.45, color: context.palette.mutedText),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Etiquette de provenance d'une donnee, affichee sur chaque aliment.
class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

/// Indicateur de confiance, sous forme de pastille coloree.
class ConfidenceChip extends StatelessWidget {
  const ConfidenceChip({super.key, required this.confidence});

  /// Confiance entre 0 et 1.
  final double confidence;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (confidence) {
      >= 0.8 => (AppColors.success, 'Confiance elevee'),
      >= 0.65 => (AppColors.warning, 'Confiance moyenne'),
      _ => (AppColors.danger, 'Confiance faible'),
    };

    return Tooltip(
      message: '$label — ${Format.confidence(confidence)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 7, color: color),
            const SizedBox(width: 5),
            Text(
              Format.confidence(confidence),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
