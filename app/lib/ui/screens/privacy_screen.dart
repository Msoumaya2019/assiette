import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/app_settings.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

/// Politique de confidentialite, affichee dans l'application.
///
/// Le meme texte sert de base a la fiche App Store et a la fiche Google Play.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accepted = ref.watch(settingsProvider).hasAcceptedPrivacyPolicy;

    return Scaffold(
      appBar: AppBar(title: const Text('Confidentialite')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xxl,
          ),
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, color: context.colors.primary),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Version ${PrivacyPolicy.version}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.palette.mutedText,
                  ),
                ),
                const Spacer(),
                if (accepted)
                  const Row(
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: AppColors.success,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Acceptee',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),

            for (final (title, body) in PrivacyPolicy.sections) ...[
              SectionCard(
                title: title,
                child: Text(
                  body,
                  style: const TextStyle(fontSize: 14, height: 1.6),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            const EstimateBanner(
              message:
                  'En resume : vos donnees restent sur votre telephone, seule l\'image '
                  'du repas est transmise pour analyse, et rien n\'est conserve cote serveur.',
            ),

            const SizedBox(height: AppSpacing.lg),

            if (!accepted)
              FilledButton(
                onPressed: () async {
                  await ref
                      .read(settingsProvider.notifier)
                      .acceptPrivacyPolicy(PrivacyPolicy.version);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Politique de confidentialite acceptee.'),
                    ),
                  );
                },
                child: const Text('J\'accepte cette politique'),
              ),
          ],
        ),
      ),
    );
  }
}
