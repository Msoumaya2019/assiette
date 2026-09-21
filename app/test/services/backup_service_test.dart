import 'dart:convert';
import 'dart:io';

import 'package:assiette/data/local/app_database.dart';
import 'package:assiette/models/food.dart';
import 'package:assiette/models/meal.dart';
import 'package:assiette/models/nutrition_values.dart';
import 'package:assiette/models/portion.dart';
import 'package:assiette/models/sauvegarde.dart';
import 'package:assiette/models/suivi_poids.dart';
import 'package:assiette/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Aliments de test. Les valeurs sont rondes pour que les attentes se verifient
/// de tete, et les provenances differentes parce que c'est la provenance qui
/// doit survivre a un aller-retour de sauvegarde.
const riz = Food(
  name: 'Riz blanc cuit',
  per100g: NutritionValues(
    kcal: 130,
    carbs: 28,
    sugars: 0.1,
    starch: 27,
    protein: 2.7,
    fat: 0.3,
    saturatedFat: 0.1,
    fiber: 0.4,
    salt: 0.01,
  ),
  source: FoodSource.ciqual,
  sourceRef: '9100',
);

const yaourt = Food(
  name: 'Yaourt nature',
  per100g: NutritionValues(
    kcal: 60,
    carbs: 4.5,
    sugars: 4.5,
    protein: 4,
    fat: 3,
    saturatedFat: 2,
    salt: 0.1,
  ),
  source: FoodSource.openFoodFacts,
  sourceRef: '3033490005247',
  brand: 'Marque Test',
);

Meal repas(
  DateTime at,
  List<MealItem> items, {
  String name = 'Repas',
  MealSource source = MealSource.manual,
  String? photoPath,
  bool isEstimate = false,
}) => Meal(
  eatenAt: at,
  name: name,
  items: items,
  source: source,
  isEstimate: isEstimate,
  photoPath: photoPath,
);

/// Ouvre une base neuve sur SQLite natif.
///
/// Le chemin est un **fichier** et non `inMemoryDatabasePath` : deux ouvertures
/// du meme chemin rendent la meme base. Mesure faite — avec `:memory:` des deux
/// cotes, la source et la cible etaient une seule et meme base, et les tests de
/// fusion lisaient dans la cible ce que la source venait d'y ecrire. Le defaut
/// se lisait « la fusion ignore un repas » alors qu'il n'y avait qu'une base.
Future<AppDatabase> baseNeuve(String nom) async {
  final base = AppDatabase(
    factory: databaseFactoryFfi,
    customPath: p.join(repertoireDesBases.path, '$nom.db'),
  );
  await base.open();
  return base;
}

/// Dossier ou sont posees les bases de test, cree avant toute ouverture.
late Directory repertoireDesBases;

void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase source;
  late AppDatabase cible;
  late Directory temporaire;
  late BackupService service;

  setUp(() async {
    repertoireDesBases = Directory.systemTemp.createTempSync('assiette-bases');
    temporaire = Directory.systemTemp.createTempSync('assiette-sauvegarde');
    source = await baseNeuve('source');
    cible = await baseNeuve('cible');
    service = BackupService(
      database: source,
      appVersion: '0.1.2+6',
      dossier: () async => temporaire,
    );
  });

  tearDown(() async {
    await source.close();
    await cible.close();
    if (temporaire.existsSync()) temporaire.deleteSync(recursive: true);
    if (repertoireDesBases.existsSync()) {
      repertoireDesBases.deleteSync(recursive: true);
    }
  });

  /// Un service branche sur une autre base, pour restaurer ailleurs.
  BackupService vers(AppDatabase autre) => BackupService(
    database: autre,
    appVersion: '0.1.2+6',
    dossier: () async => temporaire,
  );

  group('Aller-retour', () {
    test('un repas traverse la sauvegarde sans rien perdre', () async {
      final original = repas(
        DateTime(2026, 9, 18, 12, 30),
        [
          MealItem(food: riz, quantityG: 150, confidence: 0.8),
          MealItem(
            food: yaourt,
            quantityG: 125,
            portionSize: PortionSize.small,
          ),
        ],
        name: 'Dejeuner',
        source: MealSource.photo,
        isEstimate: true,
      )..notes = 'Pris au restaurant';
      await source.saveMeal(original);

      final texte = await service.exporter();
      final lue = SauvegardeLue.depuisTexte(texte);
      final rapport = await vers(
        cible,
      ).restaurer(lue, mode: ModeRestauration.remplacement);

      expect(rapport.mealsEcrits, 1);
      final relu = await cible.mealById(original.id);

      expect(relu, isNotNull, reason: 'l\'identifiant d\'origine est conserve');
      expect(relu!.name, 'Dejeuner');
      expect(relu.eatenAt, DateTime(2026, 9, 18, 12, 30));
      expect(relu.source, MealSource.photo);
      expect(relu.isEstimate, isTrue);
      expect(relu.notes, 'Pris au restaurant');

      expect(relu.items.map((i) => i.food.name), [
        'Riz blanc cuit',
        'Yaourt nature',
      ]);
      expect(relu.items.first.quantityG, 150);
      expect(relu.items.first.confidence, 0.8);
      expect(relu.items[1].portionSize, PortionSize.small);

      // Les valeurs pour 100 g sont stockees : elles doivent revenir a
      // l'identique, sinon le total serait faux sans que rien ne le signale.
      expect(relu.items.first.food.per100g.carbs, 28);
      expect(relu.items.first.food.per100g.starch, 27);
      expect(relu.items.first.food.per100g.salt, 0.01);
      expect(relu.items[1].food.per100g.sugars, 4.5);
    });

    test('le total de glucides est identique avant et apres', () async {
      // C'est la mesure qui compte pour l'utilisateur : les glucides. Un
      // aller-retour qui les modifierait, meme de peu, rendrait la sauvegarde
      // trompeuse.
      final original = repas(DateTime(2026, 9, 18), [
        MealItem(food: riz, quantityG: 137),
        MealItem(food: yaourt, quantityG: 83),
      ]);
      await source.saveMeal(original);

      final avant = (await source.mealById(original.id))!.totals;
      final lue = SauvegardeLue.depuisTexte(await service.exporter());
      await vers(cible).restaurer(lue, mode: ModeRestauration.remplacement);
      final apres = (await cible.mealById(original.id))!.totals;

      expect(apres.carbs, avant.carbs);
      expect(apres.kcal, avant.kcal);
      expect(apres.protein, avant.protein);
    });

    test('la provenance de chaque aliment survit', () async {
      // Exigence de conception : l'interface doit pouvoir dire d'ou vient une
      // valeur. Une sauvegarde qui perdrait `source` et `sourceRef` ferait
      // passer une estimation pour une donnee de reference.
      final original = repas(DateTime(2026, 9, 18), [
        MealItem(food: riz, quantityG: 100),
        MealItem(food: yaourt, quantityG: 100),
      ]);
      await source.saveMeal(original);

      final lue = SauvegardeLue.depuisTexte(await service.exporter());
      await vers(cible).restaurer(lue, mode: ModeRestauration.remplacement);

      final relu = (await cible.mealById(original.id))!;
      final premier = relu.items.firstWhere(
        (i) => i.food.name == 'Riz blanc cuit',
      );
      final second = relu.items.firstWhere(
        (i) => i.food.name == 'Yaourt nature',
      );

      expect(premier.food.source, FoodSource.ciqual);
      expect(premier.food.sourceRef, '9100');
      expect(second.food.source, FoodSource.openFoodFacts);
      expect(second.food.sourceRef, '3033490005247');
      expect(second.food.brand, 'Marque Test');
    });

    test('les favoris et les repas enregistres reviennent aussi', () async {
      await source.addFavorite('fav-1', 'food', 'Riz blanc cuit', {
        'food': riz.toJson(),
      });
      await source.saveTemplate('tpl-1', 'Petit dejeuner', [
        MealItem(food: yaourt, quantityG: 125),
      ]);

      final lue = SauvegardeLue.depuisTexte(await service.exporter());
      final rapport = await vers(
        cible,
      ).restaurer(lue, mode: ModeRestauration.remplacement);

      expect(rapport.favoritesEcrits, 1);
      expect(rapport.templatesEcrits, 1);

      final favoris = await cible.favorites();
      expect(favoris.single.id, 'fav-1');
      expect(favoris.single.label, 'Riz blanc cuit');
      expect(favoris.single.asFood?.sourceRef, '9100');

      final modeles = await cible.templates();
      expect(modeles.single.id, 'tpl-1');
      expect(modeles.single.name, 'Petit dejeuner');
      expect(modeles.single.items.single.food.name, 'Yaourt nature');
    });

    test('les reglages reviennent', () async {
      await source.writeSetting('theme_mode', 'dark');
      await source.writeSetting('daily_goals', '{"carbs":210}');

      final lue = SauvegardeLue.depuisTexte(await service.exporter());
      await vers(cible).restaurer(lue, mode: ModeRestauration.remplacement);

      expect(await cible.readSetting('theme_mode'), 'dark');
      expect(await cible.readSetting('daily_goals'), '{"carbs":210}');
    });
  });

  group('Suppressions', () {
    test('un repas supprime reste supprime apres restauration', () async {
      // Sans les pierres tombales, un repas efface reviendrait a la
      // restauration : l'utilisateur verrait reapparaitre ce qu'il a efface.
      final original = repas(DateTime(2026, 9, 18), [
        MealItem(food: riz, quantityG: 100),
      ]);
      await source.saveMeal(original);
      await source.deleteMeal(original.id);

      final lue = SauvegardeLue.depuisTexte(await service.exporter());
      expect(lue.mealsSupprimes, 1, reason: 'la pierre tombale est exportee');

      await vers(cible).restaurer(lue, mode: ModeRestauration.remplacement);

      expect(await cible.mealById(original.id), isNull);
      expect(await cible.idsDeMeals(), contains(original.id));
      expect(await cible.recentMeals(), isEmpty);
    });

    test('le compte annonce separe les repas vivants des supprimes', () async {
      await source.saveMeal(
        repas(DateTime(2026, 9, 18), [MealItem(food: riz, quantityG: 100)]),
      );
      final supprime = repas(DateTime(2026, 9, 17), [
        MealItem(food: riz, quantityG: 100),
      ]);
      await source.saveMeal(supprime);
      await source.deleteMeal(supprime.id);

      final json = jsonDecode(await service.exporter()) as Map<String, dynamic>;
      final compte = json['compte'] as Map<String, dynamic>;

      expect(compte['meals'], 1);
      expect(compte['mealsSupprimes'], 1);
    });
  });

  group('Fusion', () {
    test('une fusion n\'efface rien et n\'ecrase rien', () async {
      // La regle annoncee a l'utilisateur : le pire resultat possible est
      // « rien n'a change ». Un repas local modifie apres la sauvegarde doit
      // survivre a la fusion.
      final commun = repas(DateTime(2026, 9, 18), [
        MealItem(food: riz, quantityG: 100),
      ], name: 'Dejeuner');
      await source.saveMeal(commun);

      // La cible connait le meme identifiant, avec un contenu different : c'est
      // le cas d'un appareil ou l'utilisateur a corrige la portion.
      await cible.saveMeal(
        Meal(
          id: commun.id,
          eatenAt: DateTime(2026, 9, 18),
          name: 'Dejeuner modifie',
          items: [MealItem(food: riz, quantityG: 250)],
        ),
      );
      // Et un repas qui n'existe que localement.
      await cible.saveMeal(
        repas(DateTime(2026, 9, 16), [
          MealItem(food: yaourt, quantityG: 125),
        ], name: 'Local'),
      );

      final lue = SauvegardeLue.depuisTexte(await service.exporter());
      final rapport = await vers(
        cible,
      ).restaurer(lue, mode: ModeRestauration.fusion);

      expect(rapport.mealsEcrits, 0);
      expect(rapport.mealsIgnores, 1);

      final apres = await cible.recentMeals();
      expect(apres.length, 2, reason: 'le repas local est intact');
      expect(
        apres.firstWhere((m) => m.id == commun.id).items.single.quantityG,
        250,
        reason: 'le contenu local gagne',
      );
      expect(apres.map((m) => m.name), contains('Local'));
    });

    test('une fusion ajoute ce qui manque', () async {
      await source.saveMeal(
        repas(DateTime(2026, 9, 18), [
          MealItem(food: riz, quantityG: 100),
        ], name: 'Depuis la sauvegarde'),
      );

      final lue = SauvegardeLue.depuisTexte(await service.exporter());
      final rapport = await vers(
        cible,
      ).restaurer(lue, mode: ModeRestauration.fusion);

      expect(rapport.mealsEcrits, 1);
      final apres = await cible.recentMeals();
      expect(apres.single.name, 'Depuis la sauvegarde');
    });

    test('une fusion ne ressuscite pas un repas supprime ici', () async {
      final commun = repas(DateTime(2026, 9, 18), [
        MealItem(food: riz, quantityG: 100),
      ]);
      await source.saveMeal(commun);
      await cible.saveMeal(
        Meal(
          id: commun.id,
          eatenAt: DateTime(2026, 9, 18),
          name: 'Repas',
          items: [MealItem(food: riz, quantityG: 100)],
        ),
      );
      await cible.deleteMeal(commun.id);

      final lue = SauvegardeLue.depuisTexte(await service.exporter());
      await vers(cible).restaurer(lue, mode: ModeRestauration.fusion);

      expect(
        await cible.mealById(commun.id),
        isNull,
        reason: 'la suppression locale l\'emporte',
      );
    });

    test('une fusion n\'ecrit pas de pierre tombale isolee', () async {
      // Une suppression sauvegardee dont le repas n'existe pas ici n'apprend
      // rien : il n'y a rien a supprimer.
      final supprime = repas(DateTime(2026, 9, 17), [
        MealItem(food: riz, quantityG: 100),
      ]);
      await source.saveMeal(supprime);
      await source.deleteMeal(supprime.id);

      final lue = SauvegardeLue.depuisTexte(await service.exporter());
      final rapport = await vers(
        cible,
      ).restaurer(lue, mode: ModeRestauration.fusion);

      expect(rapport.mealsEcrits, 0);
      expect(rapport.mealsIgnores, 1);
      expect(await cible.idsDeMeals(), isEmpty);
    });
  });

  group('Secrets', () {
    test('une cle sensible n\'est jamais ecrite dans le fichier', () async {
      // La cle du fournisseur vit dans le trousseau du systeme, pas dans la
      // base. Ce test verrouille la regle : meme ajoutee par erreur dans les
      // reglages, elle ne doit pas sortir dans un fichier en clair.
      await source.writeSetting('theme_mode', 'dark');
      await source.writeSetting(
        'provider_api_key',
        'sk-secret-a-ne-pas-exporter',
      );
      await source.writeSetting('sync_token', 'jeton-confidentiel');

      final texte = await service.exporter();

      expect(texte.contains('sk-secret-a-ne-pas-exporter'), isFalse);
      expect(texte.contains('jeton-confidentiel'), isFalse);
      // Le fichier nomme les cles ecartees : un oubli se voit au lieu de se
      // deviner.
      final json = jsonDecode(texte) as Map<String, dynamic>;
      expect((json['reglagesExclus'] as List).cast<String>()..sort(), [
        'provider_api_key',
        'sync_token',
      ]);
      // Les autres reglages, eux, partent bien.
      expect((json['settings'] as Map)['theme_mode'], 'dark');
    });

    test('le motif des cles sensibles ne confond pas un reglage ordinaire', () {
      for (final ordinaire in [
        'theme_mode',
        'analysis_mode',
        'onboarding_done',
        'keep_photos',
        'meal_reminders',
        'daily_summary',
        'reminder_hour',
        'reminder_minute',
        'disclaimer_seen',
        'privacy_version',
        'daily_goals',
      ]) {
        expect(
          BackupService.motifSensible.hasMatch(ordinaire),
          isFalse,
          reason: '$ordinaire ne doit pas etre exclu',
        );
      }
      for (final sensible in ['provider_api_key', 'sync_token', 'password']) {
        expect(
          BackupService.motifSensible.hasMatch(sensible),
          isTrue,
          reason: '$sensible doit etre exclu',
        );
      }
    });
  });

  group('Photos', () {
    test('une photo disparue est retiree et annoncee', () async {
      final original = repas(DateTime(2026, 9, 18), [
        MealItem(food: riz, quantityG: 100),
      ], photoPath: p.join(temporaire.path, 'photo-qui-nexiste-pas.jpg'));
      await source.saveMeal(original);

      final texte = await service.exporter();
      final json = jsonDecode(texte) as Map<String, dynamic>;
      expect(
        json['photosAbsentes'],
        1,
        reason: 'la sauvegarde annonce la photo qu\'elle n\'emporte pas',
      );

      final rapport = await vers(cible).restaurer(
        SauvegardeLue.depuisTexte(texte),
        mode: ModeRestauration.remplacement,
      );

      expect(rapport.photosPerdues, 1);
      final relu = await cible.mealById(original.id);
      expect(
        relu!.photoPath,
        isNull,
        reason: 'mieux vaut aucune photo qu\'un chemin mort',
      );
      expect(rapport.resume, contains('photo'));
    });

    test('une photo presente est conservee', () async {
      final fichier = File(p.join(temporaire.path, 'photo.jpg'))
        ..writeAsBytesSync([1, 2, 3]);
      final original = repas(DateTime(2026, 9, 18), [
        MealItem(food: riz, quantityG: 100),
      ], photoPath: fichier.path);
      await source.saveMeal(original);

      final rapport = await vers(cible).restaurer(
        SauvegardeLue.depuisTexte(await service.exporter()),
        mode: ModeRestauration.remplacement,
      );

      expect(rapport.photosPerdues, 0);
      expect((await cible.mealById(original.id))!.photoPath, fichier.path);
    });
  });

  group('Fichier', () {
    test('le fichier ecrit porte la date dans son nom', () async {
      final fichier = await service.ecrireFichier(
        await service.exporter(),
        maintenant: DateTime(2026, 9, 19, 8, 5),
      );

      expect(p.basename(fichier.path), 'assiette-20260919-0805.json');
      expect(fichier.existsSync(), isTrue);
      expect(
        p.basename(fichier.parent.path),
        BackupService.sousDossier,
        reason: 'les sauvegardes sont rangees dans leur propre dossier',
      );
      // Le fichier doit etre relisible tel quel.
      expect(
        SauvegardeLue.depuisTexte(fichier.readAsStringSync()).meals,
        isEmpty,
      );
    });

    test('deux sauvegardes successives ne s\'ecrasent pas', () async {
      final premiere = await service.ecrireFichier(
        await service.exporter(),
        maintenant: DateTime(2026, 9, 19, 8, 5),
      );
      final seconde = await service.ecrireFichier(
        await service.exporter(),
        maintenant: DateTime(2026, 9, 19, 8, 6),
      );

      expect(premiere.path, isNot(seconde.path));
      expect(premiere.existsSync(), isTrue);
      expect(seconde.existsSync(), isTrue);
    });
  });

  group('Refus', () {
    /// Chaque refus doit nommer sa cause : « fichier invalide » laisserait
    /// l'utilisateur sans moyen de savoir s'il s'est trompe de fichier, si le
    /// fichier est abime, ou s'il vient d'une version trop recente.
    void refuse(String libelle, String texte, String attendu) {
      test(libelle, () {
        expect(
          () => SauvegardeLue.depuisTexte(texte),
          throwsA(
            isA<SauvegardeIllisible>().having(
              (e) => e.toString(),
              'message',
              contains(attendu),
            ),
          ),
        );
      });
    }

    refuse('texte qui n\'est pas du JSON', 'ceci n\'est pas du json', 'JSON');
    refuse(
      'JSON qui n\'est pas une sauvegarde',
      '[1, 2, 3]',
      'ne contient pas une sauvegarde',
    );
    refuse(
      'fichier d\'une autre application',
      '{"format":"autre.app","formatVersion":1}',
      'n\'est pas une sauvegarde Assiette',
    );
    refuse(
      'version de format future',
      '{"format":"assiette.sauvegarde","formatVersion":99}',
      'version plus recente',
    );
    refuse(
      'version de format absente',
      '{"format":"assiette.sauvegarde"}',
      'version du format',
    );
    refuse(
      'liste de repas tronquee',
      '{"format":"assiette.sauvegarde","formatVersion":1,"meals":{}}',
      'ne forment pas une liste',
    );
    refuse(
      'repas qui n\'est pas un objet',
      '{"format":"assiette.sauvegarde","formatVersion":1,"meals":[7]}',
      'n\'est pas un objet',
    );

    test('une liste vide est acceptee, pas refusee', () {
      // Un fichier sans donnees est valide : c'est le cas d'une installation
      // ou l'utilisateur n'a encore rien enregistre. Le confondre avec un
      // fichier abime ferait echouer une sauvegarde legitime.
      final lue = SauvegardeLue.depuisTexte(
        '{"format":"assiette.sauvegarde","formatVersion":1}',
      );
      expect(lue.meals, isEmpty);
      expect(lue.templates, isEmpty);
      expect(lue.favorites, isEmpty);
      expect(lue.mealsVivants, 0);
    });

    test('un format d\'une version anterieure reste lisible', () {
      // La compatibilite descendante est la raison d'etre du numero de format :
      // refuser un format 1 ancien rendrait inutiles les sauvegardes deja faites.
      final lue = SauvegardeLue.depuisTexte(
        '{"format":"assiette.sauvegarde","formatVersion":1,'
        '"meals":[{"id":"m1","eatenAt":"2026-09-18T12:00:00.000",'
        '"name":"Repas","items":[],"source":"manual","isEstimate":true}]}',
      );
      expect(lue.mealsVivants, 1);
      expect(lue.meals.single.meal.id, 'm1');
      expect(lue.meals.single.createdAt, 0, reason: 'horodatage absent tolere');
    });
  });

  group('Suivi du poids', () {
    test('les pesees et les mesures font un aller-retour', () async {
      await source.savePesee(
        Pesee(id: 'p1', le: DateTime(2026, 9, 10), poidsKg: 71, note: 'a jeun'),
      );
      await source.savePesee(
        Pesee(id: 'p2', le: DateTime(2026, 9, 12), poidsKg: 70.4),
      );
      await source.saveMesure(
        Mesure(
          id: 'm1',
          le: DateTime(2026, 9, 12),
          type: TypeMesure.taille,
          valeurCm: 82,
        ),
      );
      await source.writeObjectifPoids(const ObjectifPoids(cibleKg: 68));

      final lue = SauvegardeLue.depuisTexte(await service.exporter());
      expect(lue.peseesVivantes, 2);
      expect(lue.mesuresVivantes, 1);

      final rapport = await vers(
        cible,
      ).restaurer(lue, mode: ModeRestauration.remplacement);

      expect(rapport.peseesEcrites, 2);
      expect(rapport.mesuresEcrites, 1);

      final pesees = await cible.pesees();
      expect(pesees, hasLength(2));
      expect(pesees.first.poidsKg, 70.4);
      expect(pesees.last.note, 'a jeun');
      expect((await cible.mesures()).single.valeurCm, 82);

      // L'objectif vit dans les reglages : il suit le bloc `settings`, et une
      // seconde place dans le fichier creerait deux sources pour la meme
      // valeur.
      expect((await cible.readObjectifPoids()).cibleKg, 68);
    });

    test('une pesee supprimee reste supprimee apres restauration', () async {
      await source.savePesee(
        Pesee(id: 'p1', le: DateTime(2026, 9, 10), poidsKg: 71),
      );
      await source.savePesee(
        Pesee(id: 'p2', le: DateTime(2026, 9, 12), poidsKg: 70),
      );
      await source.deletePesee('p2');

      final lue = SauvegardeLue.depuisTexte(await service.exporter());
      expect(lue.peseesVivantes, 1);
      expect(lue.peseesSupprimees, 1);

      await vers(cible).restaurer(lue, mode: ModeRestauration.remplacement);

      // La pierre tombale a voyage : la pesee supprimee ne reapparait pas.
      expect((await cible.pesees()).map((p) => p.id), ['p1']);
    });

    test('une fusion n\'ecrase aucune pesee existante', () async {
      await source.savePesee(
        Pesee(id: 'p1', le: DateTime(2026, 9, 10), poidsKg: 71),
      );
      await cible.savePesee(
        Pesee(id: 'p1', le: DateTime(2026, 9, 10), poidsKg: 99),
      );

      final lue = SauvegardeLue.depuisTexte(await service.exporter());
      final rapport = await vers(
        cible,
      ).restaurer(lue, mode: ModeRestauration.fusion);

      expect(rapport.peseesEcrites, 0);
      expect(rapport.peseesIgnorees, 1);
      expect((await cible.pesees()).single.poidsKg, 99);
    });

    test(
      'les pesees d\'une sauvegarde ancienne sont simplement absentes',
      () async {
        // Une sauvegarde produite avant cette fonctionnalite n'a pas de section
        // `pesees` : la lire ne doit rien casser.
        final lue = SauvegardeLue.depuisTexte(
          '{"format":"assiette.sauvegarde","formatVersion":1}',
        );
        expect(lue.pesees, isEmpty);
        expect(lue.mesures, isEmpty);
        expect(lue.portions, isEmpty);
      },
    );

    test('une pesee illisible fait refuser le fichier, en le disant', () async {
      final texte = await service.exporter();
      final json = jsonDecode(texte) as Map<String, dynamic>;
      json['pesees'] = [
        {'id': 'p1', 'le': '2026-09-10T00:00:00.000'},
      ];

      expect(
        () => SauvegardeLue.depuisTexte(jsonEncode(json)),
        throwsA(
          isA<SauvegardeIllisible>().having(
            (e) => e.toString(),
            'message',
            contains('pesee'),
          ),
        ),
      );
    });
  });

  group('Portions retenues', () {
    test('les portions retenues voyagent avec la sauvegarde', () async {
      await source.writePortion(
        'ciqual:9100',
        const Portion(label: 'part', grams: 80),
      );
      await source.writePortion(
        'nom:gateau maison',
        const Portion(label: 'gateau', grams: 65),
      );

      final lue = SauvegardeLue.depuisTexte(await service.exporter());
      expect(lue.portions, hasLength(2));

      await vers(cible).restaurer(lue, mode: ModeRestauration.remplacement);

      final retenue = await cible.readPortion('ciqual:9100');
      expect(retenue, isNotNull);
      expect(retenue!.label, 'part');
      expect(retenue.grams, 80);
      expect((await cible.readPortion('nom:gateau maison'))!.grams, 65);
    });

    test('la portion d\'un aliment voyage avec son repas', () async {
      await source.saveMeal(
        repas(DateTime(2026, 9, 18), [
          MealItem(
            food: riz,
            quantityG: 160,
            portion: const Portion(label: 'part', grams: 80),
          ),
        ]),
      );

      final lue = SauvegardeLue.depuisTexte(await service.exporter());
      await vers(cible).restaurer(lue, mode: ModeRestauration.remplacement);

      final aliment = (await cible.recentMeals()).single.items.single;
      expect(aliment.portion, isNotNull);
      expect(aliment.portion!.label, 'part');
      expect(aliment.libellePortion, '2 parts · 160 g');
    });

    test('une fusion ne remplace pas une portion deja connue', () async {
      await source.writePortion(
        'ciqual:9100',
        const Portion(label: 'part', grams: 80),
      );
      await cible.writePortion(
        'ciqual:9100',
        const Portion(label: 'bol', grams: 250),
      );

      final lue = SauvegardeLue.depuisTexte(await service.exporter());
      final rapport = await vers(
        cible,
      ).restaurer(lue, mode: ModeRestauration.fusion);

      expect(rapport.portionsEcrites, 0);
      expect(rapport.portionsIgnorees, 1);
      expect((await cible.readPortion('ciqual:9100'))!.label, 'bol');
    });

    test(
      'une portion malformee est ignoree, sans faire echouer la lecture',
      () async {
        // Une portion sans poids n'a aucun sens : la garder ferait diviser par
        // zero au premier calcul de nombre d'unites.
        final texte = await service.exporter();
        final json = jsonDecode(texte) as Map<String, dynamic>;
        json['portions'] = {
          'bonne': {'label': 'part', 'grams': 80},
          'mauvaise': {'label': 'rien'},
        };

        final lue = SauvegardeLue.depuisTexte(jsonEncode(json));
        expect(lue.portions.keys, ['bonne']);
      },
    );
  });
}
