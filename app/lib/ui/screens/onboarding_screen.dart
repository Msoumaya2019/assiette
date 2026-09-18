import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../models/app_settings.dart';
import '../../state/providers.dart';
import '../router.dart';
import '../widgets/common.dart';

/// Assistant de premiere utilisation.
///
/// Quatre etapes courtes : comprendre ce que fait l'application, accepter la
/// politique de confidentialite, configurer l'analyse, puis definir un objectif
/// facultatif.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();
  final TextEditingController _keyController = TextEditingController();

  int _step = 0;
  bool _privacyAccepted = false;
  bool _keySaved = false;
  bool _busy = false;
  String? _keyError;

  static const int _steps = 4;

  @override
  void dispose() {
    _controller.dispose();
    _keyController.dispose();
    super.dispose();
  }

  void _next() {
    if (_step < _steps - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _back() {
    if (_step > 0) {
      _controller.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    final notifier = ref.read(settingsProvider.notifier);
    await notifier.acceptPrivacyPolicy(PrivacyPolicy.version);
    await notifier.markDisclaimerSeen();
    await notifier.completeOnboarding();
    if (!mounted) return;
    context.go(Routes.home);
  }

  Future<void> _saveKey() async {
    final key = _keyController.text.trim();
    if (key.length < 12) {
      setState(() => _keyError = 'Cette cle semble trop courte.');
      return;
    }

    setState(() {
      _busy = true;
      _keyError = null;
    });

    await ref.read(settingsProvider.notifier).saveProviderKey(key);

    if (!mounted) return;
    setState(() {
      _busy = false;
      _keySaved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _step == _steps - 1;

    return Scaffold(
      appBar: AppBar(
        title: Text('Etape ${_step + 1} sur $_steps'),
        leading: _step == 0
            ? IconButton(
                onPressed: () => context.go(Routes.home),
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Plus tard',
              )
            : IconButton(
                onPressed: _back,
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Retour',
              ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_step + 1) / _steps,
            minHeight: 4,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) => setState(() => _step = index),
                children: [
                  _WelcomeStep(),
                  _PrivacyStep(
                    accepted: _privacyAccepted,
                    onChanged: (value) =>
                        setState(() => _privacyAccepted = value),
                  ),
                  _AnalysisStep(
                    controller: _keyController,
                    saved: _keySaved,
                    busy: _busy,
                    error: _keyError,
                    onSave: _saveKey,
                    onUseDemo: () async {
                      await ref
                          .read(settingsProvider.notifier)
                          .setAnalysisMode(AnalysisModeSetting.demo);
                      if (!mounted) return;
                      setState(() => _keySaved = true);
                    },
                  ),
                  const _GoalsStep(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  FilledButton(
                    onPressed: isLast
                        ? (_busy ? null : _finish)
                        : (_step == 1 && !_privacyAccepted ? null : _next),
                    child: Text(isLast ? 'Commencer' : 'Continuer'),
                  ),
                  if (_step == 1 && !_privacyAccepted)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        'Cochez la case pour continuer.',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.palette.mutedText,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: context.palette.carb.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          child: Column(
            children: [
              Icon(
                Icons.restaurant_menu_rounded,
                size: 44,
                color: context.palette.carb,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                AppConfig.appName,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Estimez les glucides de vos repas en une photo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: context.palette.mutedText,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _StepBullet(
          icon: Icons.photo_camera_rounded,
          title: 'Photographiez',
          body:
              'Cadrez l\'assiette. Une seconde photo sous un autre angle ameliore '
              'l\'estimation du volume.',
        ),
        const _StepBullet(
          icon: Icons.grain_rounded,
          title: 'Les glucides d\'abord',
          body:
              'Le resultat met en avant les glucides, avec la fourchette d\'incertitude '
              'et le detail aliment par aliment.',
        ),
        const _StepBullet(
          icon: Icons.tune_rounded,
          title: 'Corrigez librement',
          body:
              'Changez un poids, remplacez un aliment, ajoutez ce qui manque. '
              'Le total se recalcule aussitot.',
        ),
        const _StepBullet(
          icon: Icons.dataset_rounded,
          title: 'Valeurs de reference',
          body:
              'Les valeurs viennent de la table Ciqual de l\'ANSES et d\'Open Food Facts. '
              'L\'analyse d\'image ne fait qu\'identifier les aliments et estimer les poids.',
        ),
      ],
    );
  }
}

class _PrivacyStep extends StatelessWidget {
  const _PrivacyStep({required this.accepted, required this.onChanged});

  final bool accepted;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const Text(
          'Vos donnees',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'L\'application fonctionne d\'abord sur votre telephone.',
          style: TextStyle(fontSize: 14, color: context.palette.mutedText),
        ),
        const SizedBox(height: AppSpacing.lg),

        for (final (title, body) in PrivacyPolicy.sections.take(5)) ...[
          _PrivacyPoint(title: title, body: body),
          const SizedBox(height: AppSpacing.md),
        ],

        const SizedBox(height: AppSpacing.sm),

        Card(
          child: CheckboxListTile(
            value: accepted,
            onChanged: (value) => onChanged(value ?? false),
            title: const Text(
              'J\'ai lu et j\'accepte la politique de confidentialite',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
      ],
    );
  }
}

class _PrivacyPoint extends StatelessWidget {
  const _PrivacyPoint({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Icon(
            Icons.check_circle_outline_rounded,
            size: 18,
            color: context.colors.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: context.palette.mutedText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnalysisStep extends StatelessWidget {
  const _AnalysisStep({
    required this.controller,
    required this.saved,
    required this.busy,
    required this.error,
    required this.onSave,
    required this.onUseDemo,
  });

  final TextEditingController controller;
  final bool saved;
  final bool busy;
  final String? error;
  final VoidCallback onSave;
  final VoidCallback onUseDemo;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const Text(
          'Analyse des photos',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Pour identifier les aliments sur une photo, l\'application utilise un modele '
          'multimodal. Vous pouvez fournir votre propre cle : elle sera conservee dans '
          'le trousseau securise du telephone.',
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: context.palette.mutedText,
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        if (saved)
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.success),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Analyse configuree. Vous pourrez la modifier a tout moment.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          )
        else ...[
          TextField(
            controller: controller,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Cle d\'acces DeepSeek',
              hintText: 'sk-…',
              helperText: 'Creez une cle sur platform.deepseek.com',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: busy ? null : onSave,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: const Text('Enregistrer la cle'),
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: busy ? null : onUseDemo,
            icon: const Icon(Icons.science_rounded, size: 18),
            label: const Text('Continuer en mode demonstration'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Le mode demonstration affiche des donnees de test : il sert a decouvrir '
            'l\'interface, pas a analyser de vraies photos.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: context.palette.mutedText,
            ),
          ),
        ],

        const SizedBox(height: AppSpacing.lg),

        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerHighest.withValues(
              alpha: 0.6,
            ),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: context.palette.mutedText,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Votre cle ne figure jamais dans l\'application. Elle est lue au moment '
                  'de l\'analyse depuis le trousseau du systeme.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: context.palette.mutedText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GoalsStep extends StatelessWidget {
  const _GoalsStep();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const Text(
          'Objectif de glucides',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Facultatif. Vous pourrez le definir plus tard, dans Reglages puis Objectifs.',
          style: TextStyle(fontSize: 14, color: context.palette.mutedText),
        ),
        const SizedBox(height: AppSpacing.lg),

        const EstimateBanner(
          message:
              'L\'application ne propose aucun objectif et ne suggere aucun chiffre : '
              'un objectif depend de votre situation. Si vous en avez besoin, '
              'demandez-le a un professionnel de sante.',
        ),

        const SizedBox(height: AppSpacing.lg),

        const _StepBullet(
          icon: Icons.insights_rounded,
          title: 'Suivi',
          body:
              'Une fois un objectif defini, chaque ecran affiche votre progression du jour.',
        ),
        const _StepBullet(
          icon: Icons.timer_outlined,
          title: 'Ensuite',
          body:
              'Vous pourrez ajouter un rappel pour ne pas oublier de renseigner un repas.',
        ),
      ],
    );
  }
}

class _StepBullet extends StatelessWidget {
  const _StepBullet({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: context.colors.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: context.palette.mutedText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
