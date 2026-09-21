import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/meal.dart';
import '../../models/portion.dart';

/// Reglage de la quantite d'un aliment.
///
/// Trois moyens complementaires, du plus rapide au plus precis : les boutons
/// d'ajustement, le curseur, et la saisie directe. Le resultat est identique
/// quel que soit le chemin — la quantite en grammes reste la seule valeur
/// stockee, et le nombre de portions n'en est qu'une lecture.
///
/// Quand une portion est definie (« 1 gateau = 65 g »), les boutons avancent
/// d'**une unite** au lieu de dix grammes, et le grand nombre affiche des
/// gateaux. C'est le sens de la fonctionnalite : l'utilisateur compte des
/// gateaux, pas des grammes.
class QuantityEditor extends StatefulWidget {
  const QuantityEditor({
    super.key,
    required this.quantityG,
    required this.onChange,
    this.portion,
    this.onPortionChange,
    this.onReplace,
    this.onRemove,
    this.sourceLabel,
    this.isEstimate = false,
  });

  final double quantityG;
  final void Function(double) onChange;

  /// Unite nommee par l'utilisateur, si elle est definie.
  final Portion? portion;

  /// Appele quand l'utilisateur definit, modifie ou retire la portion.
  /// Nul, la fonctionnalite est masquee.
  final void Function(Portion?)? onPortionChange;

  final VoidCallback? onReplace;
  final VoidCallback? onRemove;
  final String? sourceLabel;
  final bool isEstimate;

  @override
  State<QuantityEditor> createState() => _QuantityEditorState();
}

class _QuantityEditorState extends State<QuantityEditor> {
  /// Poids courant, en grammes. **Seule valeur qui fait foi.**
  ///
  /// Le curseur, lui, borne son affichage : il ne peut pas parcourir cinq
  /// kilos. Confondre les deux ferait retomber une quantite saisie a la main a
  /// 800 g des qu'on toucherait au curseur.
  late double _grams;

  /// Bornes du curseur. Au-dela, la saisie directe prend le relais.
  static const double _min = 0;
  static const double _max = 800;

  /// Plafond absolu, garde-fou contre une saisie absurde.
  static const double _plafond = 5000;

  @override
  void initState() {
    super.initState();
    _grams = widget.quantityG.clamp(_min, _plafond);
  }

  @override
  void didUpdateWidget(QuantityEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quantityG != widget.quantityG) {
      _grams = widget.quantityG.clamp(_min, _plafond);
    }
  }

  void _apply(double grams) {
    final clamped = grams.clamp(0.0, _plafond);
    setState(() => _grams = clamped);
    widget.onChange(clamped);
  }

  /// Avance d'une unite quand une portion existe, de dix grammes sinon.
  void _step(int sens) {
    final portion = widget.portion;
    if (portion == null) {
      _apply(_grams + 10 * sens);
      return;
    }
    // Le pas porte sur le nombre d'unites, pas sur les grammes : c'est ce que
    // l'utilisateur attend d'un bouton « + » a cote de « 2 gateaux ».
    final unites = portion.unitesPour(_grams) ?? 0;
    _apply(portion.grammesPour(unites + sens));
  }

  Future<void> _openNumericInput() async {
    final grams = await showQuantityDialog(
      context,
      initial: _grams,
      portion: widget.portion,
    );
    if (grams != null) _apply(grams);
  }

  Future<void> _definirPortion() async {
    final portion = await showPortionDialog(
      context,
      initial: widget.portion,
      // Une portion proposee par defaut doit coller a ce que l'utilisateur a
      // deja saisi : sinon definir une portion changerait la quantite sous ses
      // yeux, ce qui n'est jamais ce qu'il demande.
      poidsSuggere: _grams > 0 ? _grams : null,
    );
    if (portion == null) return;
    widget.onPortionChange?.call(portion);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final portion = widget.portion;

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
                onTap: () => _step(-1),
                semanticLabel: portion == null
                    ? 'Reduire de 10 grammes'
                    : 'Retirer une ${portion.nomSingulier}',
              ),
              Expanded(
                child: Center(
                  child: TextButton(
                    onPressed: _openNumericInput,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          // Sans portion, rien ne change : les grammes restent
                          // la lecture naturelle.
                          portion == null
                              ? Format.grams(_grams)
                              : portion.libelle(
                                  portion.unitesPour(_grams) ?? 0,
                                ),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          portion == null
                              ? 'Appuyez pour saisir le poids reel'
                              : '${Format.grams(_grams)} · appuyez pour corriger',
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
                onTap: () => _step(1),
                semanticLabel: portion == null
                    ? 'Augmenter de 10 grammes'
                    : 'Ajouter une ${portion.nomSingulier}',
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
              value: _grams.clamp(_min, _max),
              min: _min,
              max: _max,
              divisions: 160,
              label: Format.grams(_grams.clamp(_min, _max)),
              onChanged: (value) => _apply(value),
            ),
          ),

          const SizedBox(height: AppSpacing.xs),

          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Le raccourci le plus utile quand une portion est definie :
              // ramener la quantite a exactement une unite.
              if (portion != null)
                ActionChip(
                  avatar: const Icon(Icons.straighten_rounded, size: 16),
                  label: Text('1 ${portion.nomSingulier}'),
                  onPressed: () => _apply(portion.grams),
                ),
              for (final taille in PortionSize.values)
                ActionChip(
                  label: Text(taille.label),
                  onPressed: () => _apply(_grams * taille.factor),
                ),
            ],
          ),

          if (widget.onPortionChange != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                TextButton.icon(
                  onPressed: _definirPortion,
                  icon: Icon(
                    portion == null
                        ? Icons.add_circle_outline_rounded
                        : Icons.edit_outlined,
                    size: 16,
                  ),
                  label: Text(
                    portion == null
                        ? 'Definir une portion'
                        : '1 ${portion.nomSingulier} = '
                              '${Format.grams(portion.grams)}',
                  ),
                ),
                if (portion != null)
                  TextButton(
                    onPressed: () => widget.onPortionChange?.call(null),
                    child: const Text('Retirer la portion'),
                  ),
              ],
            ),
          ],

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

/// Saisie de la quantite : en grammes, ou en nombre de portions.
///
/// Quand une portion est definie, la question posee change : l'utilisateur qui
/// a declare « 1 gateau = 65 g » veut repondre « 2 », pas « 130 ». Les deux
/// chemins convergent vers un poids en grammes, qui reste la seule valeur
/// transmise.
///
/// Retourne `null` si l'utilisateur annule.
Future<double?> showQuantityDialog(
  BuildContext context, {
  required double initial,
  Portion? portion,
}) {
  final initialEnUnites = portion?.unitesPour(initial);

  final controller = TextEditingController(
    text: initialEnUnites != null ? _saisie(initialEnUnites) : _saisie(initial),
  );

  return showDialog<double>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        portion == null ? 'Poids reel' : 'Nombre de ${portion.nomPluriel}',
      ),
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
            decoration: InputDecoration(
              suffixText: portion == null ? 'g' : portion.nomPluriel,
              hintText: portion == null ? '180' : '2',
            ),
            onSubmitted: (value) =>
                Navigator.of(dialogContext).pop(_convertir(value, portion)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            portion == null
                ? 'Utilisez cette option lorsque vous avez pese l\'aliment : la '
                      'valeur remplace l\'estimation et le total est recalcule.'
                : '1 ${portion.nomSingulier} = '
                      '${Format.grams(portion.grams)}. La quantite sera '
                      'convertie en grammes pour le calcul.',
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
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(_convertir(controller.text, portion)),
          child: const Text('Valider'),
        ),
      ],
    ),
  );
}

/// Ecrit un nombre sans decimale inutile, virgule francaise comprise.
String _saisie(double valeur) {
  final arrondi = (valeur * 100).round() / 100;
  return arrondi == arrondi.roundToDouble()
      ? arrondi.round().toString()
      : arrondi.toStringAsFixed(2).replaceAll('.', ',');
}

/// Convertit une saisie en grammes, selon qu'elle porte sur des unites ou sur
/// un poids.
double? _convertir(String texte, Portion? portion) {
  final valeur = double.tryParse(texte.replaceAll(',', '.'));
  if (valeur == null || valeur < 0) return null;
  if (portion == null) return valeur;
  return portion.grammesPour(valeur);
}

/// Boite de definition d'une portion : un nom et un poids.
///
/// Le poids propose par defaut est la quantite deja saisie : l'utilisateur qui
/// a devant lui « 130 g » et qui declare « 1 gateau » obtient le plus souvent
/// une portion d'un gateau, pas de deux. Il reste libre de corriger.
///
/// Retourne `null` si l'utilisateur annule.
Future<Portion?> showPortionDialog(
  BuildContext context, {
  Portion? initial,
  double? poidsSuggere,
}) {
  final labelController = TextEditingController(text: initial?.label ?? '');
  final gramsController = TextEditingController(
    text: _saisie(initial?.grams ?? poidsSuggere ?? 100),
  );

  String? erreur;

  return showDialog<Portion>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        void valider() {
          final nom = labelController.text.trim();
          final grams = double.tryParse(
            gramsController.text.replaceAll(',', '.'),
          );

          if (nom.isEmpty) {
            setState(() => erreur = 'Donnez un nom a cette portion.');
            return;
          }
          if (grams == null || grams <= 0) {
            setState(
              () => erreur = 'Le poids d\'une portion doit etre positif.',
            );
            return;
          }
          Navigator.of(dialogContext).pop(Portion(label: nom, grams: grams));
        }

        return AlertDialog(
          title: const Text('Definir une portion'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: labelController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nom de l\'unite',
                  hintText: 'gateau, part, bol, tranche',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: gramsController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Poids d\'une unite',
                  suffixText: 'g',
                ),
                onSubmitted: (_) => valider(),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                erreur ??
                    'Les valeurs nutritionnelles restent enregistrees pour '
                        '100 g : cette portion ne sert qu\'a saisir et afficher '
                        'la quantite.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: erreur == null
                      ? context.palette.mutedText
                      : AppColors.danger,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(onPressed: valider, child: const Text('Valider')),
          ],
        );
      },
    ),
  );
}
