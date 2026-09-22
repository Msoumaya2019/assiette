import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/apercu_aliment.dart';
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
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.palette.mutedText,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) _LargeurBornee(child: trailing!),
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

/// Rend aux boutons pleins une largeur minimale finie, le temps d'un
/// emplacement situe dans un `Row`.
///
/// Le theme demande aux boutons pleins `minimumSize: Size.fromHeight(54)`, ce
/// qui veut dire « au moins toute la largeur » — le bon defaut pour une action
/// de page. Mais un `Row` presente a ses enfants **non flexibles** une largeur
/// **non bornee**, pour qu'ils puissent se dimensionner sur leur contenu : la
/// demande « toute la largeur » n'y a alors aucun sens, et Flutter leve
/// `BoxConstraints forces an infinite width`.
///
/// Le `trailing` de [SectionCard] est exactement un emplacement de ce genre.
/// Sans cette borne, un bouton plein y fait tomber l'ecran au premier rendu —
/// mesure faite, et non suppose : une carte avec un bouton en `trailing`, dans
/// une simple `ListView`, suffit a reproduire l'assertion.
///
/// Seules les largeurs **infinies** sont corrigees : un bouton dont la largeur
/// minimale est deja finie, ou un widget qui n'est pas un bouton, traversent
/// cet emplacement sans etre touches. La hauteur minimale du theme est
/// conservee, pour que la cible tactile ne retrecisse pas.
class _LargeurBornee extends StatelessWidget {
  const _LargeurBornee({required this.child});

  final Widget child;

  /// Une largeur minimale infinie devient « 0 », la hauteur est gardee.
  ButtonStyle? _borner(ButtonStyle? style) {
    final minimum = style?.minimumSize?.resolve(const <WidgetState>{});
    if (minimum == null || minimum.width.isFinite) return style;
    return style!.copyWith(
      minimumSize: WidgetStatePropertyAll(Size(0, minimum.height)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Theme(
      data: theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: _borner(theme.filledButtonTheme.style),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: _borner(theme.outlinedButtonTheme.style),
        ),
      ),
      child: child,
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
      EstimateSeverity.warning => (
        AppColors.warning,
        Icons.warning_amber_rounded,
      ),
      EstimateSeverity.danger => (
        AppColors.danger,
        Icons.error_outline_rounded,
      ),
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
    final ratio = target != null && target! > 0
        ? (value / target!).clamp(0.0, 1.0)
        : null;

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
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
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
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: tiles
              .map((tile) => SizedBox(width: itemWidth, child: tile))
              .toList(),
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
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: context.palette.mutedText,
                ),
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
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
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
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La ligne comparable d'un apercu, ou `null` quand il n'y a rien a comparer.
///
/// Une **liste** sert a comparer, et deux produits dont l'un est chiffre pour
/// un pot et l'autre pour 100 g ne se comparent pas sans un calcul mental. Cette
/// ligne rend le chiffre comparable lisible, sans retirer la portion mise en
/// avant : elle vient **a cote**, jamais a la place.
///
/// Le nombre et son etiquette sont produits **ici, ensemble**, et c'est tout
/// l'objet de cette fonction : un ecran qui ecrirait `apercu.reference` a cote
/// du chiffre des 100 g reproduirait exactement le defaut que
/// [apercuDePortion] existe pour empecher — « 12 g de glucides pour 1 pot
/// (125 g) », ou 12 est la valeur des 100 g.
///
/// Un seul endroit, donc : les deux listes de l'application l'appellent, et
/// aucune ne peut se tromper d'etiquette toute seule.
String? ligneComparable(Apercu apercu) {
  final comparable = apercu.comparable;
  if (comparable == null) {
    return null;
  }
  return 'soit ${Format.number(comparable.carbs)} g de glucides $reference100g';
}

/// Les valeurs d'un aliment, l'unite sur laquelle elles portent, et le chiffre
/// comparable quand il y en a un.
///
/// Ce bloc est celui qui a menti : il annoncait « 12 g de glucides pour 1 pot
/// (125 g) », ou 12 est la valeur des 100 g. Il recoit donc un apercu **entier**
/// — valeurs, reference et comparable — et n'en compose rien lui-meme : il ne
/// peut pas accoler une unite a un chiffre qui ne vient pas d'elle.
///
/// Il ne lit aucun fournisseur, et c'est deliberé : un widget qui va chercher sa
/// portion lui-meme ne se teste qu'en montant tout l'ecran, et c'est ainsi que le
/// defaut a survecu. Ici, on lui donne un apercu et on regarde ce qu'il ecrit.
class ApercuValeurs extends StatelessWidget {
  const ApercuValeurs({super.key, required this.apercu});

  final Apercu apercu;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final ligne = ligneComparable(apercu);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
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
        if (ligne != null)
          Text(ligne, style: TextStyle(fontSize: 11, color: palette.mutedText)),
      ],
    );
  }
}

/// Un chiffre et son libelle, sur une ligne.
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
