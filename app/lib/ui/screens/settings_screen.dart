import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../models/app_settings.dart';
import '../../state/providers.dart';
import '../router.dart';
import '../widgets/common.dart';

/// Reglages de l'application.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Reglages')),
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
              title: 'Analyse des repas',
              subtitle: 'Comment les photos sont analysees',
              child: Column(
                children: [
                  // La selection se declare desormais sur un RadioGroup ancetre :
                  // `groupValue` et `onChanged` sont deposes sur RadioListTile
                  // depuis Flutter 3.32.
                  RadioGroup<AnalysisModeSetting>(
                    groupValue: settings.analysisMode,
                    onChanged: (value) {
                      if (value != null) notifier.setAnalysisMode(value);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final mode in AnalysisModeSetting.values)
                          RadioListTile<AnalysisModeSetting>(
                            value: mode,
                            title: Text(
                              mode.label,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(mode.description, style: const TextStyle(fontSize: 12)),
                            contentPadding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                  ),

                  if (settings.analysisMode == AnalysisModeSetting.personal) ...[
                    const Divider(height: AppSpacing.lg),
                    _ApiKeyTile(
                      hasKey: settings.hasProviderKey,
                      onSave: notifier.saveProviderKey,
                      onClear: notifier.clearProviderKey,
                    ),
                  ],

                  if (settings.analysisMode == AnalysisModeSetting.proxy) ...[
                    const Divider(height: AppSpacing.lg),
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        AppConfig.analysisEndpoint.isEmpty
                            ? 'Aucun service n\'est configure dans cette compilation. '
                                'Utilisez une cle personnelle, ou compilez avec ANALYSIS_ENDPOINT.'
                            : 'Service configure : ${AppConfig.analysisEndpoint}',
                        style: TextStyle(fontSize: 12, color: context.palette.mutedText),
                      ),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.md),

                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerHighest.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 18, color: context.palette.mutedText),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Votre cle est conservee dans le trousseau securise du telephone, '
                            'jamais dans l\'application elle-meme.',
                            style: TextStyle(fontSize: 12, height: 1.4, color: context.palette.mutedText),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            SectionCard(
              title: 'Objectifs quotidiens',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.flag_rounded, size: 20),
                title: const Text('Definir mes objectifs'),
                subtitle: Text(
                  settings.goals.isEmpty
                      ? 'Aucun objectif defini'
                      : 'Glucides ${settings.goals.carbsG ?? '—'} g · '
                          '${settings.goals.kcal ?? '—'} kcal',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(Routes.goals),
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            SectionCard(
              title: 'Apparence',
              child: RadioGroup<ThemeMode>(
                groupValue: settings.themeMode,
                onChanged: (value) {
                  if (value != null) notifier.setThemeMode(value);
                },
                child: Column(
                  children: [
                    for (final (mode, label, icon) in const [
                      (ThemeMode.system, 'Suivre le systeme', Icons.brightness_auto_rounded),
                      (ThemeMode.light, 'Clair', Icons.light_mode_rounded),
                      (ThemeMode.dark, 'Sombre', Icons.dark_mode_rounded),
                    ])
                      RadioListTile<ThemeMode>(
                        value: mode,
                        title: Row(
                          children: [
                            Icon(icon, size: 18),
                            const SizedBox(width: AppSpacing.sm),
                            Text(label),
                          ],
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            SectionCard(
              title: 'Notifications',
              child: Column(
                children: [
                  SwitchListTile(
                    value: settings.mealRemindersEnabled,
                    onChanged: notifier.setMealReminders,
                    title: const Text('Rappel pour renseigner un repas'),
                    subtitle: const Text('Une notification discrete, desactivable a tout moment'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    value: settings.dailySummaryEnabled,
                    onChanged: notifier.setDailySummary,
                    title: const Text('Resume de la journee'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (settings.mealRemindersEnabled || settings.dailySummaryEnabled)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule_rounded, size: 20),
                      title: const Text('Heure du rappel'),
                      subtitle: Text(
                        '${settings.reminderHour.toString().padLeft(2, '0')}:'
                        '${settings.reminderMinute.toString().padLeft(2, '0')}',
                      ),
                      trailing: const Icon(Icons.edit_rounded, size: 18),
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(
                            hour: settings.reminderHour,
                            minute: settings.reminderMinute,
                          ),
                        );
                        if (time != null) notifier.setReminderTime(time.hour, time.minute);
                      },
                    ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            SectionCard(
              title: 'Donnees',
              child: Column(
                children: [
                  SwitchListTile(
                    value: settings.keepPhotos,
                    onChanged: notifier.setKeepPhotos,
                    title: const Text('Conserver la photo du repas'),
                    subtitle: const Text(
                      'Desactive, aucune photo n\'est gardee sur le telephone apres l\'analyse.',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const Divider(height: AppSpacing.lg),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_forever_rounded, size: 20, color: AppColors.danger),
                    title: const Text(
                      'Effacer toutes mes donnees',
                      style: TextStyle(color: AppColors.danger),
                    ),
                    subtitle: const Text(
                      'Repas, favoris, repas types, objectifs et cle enregistree',
                      style: TextStyle(fontSize: 12),
                    ),
                    onTap: () => _confirmErase(context, ref),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            SectionCard(
              title: 'A propos',
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.privacy_tip_outlined, size: 20),
                    title: const Text('Politique de confidentialite'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push(Routes.privacy),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.help_outline_rounded, size: 20),
                    title: const Text('Comment ca marche'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push(Routes.onboarding),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.source_rounded, size: 20),
                    title: const Text('Sources des donnees'),
                    subtitle: const Text(
                      'Ciqual 2020 (ANSES, Licence Ouverte 2.0)\n'
                      'Open Food Facts (ODbL)\n'
                      'Analyse d\'image : DeepSeek (deepseek-flash)',
                      style: TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.info_outline_rounded, size: 20),
                    title: const Text('Version'),
                    subtitle: Text(
                      '${AppConfig.appName} 0.1.0 — compilation ${AppConfig.buildChannel}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            const EstimateBanner(
              message: 'Assiette n\'est pas un dispositif medical. L\'application ne fournit '
                  'aucun diagnostic, aucune recommandation therapeutique et aucune posologie.',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmErase(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Effacer toutes les donnees ?'),
        content: const Text(
          'Vos repas, favoris, repas types, objectifs et votre cle d\'analyse seront '
          'supprimes de cet appareil. Cette action est definitive et ne peut pas etre annulee.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Tout effacer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(settingsProvider.notifier).eraseEverything();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Toutes les donnees locales ont ete effacees.')),
    );
  }
}

/// Saisie de la cle d'analyse personnelle.
class _ApiKeyTile extends StatefulWidget {
  const _ApiKeyTile({required this.hasKey, required this.onSave, required this.onClear});

  final bool hasKey;
  final Future<void> Function(String) onSave;
  final Future<void> Function() onClear;

  @override
  State<_ApiKeyTile> createState() => _ApiKeyTileState();
}

class _ApiKeyTileState extends State<_ApiKeyTile> {
  final TextEditingController _controller = TextEditingController();
  bool _visible = false;
  bool _busy = false;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _controller.text.trim();
    if (key.length < 12) {
      setState(() {
        _message = 'Cette cle semble trop courte.';
        _isError = true;
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    await widget.onSave(key);

    if (!mounted) return;
    setState(() {
      _busy = false;
      _isError = false;
      _message = 'Cle enregistree dans le trousseau du telephone.';
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.hasKey) ...[
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text(
                  'Une cle est enregistree.',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await widget.onClear();
                        if (!mounted) return;
                        setState(() {
                          _isError = false;
                          _message = 'Cle supprimee.';
                        });
                      },
                child: const Text('Supprimer'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],

        TextField(
          controller: _controller,
          obscureText: !_visible,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Cle d\'acces DeepSeek',
            hintText: 'sk-…',
            helperText: 'Creez une cle sur platform.deepseek.com',
            suffixIcon: IconButton(
              onPressed: () => setState(() => _visible = !_visible),
              icon: Icon(_visible ? Icons.visibility_off_rounded : Icons.visibility_rounded),
              tooltip: _visible ? 'Masquer' : 'Afficher',
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.sm),

        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_rounded, size: 18),
          label: const Text('Enregistrer la cle'),
        ),

        if (_message != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _message!,
            style: TextStyle(
              fontSize: 12,
              color: _isError ? AppColors.danger : AppColors.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}
