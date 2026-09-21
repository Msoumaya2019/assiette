import 'dart:convert';

import '../data/local/app_database.dart';
import 'meal.dart';
import 'portion.dart';
import 'suivi_poids.dart';

/// Format du fichier de sauvegarde.
///
/// Le fichier est du JSON, lisible par un humain : si l'application disparaissait,
/// les donnees resteraient exploitables avec un simple editeur de texte. C'est
/// deliberé — une sauvegarde qu'on ne peut relire qu'avec l'outil qui l'a
/// produite n'est pas vraiment une sauvegarde.
class FormatSauvegarde {
  const FormatSauvegarde._();

  /// Marqueur present dans tout fichier produit par l'application. Sert a
  /// refuser tot un fichier etranger, avec un message qui dit quoi faire.
  static const String identifiant = 'assiette.sauvegarde';

  /// Version du format, independante de la version du schema de la base.
  ///
  /// Les deux evoluent separement : ajouter une table change le schema sans
  /// changer le format, et un champ d'enveloppe changerait le format sans
  /// toucher au schema. Une seule version pour les deux obligerait a refuser
  /// des fichiers parfaitement lisibles.
  static const int version = 1;

  /// Nom de fichier propose a l'utilisateur.
  ///
  /// La date est dans le nom pour que deux sauvegardes successives ne
  /// s'ecrasent pas, et pour qu'on reconnaisse le bon fichier sans l'ouvrir.
  static String nomDeFichier(DateTime quand) {
    String deux(int valeur) => valeur.toString().padLeft(2, '0');
    return 'assiette-${quand.year}${deux(quand.month)}${deux(quand.day)}'
        '-${deux(quand.hour)}${deux(quand.minute)}.json';
  }
}

/// Un fichier de sauvegarde refuse.
///
/// Porte toujours une cause lisible : un message du type « fichier invalide »
/// laisserait l'utilisateur sans moyen de savoir s'il s'est trompe de fichier,
/// si le fichier est abime, ou s'il vient d'une version trop recente.
class SauvegardeIllisible implements Exception {
  const SauvegardeIllisible(this.message, {this.hint});

  final String message;

  /// Ce que l'utilisateur peut faire, quand il y a quelque chose a faire.
  final String? hint;

  @override
  String toString() => hint == null ? message : '$message $hint';
}

/// Ce qu'une sauvegarde contient, une fois lue et validee.
class SauvegardeLue {
  const SauvegardeLue({
    required this.version,
    required this.exporteLe,
    required this.appVersion,
    required this.meals,
    required this.templates,
    required this.favorites,
    required this.settings,
    required this.reglagesExclus,
    required this.photosAbsentes,
    this.pesees = const [],
    this.mesures = const [],
    this.portions = const {},
  });

  final int version;
  final DateTime? exporteLe;
  final String appVersion;

  /// Repas, supprimes compris.
  final List<MealEnregistre> meals;

  final List<TemplateEnregistre> templates;
  final List<FavoriteEnregistre> favorites;

  /// Reglages a reinscrire, hors cles exclues.
  final Map<String, String> settings;

  /// Cles de reglages volontairement ecartees de la sauvegarde. Rendues
  /// visibles plutot que tues en silence.
  final List<String> reglagesExclus;

  /// Nombre de repas dont la photo n'a pas pu etre sauvegardee, faute d'etre
  /// incluse dans le fichier. Le chiffre est annonce a l'utilisateur : une
  /// sauvegarde qui perd des photos sans le dire est une sauvegarde qui ment.
  final int photosAbsentes;

  /// Pesees, supprimees comprises.
  final List<PeseeEnregistree> pesees;

  /// Mesures corporelles, supprimees comprises.
  final List<MesureEnregistree> mesures;

  /// Portions retenues, par cle d'aliment.
  final Map<String, Portion> portions;

  int get mealsVivants => meals.where((m) => !m.estSupprime).length;

  int get mealsSupprimes => meals.where((m) => m.estSupprime).length;

  int get peseesVivantes => pesees.where((p) => !p.estSupprimee).length;

  int get peseesSupprimees => pesees.where((p) => p.estSupprimee).length;

  int get mesuresVivantes => mesures.where((m) => !m.estSupprimee).length;

  int get mesuresSupprimees => mesures.where((m) => m.estSupprimee).length;

  /// Lit un fichier de sauvegarde.
  ///
  /// Chaque refus nomme sa cause. Un fichier tronque, un fichier d'une autre
  /// application et un fichier d'une version future se ressemblent de loin —
  /// ce sont pourtant trois situations differentes, et trois gestes differents
  /// pour l'utilisateur.
  static SauvegardeLue depuisTexte(String texte) {
    Object? brut;
    try {
      brut = jsonDecode(texte);
    } on FormatException catch (erreur) {
      throw SauvegardeIllisible(
        'Ce fichier n\'est pas du JSON valide (${erreur.message}).',
        hint:
            'Verifiez que le fichier n\'a pas ete ouvert ni modifie par un '
            'autre programme.',
      );
    }

    if (brut is! Map) {
      throw const SauvegardeIllisible(
        'Ce fichier ne contient pas une sauvegarde Assiette.',
        hint: 'Choisissez un fichier produit par Reglages > Sauvegarde.',
      );
    }

    final json = brut.cast<String, dynamic>();
    final marqueur = json['format'];
    if (marqueur != FormatSauvegarde.identifiant) {
      throw SauvegardeIllisible(
        'Ce fichier n\'est pas une sauvegarde Assiette'
        '${marqueur is String ? ' (marqueur lu : « $marqueur »)' : ''}.',
        hint: 'Choisissez un fichier produit par Reglages > Sauvegarde.',
      );
    }

    final version = json['formatVersion'];
    if (version is! int) {
      throw const SauvegardeIllisible(
        'La version du format est absente ou illisible.',
        hint: 'Le fichier est probablement abime.',
      );
    }
    if (version > FormatSauvegarde.version) {
      throw SauvegardeIllisible(
        'Cette sauvegarde vient d\'une version plus recente de l\'application '
        '(format $version, cette version lit le format '
        '${FormatSauvegarde.version}).',
        hint: 'Mettez l\'application a jour, puis reessayez.',
      );
    }

    final meals = _liste(json['meals'], 'les repas').map(_lireMeal).toList();
    final templates = _liste(
      json['templates'],
      'les repas enregistres',
    ).map(_lireTemplate).toList();
    final favorites = _liste(
      json['favorites'],
      'les favoris',
    ).map(_lireFavorite).toList();

    final settings = <String, String>{};
    final reglages = json['settings'];
    if (reglages is Map) {
      for (final entree in reglages.cast<Object?, Object?>().entries) {
        final cle = entree.key;
        final valeur = entree.value;
        if (cle is String && valeur is String) settings[cle] = valeur;
      }
    }

    // Les sections ajoutees apres la version 1 du format sont **facultatives** :
    // une sauvegarde produite avant elles reste lisible. C'est ce qui permet de
    // ne pas changer le numero de format a chaque table nouvelle, et donc de ne
    // pas refuser des fichiers parfaitement exploitables.
    final pesees = _liste(
      json['pesees'],
      'les pesees',
    ).map(_lirePesee).toList();
    final mesures = _liste(
      json['mesures'],
      'les mesures',
    ).map(_lireMesure).toList();

    final portions = <String, Portion>{};
    final portionsJson = json['portions'];
    if (portionsJson is Map) {
      for (final entree in portionsJson.cast<Object?, Object?>().entries) {
        final cle = entree.key;
        if (cle is! String) continue;
        final portion = Portion.depuisJson(entree.value);
        if (portion != null) portions[cle] = portion;
      }
    }

    // L'objectif de poids n'a pas de section a lui : il vit dans la table
    // `settings`, comme les objectifs nutritionnels, et suit donc le bloc
    // `settings`. Lui donner une seconde place dans le fichier creerait deux
    // sources pour la meme valeur, et rien ne dirait laquelle fait foi.
    return SauvegardeLue(
      version: version,
      exporteLe: json['exporteLe'] is String
          ? DateTime.tryParse(json['exporteLe'] as String)
          : null,
      appVersion: (json['appVersion'] as String?) ?? 'inconnue',
      meals: meals,
      templates: templates,
      favorites: favorites,
      settings: settings,
      reglagesExclus: _liste(
        json['reglagesExclus'],
        'les reglages exclus',
      ).whereType<String>().toList(),
      photosAbsentes: (json['photosAbsentes'] as int?) ?? 0,
      pesees: pesees,
      mesures: mesures,
      portions: portions,
    );
  }

  static List<Object?> _liste(Object? valeur, String quoi) {
    if (valeur == null) return const [];
    if (valeur is! List) {
      throw SauvegardeIllisible(
        'La sauvegarde est abimee : $quoi ne forment pas une liste.',
        hint: 'Le fichier est probablement tronque.',
      );
    }
    return valeur;
  }

  static MealEnregistre _lireMeal(Object? valeur) {
    final json = _objet(valeur, 'un repas');
    final Meal meal;
    try {
      meal = Meal.fromJson(json);
    } on Object catch (erreur) {
      throw SauvegardeIllisible(
        'Un repas de la sauvegarde est illisible ($erreur).',
        hint: 'Le fichier est probablement abime.',
      );
    }
    return MealEnregistre(
      meal: meal,
      createdAt: _entier(json['createdAt']) ?? 0,
      updatedAt: _entier(json['updatedAt']) ?? 0,
      deletedAt: _entier(json['deletedAt']),
    );
  }

  static TemplateEnregistre _lireTemplate(Object? valeur) {
    final json = _objet(valeur, 'un repas enregistre');
    try {
      final items = (json['items'] as List?) ?? const [];
      return TemplateEnregistre(
        template: MealTemplate(
          id: _texte(json['id'], 'un identifiant de repas enregistre'),
          name: (json['name'] as String?) ?? 'Repas',
          items: items
              .map(
                (item) =>
                    MealItem.fromJson((item as Map).cast<String, dynamic>()),
              )
              .toList(),
        ),
        createdAt: _entier(json['createdAt']) ?? 0,
        updatedAt: _entier(json['updatedAt']) ?? 0,
      );
    } on SauvegardeIllisible {
      rethrow;
    } on Object catch (erreur) {
      throw SauvegardeIllisible(
        'Un repas enregistre de la sauvegarde est illisible ($erreur).',
        hint: 'Le fichier est probablement abime.',
      );
    }
  }

  static FavoriteEnregistre _lireFavorite(Object? valeur) {
    final json = _objet(valeur, 'un favori');
    try {
      return FavoriteEnregistre(
        favorite: Favorite(
          id: _texte(json['id'], 'un identifiant de favori'),
          kind: (json['kind'] as String?) ?? 'food',
          label: (json['label'] as String?) ?? '',
          payload: ((json['payload'] as Map?) ?? const {})
              .cast<String, dynamic>(),
        ),
        createdAt: _entier(json['createdAt']) ?? 0,
      );
    } on SauvegardeIllisible {
      rethrow;
    } on Object catch (erreur) {
      throw SauvegardeIllisible(
        'Un favori de la sauvegarde est illisible ($erreur).',
        hint: 'Le fichier est probablement abime.',
      );
    }
  }

  static PeseeEnregistree _lirePesee(Object? valeur) {
    final json = _objet(valeur, 'une pesee');
    final pesee = Pesee.depuisJson(json);
    if (pesee == null) {
      throw const SauvegardeIllisible(
        'Une pesee de la sauvegarde est illisible : son poids ou sa date '
        'manque.',
        hint: 'Le fichier est probablement abime.',
      );
    }
    return PeseeEnregistree(
      pesee: pesee,
      createdAt: _entier(json['createdAt']) ?? 0,
      updatedAt: _entier(json['updatedAt']) ?? 0,
      deletedAt: _entier(json['deletedAt']),
    );
  }

  static MesureEnregistree _lireMesure(Object? valeur) {
    final json = _objet(valeur, 'une mesure');
    final mesure = Mesure.depuisJson(json);
    if (mesure == null) {
      throw const SauvegardeIllisible(
        'Une mesure de la sauvegarde est illisible : son type, sa valeur ou sa '
        'date manque, ou son type n\'est pas reconnu.',
        hint: 'Le fichier est probablement abime.',
      );
    }
    return MesureEnregistree(
      mesure: mesure,
      createdAt: _entier(json['createdAt']) ?? 0,
      updatedAt: _entier(json['updatedAt']) ?? 0,
      deletedAt: _entier(json['deletedAt']),
    );
  }

  static Map<String, dynamic> _objet(Object? valeur, String quoi) {
    if (valeur is! Map) {
      throw SauvegardeIllisible(
        'La sauvegarde est abimee : $quoi n\'est pas un objet.',
        hint: 'Le fichier est probablement tronque.',
      );
    }
    return valeur.cast<String, dynamic>();
  }

  static String _texte(Object? valeur, String quoi) {
    if (valeur is! String || valeur.isEmpty) {
      throw SauvegardeIllisible(
        'La sauvegarde est abimee : $quoi est absent.',
        hint: 'Le fichier est probablement tronque.',
      );
    }
    return valeur;
  }

  /// Un entier, ou `null` si la valeur est absente ou d'un autre type.
  ///
  /// Les horodatages ne font pas echouer la lecture : une sauvegarde sans
  /// `createdAt` reste exploitable, elle perd seulement la date d'entree en
  /// base. Refuser le fichier entier pour cela serait disproportionne.
  static int? _entier(Object? valeur) => valeur is int ? valeur : null;
}
