import 'package:assiette/data/distant/correspondance_distant.dart';
import 'package:assiette/data/local/app_database.dart';
import 'package:assiette/data/local/synchronisation_locale.dart';
import 'package:assiette/models/synchronisation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Les colonnes dont la valeur reste sur cet appareil
/// ---------------------------------------------------
/// `meals.photo_path` porte un **chemin absolu** dans le dossier de documents
/// du telephone, compose par `services/image_service.dart`. Il a beau exister
/// des deux cotes du schema, il n'est pas transportable : l'appareil d'a cote
/// n'a pas ce fichier.
///
/// Ce fichier eprouve les deux moities de la decision, et il faut les deux :
///
///  - la lecture **n'emet pas** la colonne, donc elle ne part jamais ;
///  - l'ecriture **relit** la valeur locale et la remet, donc elle ne revient
///    jamais — `insert` avec `ConflictAlgorithm.replace` supprime la ligne, et
///    une colonne absente du contenu retomberait a `NULL`.
///
/// La seconde moitie est celle qui se voit le moins : sans elle, la photo de
/// l'utilisateur disparait a chaque synchronisation, sans erreur, sans trace, et
/// sans qu'aucun des tests de `synchronisation_locale_test.dart` ne tombe —
/// puisque ces tests-la comparent des empreintes, pas des fichiers.
///
/// Ce fichier a sa propre fixture plutot que de partager celle de
/// `synchronisation_locale_test.dart`, et c'est delibere : il est la cible d'un
/// banc de falsification, et un banc epingle le **nombre** de tests de son
/// fichier. Y ajouter un cas casserait le banc voisin, qui aurait alors l'air
/// d'accuser le depot.
void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase base;
  late Database db;

  const cheminPhoto = '/data/user/0/fr.assiette/files/meal_photos/m1.jpg';

  setUp(() async {
    base = AppDatabase(
      factory: databaseFactoryFfi,
      customPath: inMemoryDatabasePath,
    );
    await base.open();
    db = base.db;
    await db.insert('meals', {
      'id': 'm1',
      'eaten_at': 1000,
      'name': 'Repas',
      'source': 'photo',
      'notes': 'une note',
      'photo_path': cheminPhoto,
      'is_estimate': 1,
      'created_at': 900,
      'updated_at': 1000,
      'deleted_at': null,
    });
  });

  tearDown(() => base.close());

  /// Une version distante complete : tout ce que le schema declare obligatoire,
  /// et surtout **pas** de photo.
  LigneSynchronisable venueDAilleurs({String nom = 'Repas venu d\'ailleurs'}) =>
      LigneSynchronisable(
        cle: 'm1',
        updatedAt: 5000,
        contenu: {
          'eaten_at': 1000,
          'name': nom,
          'source': 'photo',
          'notes': null,
          'is_estimate': 1,
          'created_at': 900,
        },
      );

  group('La declaration est nommee, et coherente', () {
    test('la photo d\'un repas y figure', () {
      expect(colonnesLocalesSeulesDe('meals'), contains('photo_path'));
    });

    test('une colonne locale ne peut pas etre aussi datee ou booleenne', () {
      // Une colonne a la fois retenue sur l'appareil et declaree datee serait
      // une contradiction : elle ne serait ni transportee, ni convertie — et
      // deux declarations opposees se masqueraient l'une l'autre.
      for (final entree in colonnesLocalesSeules.entries) {
        expect(
          tablesDistantes,
          contains(entree.key),
          reason: '${entree.key} est declaree local sans etre une table connue',
        );
        expect(
          (colonnesDatesDistantes[entree.key] ?? const <String>{}).intersection(
            entree.value,
          ),
          isEmpty,
          reason: '${entree.key} : locale et datee a la fois',
        );
        expect(
          (colonnesBooleennesDistantes[entree.key] ?? const <String>{})
              .intersection(entree.value),
          isEmpty,
          reason: '${entree.key} : locale et booleenne a la fois',
        );
      }
    });
  });

  group('La lecture n\'emet pas la colonne', () {
    test('le contenu d\'un repas ne porte pas le chemin de sa photo', () async {
      final ligne = (await lireLignes(db, _repas())).single;
      expect(ligne.contenu, isNot(contains('photo_path')));
      // Le reste du repas est bien la : l'exclusion porte sur une colonne
      // nommee, pas sur la ligne entiere.
      expect(ligne.contenu['name'], 'Repas');
      expect(ligne.contenu['notes'], 'une note');
    });

    test('changer la photo seule ne fait pas bouger l\'empreinte', () async {
      // La consequence assumee : la photo ne fait pas partie de l'identite d'un
      // repas pour la synchronisation. Deux appareils qui ont le meme repas et
      // chacun sa photo sont **d'accord** — c'est ce qu'on veut, sinon chaque
      // passage renverrait la ligne dans les deux sens.
      final avant = (await lireLignes(db, _repas())).single;
      await db.update(
        'meals',
        {'photo_path': '/photos/autre.jpg'},
        where: 'id = ?',
        whereArgs: ['m1'],
      );
      final apres = (await lireLignes(db, _repas())).single;
      expect(apres.version.empreinte, avant.version.empreinte);
      expect(apres.contenu, isNot(contains('photo_path')));
    });
  });

  group('L\'ecriture preserve la valeur locale', () {
    test('une ligne distante n\'efface pas la photo locale', () async {
      await ecrireLigne(db, _repas(), venueDAilleurs());

      final relue = (await db.query(
        'meals',
        where: 'id = ?',
        whereArgs: ['m1'],
      )).single;
      expect(relue['photo_path'], cheminPhoto);
      // Et la version distante a bien ete appliquee, sinon le test passerait en
      // n'ayant rien ecrit.
      expect(relue['name'], 'Repas venu d\'ailleurs');
      expect(relue['updated_at'], 5000);
    });

    test('un repas inconnu localement arrive sans photo', () async {
      // Rien a relire : cet appareil n'a pas cette photo. Une valeur nulle est
      // exacte — inventer un chemin serait pire que l'absence.
      await ecrireLigne(
        db,
        _repas(),
        LigneSynchronisable(
          cle: 'm9',
          updatedAt: 5000,
          contenu: {
            'eaten_at': 1000,
            'name': 'Ailleurs',
            'source': 'photo',
            'notes': null,
            'is_estimate': 1,
            'created_at': 900,
          },
        ),
      );
      final relue = (await db.query(
        'meals',
        where: 'id = ?',
        whereArgs: ['m9'],
      )).single;
      expect(relue['photo_path'], isNull);
      expect(relue['name'], 'Ailleurs');
    });

    test('une ligne sans photo locale reste sans photo', () async {
      // Le cas oppose du premier : la preservation ne doit pas **inventer** une
      // valeur quand il n'y en a pas. Un `photo_path` remonte du contenu
      // distant serait exactement le defaut qu'on ferme.
      await db.update(
        'meals',
        {'photo_path': null},
        where: 'id = ?',
        whereArgs: ['m1'],
      );
      await ecrireLigne(db, _repas(), venueDAilleurs(nom: 'Sans photo'));

      final relue = (await db.query(
        'meals',
        where: 'id = ?',
        whereArgs: ['m1'],
      )).single;
      expect(relue['photo_path'], isNull);
      expect(relue['name'], 'Sans photo');
    });
  });
}

TableSynchronisable _repas() =>
    tablesSynchronisables.firstWhere((table) => table.nom == 'meals');
