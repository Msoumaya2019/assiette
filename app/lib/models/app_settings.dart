import 'package:flutter/material.dart';

import 'goals.dart';

/// Preferences de l'utilisateur, persistees localement.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.analysisMode = AnalysisModeSetting.personal,
    this.hasProviderKey = false,
    this.onboardingDone = false,
    this.keepPhotos = true,
    this.mealRemindersEnabled = false,
    this.dailySummaryEnabled = false,
    this.reminderHour = 20,
    this.reminderMinute = 0,
    this.privacyPolicyAcceptedVersion,
    this.goals = DailyGoals.none,
    this.useEstimatesDisclaimerSeen = false,
  });

  final ThemeMode themeMode;
  final AnalysisModeSetting analysisMode;

  /// Vrai lorsqu'une cle fournisseur est enregistree dans le trousseau.
  /// La cle elle-meme n'est jamais conservee ici.
  final bool hasProviderKey;

  final bool onboardingDone;

  /// Conserver la photo avec le repas. Desactive par defaut a la suppression.
  final bool keepPhotos;

  final bool mealRemindersEnabled;
  final bool dailySummaryEnabled;
  final int reminderHour;
  final int reminderMinute;

  /// Version de la politique de confidentialite acceptee, ou null.
  final String? privacyPolicyAcceptedVersion;

  final DailyGoals goals;

  /// Vrai lorsque l'avertissement sur les estimations a deja ete presente.
  final bool useEstimatesDisclaimerSeen;

  bool get hasAcceptedPrivacyPolicy => privacyPolicyAcceptedVersion != null;

  AppSettings copyWith({
    ThemeMode? themeMode,
    AnalysisModeSetting? analysisMode,
    bool? hasProviderKey,
    bool? onboardingDone,
    bool? keepPhotos,
    bool? mealRemindersEnabled,
    bool? dailySummaryEnabled,
    int? reminderHour,
    int? reminderMinute,
    String? privacyPolicyAcceptedVersion,
    DailyGoals? goals,
    bool? useEstimatesDisclaimerSeen,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      analysisMode: analysisMode ?? this.analysisMode,
      hasProviderKey: hasProviderKey ?? this.hasProviderKey,
      onboardingDone: onboardingDone ?? this.onboardingDone,
      keepPhotos: keepPhotos ?? this.keepPhotos,
      mealRemindersEnabled: mealRemindersEnabled ?? this.mealRemindersEnabled,
      dailySummaryEnabled: dailySummaryEnabled ?? this.dailySummaryEnabled,
      reminderHour: reminderHour ?? this.reminderHour,
      reminderMinute: reminderMinute ?? this.reminderMinute,
      privacyPolicyAcceptedVersion:
          privacyPolicyAcceptedVersion ?? this.privacyPolicyAcceptedVersion,
      goals: goals ?? this.goals,
      useEstimatesDisclaimerSeen: useEstimatesDisclaimerSeen ?? this.useEstimatesDisclaimerSeen,
    );
  }
}

/// Mode d'analyse choisi par l'utilisateur.
enum AnalysisModeSetting {
  /// Cle personnelle, stockee dans le trousseau du systeme.
  personal('Cle personnelle', 'Votre cle, conservee dans le trousseau du telephone'),

  /// Service securise heberge, prevu pour la publication.
  proxy('Service securise', 'Aucune cle a saisir, l\'analyse passe par un service heberge'),

  /// Mode demonstration, sans appel reseau.
  demo('Demonstration', 'Donnees de test, aucune analyse reelle');

  const AnalysisModeSetting(this.label, this.description);

  final String label;
  final String description;

  static AnalysisModeSetting fromId(String? id) => AnalysisModeSetting.values.firstWhere(
        (mode) => mode.name == id,
        orElse: () => AnalysisModeSetting.personal,
      );
}

/// Contenu de la politique de confidentialite, affiche dans l'application et
/// repris dans les fiches App Store et Google Play.
class PrivacyPolicy {
  const PrivacyPolicy._();

  static const String version = '1.0';

  static const List<(String, String)> sections = [
    (
      'Ce que fait l\'application',
      'Assiette estime les valeurs nutritionnelles d\'un repas a partir d\'une photo, '
          'd\'un code-barres ou d\'une recherche. Les quantites deduites d\'une photo sont '
          'des estimations : elles doivent etre verifiees lorsque la precision compte.'
    ),
    (
      'Quelles donnees sont envoyees',
      'Lors d\'une analyse par photo, seule l\'image du repas est transmise au service '
          'd\'analyse, apres reduction de sa taille. Aucun nom, aucune adresse et aucun '
          'identifiant de telephone ne sont transmis. Si vous utilisez votre propre cle '
          'd\'acces, l\'image est envoyee directement au fournisseur que vous avez choisi.'
    ),
    (
      'Ce qui reste sur votre telephone',
      'Vos repas, vos aliments, vos favoris, vos objectifs et vos reglages sont stockes '
          'uniquement sur votre appareil. L\'application fonctionne entierement hors ligne '
          'pour la consultation de l\'historique et la recherche d\'aliments.'
    ),
    (
      'Ce qui n\'est pas conserve',
      'Les images envoyees pour analyse ne sont pas archivees par le service : elles sont '
          'traitees puis oubliees. Seule la photo que vous choisissez de conserver reste sur '
          'votre appareil.'
    ),
    (
      'Bases de donnees utilisees',
      'Les valeurs nutritionnelles proviennent de la table Ciqual publiee par l\'ANSES '
          '(Licence Ouverte 2.0) et de la base Open Food Facts (licence ODbL). Ces sources '
          'sont citees dans l\'application.'
    ),
    (
      'Vos droits',
      'Vous pouvez supprimer un repas, effacer l\'ensemble de vos donnees ou retirer votre '
          'cle d\'acces a tout moment depuis les reglages. La desinstallation de '
          'l\'application supprime definitivement les donnees locales.'
    ),
    (
      'Avertissement',
      'Assiette n\'est pas un dispositif medical. L\'application ne fournit aucun diagnostic, '
          'aucune recommandation therapeutique et aucune posologie. Pour toute decision '
          'concernant votre sante, consultez un professionnel.'
    ),
  ];
}
