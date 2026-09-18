import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/failures.dart';
import '../../core/theme.dart';
import '../../data/vision/vision_provider.dart';
import '../../state/providers.dart';
import '../router.dart';

/// Ecran d'analyse.
///
/// L'utilisateur voit sa photo et un message d'avancement : jamais un ecran
/// fige. Chaque echec possible (reseau, cle refusee, quota, aucun aliment,
/// service indisponible) donne un message precis et une action.
class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  Future<void>? _run;
  int _messageIndex = 0;
  Timer? _messageTimer;

  static const List<String> _messages = [
    'Preparation de la photo…',
    'Identification des aliments…',
    'Estimation des quantites…',
    'Correspondance avec la table Ciqual…',
    'Calcul des glucides…',
  ];

  @override
  void initState() {
    super.initState();
    _messageTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      if (!mounted) return;
      setState(() => _messageIndex = (_messageIndex + 1) % _messages.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    super.dispose();
  }

  void _start() {
    if (_run != null) return;
    setState(() {
      _run = _analyze();
    });
  }

  Future<void> _analyze() async {
    final capture = ref.read(pendingCaptureProvider);
    if (capture == null) {
      throw const ProviderFailure(
        'Aucune photo a analyser',
        hint: 'Revenez a l\'accueil et reprenez une photo.',
      );
    }

    final service = await ref.read(mealAnalysisServiceProvider.future);
    final outcome = await service.analyze(
      MealAnalysisRequest(
        image: capture.image.bytes,
        mimeType: capture.image.mimeType,
        secondImage: capture.secondImage?.bytes,
        secondMimeType: capture.secondImage?.mimeType,
        portionHint: capture.portionHint,
      ),
    );

    // Le repas analyse remplace l'ebauche : la photo choisie est conservee.
    final draft = ref.read(draftMealProvider);
    final meal = draft == null
        ? outcome.meal
        : outcome.meal.copyWith(name: draft.name, photoPath: draft.photoPath, eatenAt: draft.eatenAt);

    ref.read(draftMealProvider.notifier).start(meal);

    if (!mounted) return;
    context.pushReplacement(Routes.review);
  }

  @override
  Widget build(BuildContext context) {
    final capture = ref.watch(pendingCaptureProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analyse en cours'),
        leading: IconButton(
          onPressed: () {
            ref.read(pendingCaptureProvider.notifier).clear();
            ref.read(draftMealProvider.notifier).clear();
            context.go(Routes.home);
          },
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Annuler',
        ),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: FutureBuilder<void>(
            future: _run,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _Loading(
                  photo: capture?.image.bytes,
                  message: _messages[_messageIndex],
                );
              }

              final error = snapshot.error;
              if (error != null) {
                final failure = AppFailure.from(error);
                return _FailureView(
                  failure: failure,
                  onRetry: () {
                    _messageIndex = 0;
                    _run = null;
                    _start();
                  },
                  onCancel: () {
                    ref.read(pendingCaptureProvider.notifier).clear();
                    ref.read(draftMealProvider.notifier).clear();
                    context.go(Routes.home);
                  },
                );
              }

              return const Center(child: CircularProgressIndicator());
            },
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.photo, required this.message});

  final Uint8List? photo;
  final String message;

  @override
  Widget build(BuildContext context) {
    // Copie locale : Dart ne promeut pas un champ, meme garde par un test de
    // non-nullite. Sans cette copie, `photo` reste de type `Uint8List?`.
    final photo = this.photo;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (photo != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Image.memory(photo, height: 260, fit: BoxFit.cover),
                Positioned.fill(
                  child: ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
                ),
                const SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(strokeWidth: 3.5, color: Colors.white),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.xl),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: Text(
            message,
            key: ValueKey(message),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Cela prend generalement quelques secondes.',
          style: TextStyle(fontSize: 13, color: context.palette.mutedText),
        ),
      ],
    );
  }
}

class _FailureView extends StatelessWidget {
  const _FailureView({required this.failure, required this.onRetry, required this.onCancel});

  final AppFailure failure;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final icon = switch (failure) {
      NetworkFailure() => Icons.wifi_off_rounded,
      TimeoutFailure() => Icons.hourglass_empty_rounded,
      NoFoodDetectedFailure() => Icons.no_food_rounded,
      MissingCredentialFailure() => Icons.key_off_rounded,
      RateLimitFailure() => Icons.timer_rounded,
      _ => Icons.error_outline_rounded,
    };

    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: AppColors.danger),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              failure.message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            if (failure.hint != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                failure.hint!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.5, color: context.palette.mutedText),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),

            if (failure is MissingCredentialFailure)
              FilledButton.icon(
                onPressed: () => context.go(Routes.settings),
                icon: const Icon(Icons.settings_rounded),
                label: const Text('Ouvrir les reglages'),
              )
            else if (failure.isRetryable)
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reessayer'),
              ),

            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: onCancel,
              child: const Text('Revenir a l\'accueil'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton.icon(
              onPressed: () {
                onCancel();
                context.push(Routes.search);
              },
              icon: const Icon(Icons.search_rounded, size: 18),
              label: const Text('Saisir le repas a la main'),
            ),
          ],
        ),
      ),
    );
  }
}
