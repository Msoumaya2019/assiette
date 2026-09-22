import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/config.dart';
import '../../core/failures.dart';
import '../../core/theme.dart';
import '../../models/app_settings.dart';
import '../../models/sauvegarde.dart';
import '../../models/session.dart';
import '../../services/backup_service.dart';
import '../../services/synchronisation_service.dart';
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              mode.description,
                              style: const TextStyle(fontSize: 12),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                  ),

                  if (settings.analysisMode ==
                      AnalysisModeSetting.personal) ...[
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
                        style: TextStyle(
                          fontSize: 12,
                          color: context.palette.mutedText,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.md),

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
                            'Votre cle est conservee dans le trousseau securise du telephone, '
                            'jamais dans l\'application elle-meme.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
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
                      (
                        ThemeMode.system,
                        'Suivre le systeme',
                        Icons.brightness_auto_rounded,
                      ),
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
                    onChanged: (value) => _basculerRappel(
                      context,
                      ref,
                      valeur: value,
                      appliquer: notifier.setMealReminders,
                    ),
                    title: const Text('Rappel pour renseigner un repas'),
                    subtitle: const Text(
                      'Une notification discrete, desactivable a tout moment',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    value: settings.dailySummaryEnabled,
                    onChanged: (value) => _basculerRappel(
                      context,
                      ref,
                      valeur: value,
                      appliquer: notifier.setDailySummary,
                    ),
                    title: const Text('Resume de la journee'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (settings.mealRemindersEnabled ||
                      settings.dailySummaryEnabled)
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
                        if (time != null) {
                          notifier.setReminderTime(time.hour, time.minute);
                        }
                      },
                    ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            SectionCard(
              title: 'Sauvegarde',
              subtitle: 'Emporter vos donnees, ou les remettre en place',
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.ios_share_rounded, size: 20),
                    title: const Text('Exporter mes donnees'),
                    subtitle: const Text(
                      'Fichier lisible par un humain, a conserver ou a envoyer. '
                      'Les photos ne sont pas incluses.',
                      style: TextStyle(fontSize: 12),
                    ),
                    onTap: () => _exporter(context, ref),
                  ),
                  const Divider(height: AppSpacing.lg),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.restore_rounded, size: 20),
                    title: const Text('Restaurer une sauvegarde'),
                    subtitle: const Text(
                      'Fusionner ajoute ce qui manque, sans rien effacer. '
                      'Remplacer efface d\'abord les donnees de ce telephone.',
                      style: TextStyle(fontSize: 12),
                    ),
                    onTap: () => _restaurer(context, ref),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            SectionCard(
              title: 'Compte',
              subtitle: 'Pour retrouver vos repas sur vos appareils',
              child: const _CompteSection(),
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
                    leading: const Icon(
                      Icons.delete_forever_rounded,
                      size: 20,
                      color: AppColors.danger,
                    ),
                    title: const Text(
                      'Effacer toutes mes donnees',
                      style: TextStyle(color: AppColors.danger),
                    ),
                    subtitle: const Text(
                      'Repas, favoris, repas types, objectifs, cle enregistree '
                      'et session de compte',
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
                      '${AppConfig.appName} ${AppConfig.version} — '
                      'compilation ${AppConfig.buildChannel}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            const EstimateBanner(
              message:
                  'Assiette n\'est pas un dispositif medical. L\'application ne fournit '
                  'aucun diagnostic, aucune recommandation therapeutique et aucune posologie.',
            ),
          ],
        ),
      ),
    );
  }

  /// Active ou desactive un rappel, en demandant d'abord l'autorisation.
  ///
  /// Android 13 et les versions suivantes, comme iOS, exigent une autorisation
  /// explicite pour afficher une notification. Sans cette demande, le reglage
  /// s'activait, la notification etait bien programmee, et rien n'arrivait
  /// jamais — sans que rien ne l'explique. Le reglage reste donc desactive tant
  /// que l'autorisation n'a pas ete accordee, ce qui rend le refus visible.
  ///
  /// Desactiver ne demande evidemment aucune autorisation : c'est le seul chemin
  /// qui ne s'interrompt pas.
  Future<void> _basculerRappel(
    BuildContext context,
    WidgetRef ref, {
    required bool valeur,
    required Future<void> Function(bool) appliquer,
  }) async {
    if (!valeur) {
      await appliquer(false);
      return;
    }

    final accordee = await ref
        .read(notificationServiceProvider)
        .requestPermission();

    if (!accordee) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Assiette n\'est pas autorisee a afficher des notifications. '
            'Autorisez-les dans les reglages du telephone pour activer ce rappel.',
          ),
        ),
      );
      return;
    }

    await appliquer(true);
  }

  /// Exporte les donnees, puis ouvre la feuille de partage du systeme.
  ///
  /// Le fichier est d'abord ecrit dans le dossier prive de l'application, puis
  /// propose au partage : c'est la feuille de partage qui permet de l'envoyer
  /// vers un stockage en ligne ou de le retrouver depuis un ordinateur. Un
  /// fichier qui ne quitte jamais le telephone ne serait pas une sauvegarde.
  ///
  /// Aucune erreur ne bloque l'ecran : tout echec devient un message lisible.
  Future<void> _exporter(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = ref.read(backupServiceProvider);
      final fichier = await service.ecrireFichier(await service.exporter());
      if (!context.mounted) return;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(fichier.path)],
          subject: 'Sauvegarde Assiette',
          text: 'Sauvegarde de mes repas Assiette.',
          sharePositionOrigin: _origineDuPartage(context),
        ),
      );
    } on Object catch (erreur) {
      messenger.showSnackBar(
        SnackBar(content: Text('L\'export a echoue : $erreur')),
      );
    }
  }

  /// Choisit un fichier, demande le mode, puis applique la sauvegarde.
  Future<void> _restaurer(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final choix = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choisir une sauvegarde Assiette',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (choix == null || choix.files.isEmpty) return;

      final sauvegarde = SauvegardeLue.depuisTexte(
        await _lireLeFichier(choix.files.single),
      );

      if (!context.mounted) return;
      final mode = await _demanderLeMode(context, sauvegarde);
      if (mode == null) return;

      final rapport = await ref
          .read(backupServiceProvider)
          .restaurer(sauvegarde, mode: mode);
      // Les reglages ont pu etre reecrits : l'application doit les relire, sans
      // quoi elle afficherait encore ceux d'avant jusqu'au prochain demarrage.
      await ref.read(settingsProvider.notifier).rechargerApresRestauration();

      messenger.showSnackBar(SnackBar(content: Text(rapport.resume)));
    } on SauvegardeIllisible catch (erreur) {
      messenger.showSnackBar(SnackBar(content: Text(erreur.toString())));
    } on Object catch (erreur) {
      messenger.showSnackBar(
        SnackBar(content: Text('La restauration a echoue : $erreur')),
      );
    }
  }

  /// Lit le contenu d'un fichier choisi, quel que soit le chemin fourni.
  ///
  /// `withData` remplit `bytes` sur toutes les plateformes ; `path` sert de
  /// repli, car il peut pointer vers une copie temporaire selon la source.
  Future<String> _lireLeFichier(PlatformFile fichier) async {
    final octets = fichier.bytes;
    if (octets != null) {
      try {
        return utf8.decode(octets);
      } on FormatException {
        throw const SauvegardeIllisible(
          'Ce fichier n\'est pas du texte lisible (UTF-8).',
          hint: 'Choisissez un fichier produit par Reglages > Sauvegarde.',
        );
      }
    }

    final chemin = fichier.path;
    if (chemin == null) {
      throw const SauvegardeIllisible(
        'Le fichier choisi n\'est pas accessible.',
        hint: 'Copiez-le dans le stockage du telephone, puis reessayez.',
      );
    }
    return File(chemin).readAsString();
  }

  /// Demande comment appliquer la sauvegarde.
  ///
  /// Le choix est explicite parce que les deux modes n'ont pas les memes
  /// consequences : l'un ne peut que completer, l'autre efface. Laisser
  /// l'application decider a la place de l'utilisateur reviendrait a effacer
  /// ses donnees sans le lui dire.
  Future<ModeRestauration?> _demanderLeMode(
    BuildContext context,
    SauvegardeLue sauvegarde,
  ) {
    return showDialog<ModeRestauration>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restaurer cette sauvegarde ?'),
        content: Text(
          'Sauvegarde du ${_dateLisible(sauvegarde.exporteLe)}.\n'
          '${sauvegarde.mealsVivants} repas, '
          '${sauvegarde.templates.length} repas enregistres, '
          '${sauvegarde.favorites.length} favoris.\n\n'
          'Fusionner ajoute ce qui manque et ne supprime jamais rien.\n'
          'Remplacer efface d\'abord les donnees presentes sur ce telephone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(ModeRestauration.fusion),
            child: const Text('Fusionner'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(ModeRestauration.remplacement),
            child: const Text('Remplacer'),
          ),
        ],
      ),
    );
  }

  /// Rectangle d'ancrage de la feuille de partage.
  ///
  /// Obligatoire sur iPad et macOS : sans lui, le partage leve une exception au
  /// lieu de s'ouvrir. On ancre a la tuile quand sa position est connue, sinon
  /// au centre de l'ecran — un ancrage valide dans tous les cas.
  Rect _origineDuPartage(BuildContext context) {
    final boite = context.findRenderObject();
    if (boite is RenderBox && boite.hasSize) {
      return boite.localToGlobal(Offset.zero) & boite.size;
    }
    final taille = MediaQuery.sizeOf(context);
    return Rect.fromCenter(
      center: Offset(taille.width / 2, taille.height / 2),
      width: 1,
      height: 1,
    );
  }

  String _dateLisible(DateTime? quand) {
    if (quand == null) return 'date inconnue';
    final local = quand.toLocal();
    String deux(int valeur) => valeur.toString().padLeft(2, '0');
    return '${deux(local.day)}/${deux(local.month)}/${local.year} '
        'a ${deux(local.hour)}h${deux(local.minute)}';
  }

  Future<void> _confirmErase(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Effacer toutes les donnees ?'),
        content: const Text(
          'Vos repas, favoris, repas types, objectifs, les photos enregistrees, '
          'votre cle d\'analyse et votre session de compte seront supprimes de '
          'cet appareil. Cette action est definitive et ne peut pas etre '
          'annulee.\n\n'
          'Pour conserver votre historique, exportez d\'abord une sauvegarde '
          'depuis la section Sauvegarde ci-dessus.',
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
      const SnackBar(
        content: Text('Toutes les donnees locales ont ete effacees.'),
      ),
    );
  }
}

/// Saisie de la cle d'analyse personnelle.
class _ApiKeyTile extends StatefulWidget {
  const _ApiKeyTile({
    required this.hasKey,
    required this.onSave,
    required this.onClear,
  });

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
              const Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: AppColors.success,
              ),
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
              icon: Icon(
                _visible
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
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
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
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

/// La section Compte : se connecter, ou voir de quel compte il s'agit.
///
/// Trois cas, et le troisieme n'est pas un etat : un exemplaire compile **sans
/// projet** ne peut ouvrir aucune session. Il le dit, et n'affiche aucun
/// formulaire. Proposer une saisie qui ne peut pas aboutir serait le plus sur
/// moyen de faire porter a l'utilisateur la responsabilite d'une erreur de
/// compilation.
class _CompteSection extends ConsumerStatefulWidget {
  const _CompteSection();

  @override
  ConsumerState<_CompteSection> createState() => _CompteSectionState();
}

class _CompteSectionState extends ConsumerState<_CompteSection> {
  final TextEditingController _adresse = TextEditingController();
  final TextEditingController _motDePasse = TextEditingController();

  /// Vrai pendant la requete. Empeche une seconde tentative de partir avant que
  /// la premiere ait repondu : deux requetes pour un seul geste, c'est un refus
  /// de trop par la limite de debit du serveur.
  bool _enCours = false;

  /// Le dernier refus, tel qu'il doit etre montre. Efface des qu'on retente.
  String? _refus;

  @override
  void dispose() {
    _adresse.dispose();
    _motDePasse.dispose();
    super.dispose();
  }

  Future<void> _connecter() async {
    final adresse = _adresse.text.trim();
    if (adresse.isEmpty || _motDePasse.text.isEmpty) {
      setState(() {
        _refus = 'Renseignez votre adresse et votre mot de passe.';
      });
      return;
    }

    setState(() {
      _enCours = true;
      _refus = null;
    });

    try {
      await ref
          .read(compteProvider.notifier)
          .connecter(email: adresse, motDePasse: _motDePasse.text);
      if (!mounted) return;
      // Le mot de passe ne reste pas dans le champ : la section peut etre
      // rouverte apres une deconnexion, et un secret n'a rien a y faire encore.
      _motDePasse.clear();
      setState(() => _enCours = false);
    } on Object catch (erreur) {
      if (!mounted) return;
      // `AppFailure.from` rend l'echec tel quel s'il en est deja un : les
      // messages ecrits dans `failures.dart` arrivent donc intacts.
      setState(() {
        _enCours = false;
        _refus = _messageDe(AppFailure.from(erreur));
      });
    }
  }

  Future<void> _deconnecter() async {
    setState(() {
      _enCours = true;
      _refus = null;
    });

    try {
      await ref.read(compteProvider.notifier).deconnecter();
    } on Object catch (erreur) {
      if (!mounted) return;
      setState(() {
        _enCours = false;
        _refus = AppFailure.from(erreur).message;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _enCours = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(projetConfigureProvider)) {
      return _note(
        'Cet exemplaire a ete compile sans projet : le compte et la '
        'synchronisation ne sont pas disponibles. Recompiler avec SUPABASE_URL '
        'et SUPABASE_ANON_KEY pour les activer.',
      );
    }

    return ref
        .watch(compteProvider)
        .when(
          // La lecture du trousseau est asynchrone : le premier affichage n'a
          // pas encore de reponse. Une barre discrete le dit, plutot qu'un
          // formulaire qui apparaitrait puis disparaitrait.
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: LinearProgressIndicator(minHeight: 2),
          ),
          // Le trousseau lui-meme peut refuser de repondre. On ne fait pas
          // tomber l'ecran pour autant : on invite a se reconnecter, ce qui est
          // le remede dans tous les cas ou la lecture echoue.
          error: (erreur, pile) => _note(
            'La session enregistree n\'a pas pu etre relue. Reconnectez-vous '
            'pour la remplacer.',
          ),
          data: (session) =>
              session == null ? _formulaire() : _connecte(session),
        );
  }

  Widget _formulaire() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _adresse,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Adresse electronique'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _motDePasse,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (!_enCours) _connecter();
          },
          decoration: const InputDecoration(labelText: 'Mot de passe'),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: _enCours ? null : _connecter,
          icon: _enCours
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.login_rounded, size: 18),
          label: const Text('Se connecter'),
        ),
        if (_refus != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _ligneDeRefus(_refus!),
        ],
        const SizedBox(height: AppSpacing.md),
        _note(
          'Votre mot de passe n\'est jamais conserve : seule la session est '
          'rangee dans le trousseau du telephone.',
        ),
      ],
    );
  }

  Widget _connecte(Session session) {
    final adresse = session.adresse;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: 18,
              color: AppColors.success,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                // Un compte ouvert par telephone n'a pas d'adresse : le serveur
                // ne classe pas `email` parmi les champs obligatoires. On le dit
                // sans le montrer comme un manque.
                adresse == null ? 'Compte connecte' : 'Connecte : $adresse',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _note(
          'La session est rangee dans le trousseau du telephone : '
          'l\'application se rouvre sans redemander le mot de passe.',
        ),
        const SizedBox(height: AppSpacing.md),
        _synchronisation(),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: _enCours ? null : _deconnecter,
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('Se deconnecter'),
        ),
        if (_refus != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _ligneDeRefus(_refus!),
        ],
      ],
    );
  }

  /// Le passage de synchronisation, et ce qu'il a fait.
  ///
  /// L'etat vit dans `synchronisationProvider`, pas dans cette section : un
  /// passage survit ainsi a un changement d'onglet, et l'ecran n'a pas a
  /// deviner s'il est en cours — il le lit.
  Widget _synchronisation() {
    final etat = ref.watch(synchronisationProvider);
    final enCours = etat.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: enCours ? null : _synchroniser,
          icon: enCours
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.sync_rounded, size: 18),
          label: const Text('Synchroniser maintenant'),
        ),
        const SizedBox(height: AppSpacing.sm),
        etat.when(
          loading: () => _note('Passage en cours...'),
          error: (erreur, pile) =>
              _ligneDeRefus(_messageDe(AppFailure.from(erreur))),
          data: (rapport) => rapport == null
              ? _note('Aucun passage n\'a encore eu lieu depuis cet appareil.')
              : _rapport(rapport),
        ),
        const SizedBox(height: AppSpacing.sm),
        _note(
          'Le passage est manuel : il n\'a pas lieu tout seul quand un repas '
          'est enregistre. Les donnees restent sur cet appareil tant qu\'aucun '
          'passage n\'a abouti.',
        ),
      ],
    );
  }

  Future<void> _synchroniser() async {
    // Aucun `try` ici, et c'est volontaire : le notifier publie l'echec dans son
    // etat au lieu de le lever. Un `catch` de plus ne servirait qu'a le
    // reformuler deux fois, et la deuxieme formulation finirait par diverger.
    await ref.read(synchronisationProvider.notifier).synchroniser();
  }

  /// Ce qu'un passage a fait, en clair.
  Widget _rapport(RapportSynchronisation rapport) {
    final lignes = <Widget>[];

    if (rapport.aEchoue) {
      for (final table in rapport.tablesEnEchec) {
        lignes.add(
          _ligneDeRefus(
            '${_libelleDeTable(table)} : '
            '${_messageDe(rapport.parTable[table]?.panne)}',
          ),
        );
      }
    } else if (rapport.estVide) {
      lignes.add(_note('Tout est deja a jour : rien n\'a eu a bouger.'));
    } else {
      lignes.add(
        _note(
          '${rapport.poussees} ligne(s) envoyee(s), '
          '${rapport.appliquees} ligne(s) recue(s).',
        ),
      );
    }

    if (rapport.horlogeSuspecte) {
      // L'ecart est **signale**, jamais applique : redater ferait de chaque
      // passage une modification, et les deux appareils se renverraient la meme
      // ligne sans fin. Le dire evite de chercher ailleurs une date etrange.
      lignes.add(
        _note(
          'L\'horloge de cet appareil s\'ecarte de celle du serveur de '
          '${(rapport.decalageMs! / 1000).round()} secondes. Les dates '
          'enregistrees ne sont pas corrigees pour autant.',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final ligne in lignes) ...[
          ligne,
          const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }

  Widget _ligneDeRefus(String texte) => Text(
    texte,
    style: const TextStyle(
      fontSize: 12,
      color: AppColors.danger,
      fontWeight: FontWeight.w600,
    ),
  );

  /// Le message d'un echec, suivi de son conseil quand il en porte un.
  ///
  /// Ecrit **une seule fois** : il l'etait a deux endroits — la connexion et,
  /// depuis, le rapport de synchronisation — et deux copies de cette
  /// concatenation finiraient par ne plus dire la meme chose.
  String _messageDe(AppFailure? echec) {
    if (echec == null) return 'Echec sans cause connue.';
    final hint = echec.hint;
    return hint == null ? echec.message : '${echec.message}. $hint';
  }

  /// Le nom d'une table, tel qu'un utilisateur le lit.
  ///
  /// Le rapport nomme les tables en vocabulaire **local** (`meals`, `pesees`),
  /// qui n'est pas fait pour etre lu. Une table absente de cette table de
  /// correspondance **garde son nom technique** plutot que d'etre masquee :
  /// c'est un repli, pas une omission, et le jour ou une table est ajoutee, le
  /// rapport la montre au lieu de la taire.
  String _libelleDeTable(String table) =>
      const {
        'meals': 'Repas',
        'templates': 'Modeles',
        'favorites': 'Favoris',
        'pesees': 'Pesees',
        'mesures': 'Mensurations',
        'portions': 'Portions',
      }[table] ??
      table;

  Widget _note(String texte) => Text(
    texte,
    style: TextStyle(
      fontSize: 12,
      height: 1.4,
      color: context.palette.mutedText,
    ),
  );
}
