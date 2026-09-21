import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/local/app_database.dart';
import '../models/meal.dart';
import '../models/sauvegarde.dart';

/// Ce qu'une restauration a fait, en chiffres.
///
/// L'utilisateur vient de remplacer ou de completer ses donnees : lui dire
/// « restauration terminee » sans plus ne lui permet pas de verifier que le
/// fichier choisi etait le bon. Les chiffres le lui disent.
class RapportRestauration {
  const RapportRestauration({
    required this.mode,
    required this.mealsEcrits,
    required this.mealsIgnores,
    required this.templatesEcrits,
    required this.templatesIgnores,
    required this.favoritesEcrits,
    required this.favoritesIgnores,
    required this.reglagesEcrits,
    required this.reglagesIgnores,
    required this.photosPerdues,
    this.peseesEcrites = 0,
    this.peseesIgnorees = 0,
    this.mesuresEcrites = 0,
    this.mesuresIgnorees = 0,
    this.portionsEcrites = 0,
    this.portionsIgnorees = 0,
  });

  final ModeRestauration mode;
  final int mealsEcrits;
  final int mealsIgnores;
  final int templatesEcrits;
  final int templatesIgnores;
  final int favoritesEcrits;
  final int favoritesIgnores;
  final int reglagesEcrits;
  final int reglagesIgnores;

  /// Repas dont la photo n'a pas ete retrouvee sur cet appareil.
  final int photosPerdues;

  final int peseesEcrites;
  final int peseesIgnorees;
  final int mesuresEcrites;
  final int mesuresIgnorees;
  final int portionsEcrites;
  final int portionsIgnorees;

  bool get rienAEcrit =>
      mealsEcrits == 0 &&
      templatesEcrits == 0 &&
      favoritesEcrits == 0 &&
      reglagesEcrits == 0 &&
      peseesEcrites == 0 &&
      mesuresEcrites == 0 &&
      portionsEcrites == 0;

  /// Resume en une phrase, affiche tel quel a l'utilisateur.
  String get resume {
    if (rienAEcrit) {
      return mode == ModeRestauration.fusion
          ? 'Rien a ajouter : ces donnees sont deja presentes.'
          : 'La sauvegarde ne contenait aucune donnee.';
    }

    final morceaux = <String>[
      if (mealsEcrits > 0) '$mealsEcrits repas',
      if (templatesEcrits > 0) '$templatesEcrits repas enregistres',
      if (favoritesEcrits > 0) '$favoritesEcrits favoris',
      if (peseesEcrites > 0) '$peseesEcrites pesees',
      if (mesuresEcrites > 0) '$mesuresEcrites mesures',
      if (portionsEcrites > 0) '$portionsEcrites portions',
      if (reglagesEcrits > 0) '$reglagesEcrits reglages',
    ];

    final ignores =
        mealsIgnores +
        templatesIgnores +
        favoritesIgnores +
        peseesIgnorees +
        mesuresIgnorees +
        portionsIgnorees;

    final buffer = StringBuffer()..write('Restaure : ${morceaux.join(', ')}.');
    if (ignores > 0) {
      buffer.write(' Conserve : $ignores element(s) deja present(s).');
    }
    if (photosPerdues > 0) {
      buffer.write(
        ' $photosPerdues photo(s) non retrouvee(s) sur cet appareil.',
      );
    }
    return buffer.toString();
  }
}

/// Comment une sauvegarde s'applique.
enum ModeRestauration {
  /// Ajoute ce qui manque. **N'efface jamais rien.**
  fusion,

  /// Efface les donnees locales, puis reinscrit la sauvegarde.
  remplacement,
}

/// Export et restauration de la base locale.
///
/// Ce service ne connait ni `share_plus` ni le selecteur de fichiers : il rend
/// du texte et ecrit un fichier. C'est deliberé — les greffons natifs ne se
/// lancent pas dans un test unitaire, et une sauvegarde qui ne se teste qu'a la
/// main est une sauvegarde dont on ne sait rien.
///
/// ## Ce qui n'est pas sauvegarde, et pourquoi
///
/// Les **photos** ne sont pas incluses : une photo de repas pese quelques
/// centaines de kilooctets, et un historique de deux cents repas ferait un
/// fichier de plusieurs dizaines de megaoctets, impossible a envoyer par
/// messagerie et long a relire en memoire. Les chemins sont conserves, mais ils
/// ne veulent rien dire sur un autre appareil. La restauration verifie donc
/// l'existence de chaque fichier et **annonce** le nombre de photos perdues,
/// plutot que de laisser des references mortes.
///
/// La **cle du fournisseur d'analyse** n'est pas sauvegardee : elle vit dans le
/// trousseau du systeme, pas dans la base, et un fichier de sauvegarde est un
/// fichier en clair. C'est aussi ce qui rend une sauvegarde partageable sans
/// risque.
class BackupService {
  BackupService({
    required AppDatabase database,
    required String appVersion,
    Future<Directory> Function()? dossier,
  }) : _database = database,
       _appVersion = appVersion,
       _dossier = dossier ?? getApplicationDocumentsDirectory;

  final AppDatabase _database;
  final String _appVersion;
  final Future<Directory> Function() _dossier;

  /// Sous-dossier ou sont deposees les sauvegardes.
  static const String sousDossier = 'sauvegardes';

  /// Cles de reglages jamais ecrites dans un fichier de sauvegarde.
  ///
  /// Aujourd'hui aucun secret ne vit dans la table `settings` : la cle
  /// d'analyse est dans le trousseau du systeme. Cette liste est une ceinture
  /// en plus, pour qu'un reglage ajoute plus tard — un jeton, un mot de passe —
  /// ne parte pas en clair sans que personne ne le remarque. Les cles ecartees
  /// sont **nommees** dans le fichier, pour qu'un oubli se voie au lieu de se
  /// deviner.
  static final RegExp motifSensible = RegExp(
    r'(key|token|secret|password|passwd|credential|jeton|apikey)',
    caseSensitive: false,
  );

  /// Construit le texte de la sauvegarde. N'ecrit rien.
  Future<String> exporter({DateTime? maintenant}) async {
    final quand = maintenant ?? DateTime.now();

    final meals = await _database.mealsPourSauvegarde();
    final templates = await _database.templatesPourSauvegarde();
    final favorites = await _database.favoritesPourSauvegarde();
    final settings = await _database.settingsPourSauvegarde();
    final pesees = await _database.peseesPourSauvegarde();
    final mesures = await _database.mesuresPourSauvegarde();
    final portions = await _database.portionsPourSauvegarde();

    final reglagesExclus = <String>[];
    final reglagesGardes = <String, String>{};
    for (final entree in settings.entries) {
      if (motifSensible.hasMatch(entree.key)) {
        reglagesExclus.add(entree.key);
      } else {
        reglagesGardes[entree.key] = entree.value;
      }
    }
    reglagesExclus.sort();

    // Les photos ne suivent pas : on compte celles qu'on abandonne, pour
    // pouvoir le dire. Un chemin vide ne compte pas, ce n'est pas une photo.
    final photosAbsentes = meals
        .where((m) => !m.estSupprime)
        .where((m) => (m.meal.photoPath ?? '').isNotEmpty)
        .length;

    final contenu = <String, Object?>{
      'format': FormatSauvegarde.identifiant,
      'formatVersion': FormatSauvegarde.version,
      'exporteLe': quand.toUtc().toIso8601String(),
      'appVersion': _appVersion,
      // Compteurs : ils permettent de reperer un fichier tronque a la lecture,
      // et donnent a l'utilisateur de quoi verifier ce qu'il a sauvegarde.
      'compte': {
        'meals': meals.where((m) => !m.estSupprime).length,
        'mealsSupprimes': meals.where((m) => m.estSupprime).length,
        'templates': templates.where((t) => !t.estSupprime).length,
        'templatesSupprimes': templates.where((t) => t.estSupprime).length,
        'favorites': favorites.where((f) => !f.estSupprime).length,
        'favoritesSupprimes': favorites.where((f) => f.estSupprime).length,
        'pesees': pesees.where((p) => !p.estSupprimee).length,
        'peseesSupprimees': pesees.where((p) => p.estSupprimee).length,
        'mesures': mesures.where((m) => !m.estSupprimee).length,
        'mesuresSupprimees': mesures.where((m) => m.estSupprimee).length,
        'portions': portions.where((p) => !p.estSupprimee).length,
        'portionsSupprimees': portions.where((p) => p.estSupprimee).length,
      },
      'photosAbsentes': photosAbsentes,
      'reglagesExclus': reglagesExclus,
      'meals': [
        for (final enregistre in meals)
          {
            ...enregistre.meal.toJson(),
            'createdAt': enregistre.createdAt,
            'updatedAt': enregistre.updatedAt,
            'deletedAt': enregistre.deletedAt,
          },
      ],
      'templates': [
        for (final enregistre in templates)
          {
            'id': enregistre.template.id,
            'name': enregistre.template.name,
            'items': enregistre.template.items
                .map((item) => item.toJson())
                .toList(),
            'createdAt': enregistre.createdAt,
            'updatedAt': enregistre.updatedAt,
            'deletedAt': enregistre.deletedAt,
          },
      ],
      'favorites': [
        for (final enregistre in favorites)
          {
            'id': enregistre.favorite.id,
            'kind': enregistre.favorite.kind,
            'label': enregistre.favorite.label,
            'payload': enregistre.favorite.payload,
            'createdAt': enregistre.createdAt,
            'updatedAt': enregistre.updatedAt,
            'deletedAt': enregistre.deletedAt,
          },
      ],
      'settings': reglagesGardes,

      // Sections ajoutees apres la version 1 du format. Leur absence dans un
      // fichier ancien est normale : la lecture les traite comme vides, et le
      // numero de format n'a donc pas eu a changer. Un fichier ecrit ici reste
      // lisible par une version anterieure, qui ignorera simplement ces cles.
      'pesees': [
        for (final enregistre in pesees)
          {
            ...enregistre.pesee.toJson(),
            'createdAt': enregistre.createdAt,
            'updatedAt': enregistre.updatedAt,
            'deletedAt': enregistre.deletedAt,
          },
      ],
      'mesures': [
        for (final enregistre in mesures)
          {
            ...enregistre.mesure.toJson(),
            'createdAt': enregistre.createdAt,
            'updatedAt': enregistre.updatedAt,
            'deletedAt': enregistre.deletedAt,
          },
      ],
      // Liste et non objet : une portion porte desormais une pierre tombale, et
      // une cle ne peut pas dire « supprimee ». Les anciens fichiers, ecrits
      // sous forme d'objet, restent lus — voir `SauvegardeLue._lirePortions`.
      'portions': [
        for (final enregistre in portions)
          {
            'cle': enregistre.cle,
            'portion': enregistre.portion.toJson(),
            'updatedAt': enregistre.updatedAt,
            'deletedAt': enregistre.deletedAt,
          },
      ],
    };

    // Avec indentation plutot que compact : le fichier reste lisible dans un
    // editeur de texte, ce qui est le point d'une sauvegarde en clair.
    return JsonEncoder.withIndent('  ').convert(contenu);
  }

  /// Ecrit la sauvegarde dans un fichier et rend ce fichier.
  ///
  /// Le fichier est depose dans le dossier prive de l'application : il sert de
  /// source au partage, et reste disponible si l'utilisateur veut le partager
  /// une seconde fois sans refaire l'export.
  Future<File> ecrireFichier(String contenu, {DateTime? maintenant}) async {
    final quand = maintenant ?? DateTime.now();
    final base = await _dossier();
    final dossier = Directory(p.join(base.path, sousDossier));
    if (!dossier.existsSync()) {
      await dossier.create(recursive: true);
    }
    final fichier = File(
      p.join(dossier.path, FormatSauvegarde.nomDeFichier(quand)),
    );
    await fichier.writeAsString(contenu, flush: true);
    return fichier;
  }

  /// Applique une sauvegarde.
  ///
  /// En mode [ModeRestauration.fusion], **rien n'est jamais efface** : ce qui
  /// existe deja localement l'emporte, et seules les donnees absentes sont
  /// ajoutees. C'est la regle qu'attend quiconque choisit « fusionner », et
  /// elle rend l'operation sans danger : le pire resultat possible est « rien
  /// n'a change ».
  Future<RapportRestauration> restaurer(
    SauvegardeLue sauvegarde, {
    required ModeRestauration mode,
  }) async {
    if (mode == ModeRestauration.remplacement) {
      await _database.wipe();
    }

    final idsExistants = mode == ModeRestauration.fusion
        ? await _database.idsDeMeals()
        : const <String>{};

    var mealsEcrits = 0;
    var mealsIgnores = 0;
    var photosPerdues = 0;

    for (final enregistre in sauvegarde.meals) {
      if (mode == ModeRestauration.fusion) {
        // Un identifiant deja present : le repas local gagne, y compris s'il
        // avait ete supprime ici. Une fusion n'efface rien et ne ressuscite
        // rien.
        if (idsExistants.contains(enregistre.meal.id)) {
          mealsIgnores++;
          continue;
        }
        // Une pierre tombale sans repas local n'apprend rien : il n'y a rien a
        // supprimer. L'ecrire ajouterait une ligne invisible.
        if (enregistre.estSupprime) {
          mealsIgnores++;
          continue;
        }
      }

      final resultat = _sansPhotoAbsente(enregistre.meal);
      if (resultat.photoPerdue) {
        photosPerdues++;
      }

      await _database.restaurerMeal(
        MealEnregistre(
          meal: resultat.meal,
          createdAt: enregistre.createdAt,
          updatedAt: enregistre.updatedAt,
          deletedAt: enregistre.deletedAt,
        ),
      );
      mealsEcrits++;
    }

    final idsTemplates = mode == ModeRestauration.fusion
        ? (await _database.templatesPourSauvegarde())
              .map((t) => t.template.id)
              .toSet()
        : const <String>{};
    var templatesEcrits = 0;
    var templatesIgnores = 0;
    for (final enregistre in sauvegarde.templates) {
      if (mode == ModeRestauration.fusion) {
        // Meme regle que pour les repas : l'identifiant local l'emporte, et une
        // pierre tombale sans modele local n'apprend rien.
        if (idsTemplates.contains(enregistre.template.id) ||
            enregistre.estSupprime) {
          templatesIgnores++;
          continue;
        }
      }
      await _database.restaurerTemplate(enregistre);
      templatesEcrits++;
    }

    final idsFavoris = mode == ModeRestauration.fusion
        ? (await _database.favoritesPourSauvegarde())
              .map((f) => f.favorite.id)
              .toSet()
        : const <String>{};
    var favoritesEcrits = 0;
    var favoritesIgnores = 0;
    for (final enregistre in sauvegarde.favorites) {
      if (mode == ModeRestauration.fusion) {
        if (idsFavoris.contains(enregistre.favorite.id) ||
            enregistre.estSupprime) {
          favoritesIgnores++;
          continue;
        }
      }
      await _database.restaurerFavorite(enregistre);
      favoritesEcrits++;
    }

    // Suivi du poids : memes regles que les repas, et pour la meme raison. En
    // fusion, un identifiant deja present l'emporte — y compris s'il a ete
    // supprime ici — et une pierre tombale sans pesee locale n'apprend rien,
    // donc elle n'est pas ecrite.
    final idsPesees = mode == ModeRestauration.fusion
        ? await _database.idsDePesees()
        : const <String>{};
    var peseesEcrites = 0;
    var peseesIgnorees = 0;
    for (final enregistre in sauvegarde.pesees) {
      if (mode == ModeRestauration.fusion) {
        if (idsPesees.contains(enregistre.pesee.id) ||
            enregistre.estSupprimee) {
          peseesIgnorees++;
          continue;
        }
      }
      await _database.restaurerPesee(enregistre);
      peseesEcrites++;
    }

    final idsMesures = mode == ModeRestauration.fusion
        ? await _database.idsDeMesures()
        : const <String>{};
    var mesuresEcrites = 0;
    var mesuresIgnorees = 0;
    for (final enregistre in sauvegarde.mesures) {
      if (mode == ModeRestauration.fusion) {
        if (idsMesures.contains(enregistre.mesure.id) ||
            enregistre.estSupprimee) {
          mesuresIgnorees++;
          continue;
        }
      }
      await _database.restaurerMesure(enregistre);
      mesuresEcrites++;
    }

    // Les portions portent desormais une pierre tombale, comme le reste : une
    // portion supprimee sur un appareil doit pouvoir disparaitre sur l'autre,
    // sinon la synchronisation la ferait revenir. La cle identifie l'aliment,
    // donc une portion deja connue localement n'est jamais ecrasee par une
    // fusion.
    final clesPortions = mode == ModeRestauration.fusion
        ? await _database.clesDePortions()
        : const <String>{};
    var portionsEcrites = 0;
    var portionsIgnorees = 0;
    for (final enregistre in sauvegarde.portions) {
      if (mode == ModeRestauration.fusion) {
        if (clesPortions.contains(enregistre.cle) || enregistre.estSupprimee) {
          portionsIgnorees++;
          continue;
        }
      }
      await _database.restaurerPortion(enregistre);
      portionsEcrites++;
    }

    var reglagesEcrits = 0;
    var reglagesIgnores = 0;
    final aEcrire = <String, String>{};
    if (mode == ModeRestauration.remplacement) {
      aEcrire.addAll(sauvegarde.settings);
      reglagesEcrits = sauvegarde.settings.length;
    } else {
      final existants = await _database.settingsPourSauvegarde();
      for (final entree in sauvegarde.settings.entries) {
        if (existants.containsKey(entree.key)) {
          reglagesIgnores++;
        } else {
          aEcrire[entree.key] = entree.value;
          reglagesEcrits++;
        }
      }
    }
    if (aEcrire.isNotEmpty) {
      await _database.ecrireSettings(aEcrire);
    }

    return RapportRestauration(
      mode: mode,
      mealsEcrits: mealsEcrits,
      mealsIgnores: mealsIgnores,
      templatesEcrits: templatesEcrits,
      templatesIgnores: templatesIgnores,
      favoritesEcrits: favoritesEcrits,
      favoritesIgnores: favoritesIgnores,
      reglagesEcrits: reglagesEcrits,
      reglagesIgnores: reglagesIgnores,
      photosPerdues: photosPerdues,
      peseesEcrites: peseesEcrites,
      peseesIgnorees: peseesIgnorees,
      mesuresEcrites: mesuresEcrites,
      mesuresIgnorees: mesuresIgnorees,
      portionsEcrites: portionsEcrites,
      portionsIgnorees: portionsIgnorees,
    );
  }

  /// Ecarte la photo d'un repas si son fichier n'existe pas sur cet appareil.
  ///
  /// Rend le repas inchange lorsque la photo est bien la, ce qui evite de
  /// reconstruire un objet identique. Un chemin mort vaut moins qu'une absence :
  /// l'interface afficherait une vignette vide sans pouvoir expliquer pourquoi.
  ({Meal meal, bool photoPerdue}) _sansPhotoAbsente(Meal meal) {
    final chemin = meal.photoPath;
    if (chemin == null || chemin.isEmpty) {
      return (meal: meal, photoPerdue: false);
    }
    if (File(chemin).existsSync()) {
      return (meal: meal, photoPerdue: false);
    }

    return (
      meal: Meal(
        id: meal.id,
        eatenAt: meal.eatenAt,
        name: meal.name,
        items: meal.items,
        source: meal.source,
        notes: meal.notes,
        photoPath: null,
        isEstimate: meal.isEstimate,
      ),
      photoPerdue: true,
    );
  }
}
