import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/goals.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

/// Definition des objectifs quotidiens.
///
/// L'application ne propose aucune valeur par defaut et ne suggere aucun
/// chiffre : un objectif nutritionnel depend d'une situation personnelle et
/// parfois d'un suivi medical. Chaque champ peut rester vide.
class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  late final TextEditingController _carbs;
  late final TextEditingController _kcal;
  late final TextEditingController _protein;
  late final TextEditingController _fat;
  late final TextEditingController _fiber;

  @override
  void initState() {
    super.initState();
    final goals = ref.read(settingsProvider).goals;
    _carbs = _controllerFor(goals.carbsG);
    _kcal = _controllerFor(goals.kcal);
    _protein = _controllerFor(goals.proteinG);
    _fat = _controllerFor(goals.fatG);
    _fiber = _controllerFor(goals.fiberG);
  }

  TextEditingController _controllerFor(double? value) {
    if (value == null) return TextEditingController();
    return TextEditingController(
      text: value == value.roundToDouble()
          ? value.round().toString()
          : value.toString(),
    );
  }

  @override
  void dispose() {
    for (final controller in [_carbs, _kcal, _protein, _fat, _fiber]) {
      controller.dispose();
    }
    super.dispose();
  }

  double? _read(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text.replaceAll(',', '.'));
    if (parsed == null || parsed <= 0 || parsed > 100000) return null;
    return parsed;
  }

  Future<void> _save() async {
    final goals = DailyGoals(
      carbsG: _read(_carbs),
      kcal: _read(_kcal),
      proteinG: _read(_protein),
      fatG: _read(_fat),
      fiberG: _read(_fiber),
    );

    await ref.read(settingsProvider.notifier).updateGoals(goals);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          goals.isEmpty ? 'Objectifs effaces.' : 'Objectifs enregistres.',
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Objectifs quotidiens')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xxl,
          ),
          children: [
            SectionCard(
              title: 'Vos objectifs',
              subtitle: 'Laissez vide ce que vous ne souhaitez pas suivre',
              child: Column(
                children: [
                  _GoalField(
                    controller: _carbs,
                    label: 'Glucides par jour',
                    unit: 'g',
                    highlighted: true,
                    helper: 'L\'information principale de l\'application',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _GoalField(
                    controller: _kcal,
                    label: 'Calories par jour',
                    unit: 'kcal',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _GoalField(
                    controller: _protein,
                    label: 'Proteines par jour',
                    unit: 'g',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _GoalField(
                    controller: _fat,
                    label: 'Lipides par jour',
                    unit: 'g',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _GoalField(
                    controller: _fiber,
                    label: 'Fibres par jour',
                    unit: 'g',
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            const EstimateBanner(
              message:
                  'Ces objectifs sont ceux que vous definissez. L\'application ne les '
                  'propose pas et ne les interprete pas : elle affiche seulement votre '
                  'progression. Pour determiner un objectif adapte a votre situation, '
                  'adressez-vous a un professionnel de sante.',
            ),

            const SizedBox(height: AppSpacing.lg),

            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Enregistrer'),
            ),

            const SizedBox(height: AppSpacing.sm),

            OutlinedButton(
              onPressed: () {
                for (final controller in [
                  _carbs,
                  _kcal,
                  _protein,
                  _fat,
                  _fiber,
                ]) {
                  controller.clear();
                }
              },
              child: const Text('Tout effacer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalField extends StatelessWidget {
  const _GoalField({
    required this.controller,
    required this.label,
    required this.unit,
    this.helper,
    this.highlighted = false,
  });

  final TextEditingController controller;
  final String label;
  final String unit;
  final String? helper;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      style: TextStyle(
        fontSize: highlighted ? 18 : 15,
        fontWeight: highlighted ? FontWeight.w800 : FontWeight.w500,
        color: highlighted ? palette.carb : null,
      ),
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit,
        helperText: helper,
        labelStyle: highlighted
            ? TextStyle(color: palette.carb, fontWeight: FontWeight.w700)
            : null,
      ),
    );
  }
}
