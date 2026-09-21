import 'package:assiette/data/distant/correspondance_distant.dart';
import 'package:assiette/data/local/app_database.dart';
import 'package:assiette/data/local/synchronisation_locale.dart';
import 'package:assiette/models/empreinte.dart';
import 'package:assiette/models/synchronisation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Une ligne complete par table, avec toutes les colonnes renseignees.
///
/// Ecrites explicitement plutot que construites : c'est le **schema** qu'on
/// interroge, et une fixture generee depuis le code testerait le code.
final Map<String, Map<String, Object?>> _lignes = {
  'meals': {
    'id': 'm1',
    'eaten_at': 1000,
    'name': 'Repas',
    'source': 'photo',
    'notes': 'une note',
    'photo_path': '/photos/m1.jpg',
    'is_estimate': 1,
    'created_at': 900,
    'updated_at': 1000,
    'deleted_at': null,
  },
  'templates': {
    'id': 't1',
    'name': 'Petit-dejeuner',
    'items_json': '[]',
    'created_at': 900,
    'updated_at': 1000,
    'deleted_at': null,
  },
  'favorites': {
    'id': 'f1',
    'kind': 'food',
    'label': 'Riz',
    'payload_json': '{}',
    'created_at': 900,
    'updated_at': 1000,
    'deleted_at': null,
  },
  'pesees': {
    'id': 'p1',
    'mesure_le': 1000,
    'poids_kg': 72.5,
    'note': 'le matin',
    'created_at': 900,
    'updated_at': 1000,
    'deleted_at': null,
  },
  'mesures': {
    'id': 's1',
    'mesure_le': 1000,
    'type': 'taille',
    'valeur_cm': 88.0,
    'created_at': 900,
    'updated_at': 1000,
    'deleted_at': null,
  },
  'portions': {
    'cle': 'nom:gateau',
    'label': 'gateau',
    'grams': 65.0,
    'updated_at': 1000,
    'deleted_at': null,
  },
};

TableSynchronisable _table(String nom) =>
    tablesSynchronisables.firstWhere((table) => table.nom == nom);

/// Une valeur differente de celle fournie, du type declare par le schema.
///
/// Sert au controle **par colonne** : si remplacer la valeur d'une colonne ne
/// change pas l'empreinte, c'est que la colonne n'entre pas dans le contenu — et
/// une modification de cette colonne, seule, serait invisible a la
/// synchronisation.
Object? _autreValeur(String type, Object? actuelle) {
  if (actuelle == null) {
    if (type.contains('INT')) return 42;
    if (type.contains('REAL')) return 4.2;
    return 'autre';
  }
  if (actuelle is int) return actuelle + 1;
  if (actuelle is double) return actuelle + 1;
  if (actuelle is String) return '${actuelle}x';
  return null;
}

Future<void> _peupler(DatabaseExecutor db) async {
  for (final entree in _lignes.entries) {
    await db.insert(entree.key, entree.value);
  }
  await db.insert('meal_items', {
    'id': 'i1',
    'meal_id': 'm1',
    'name': 'Riz',
    'quantity_g': 150.0,
    'kcal_100g': 130.0,
    'carbs_100g': 28.0,
    'sugars_100g': 0.1,
    'starch_100g': 27.0,
    'protein_100g': 2.7,
    'fat_100g': 0.3,
    'sat_fat_100g': 0.1,
    'fiber_100g': 0.4,
    'salt_100g': 0.01,
    'source': 'ciqual',
    'source_ref': '9100',
    'brand': 'marque',
    'image_url': 'https://exemple/riz.jpg',
    'confidence': 0.9,
    'portion': 'medium',
    'portion_label': 'bol',
    'portion_grams': 150.0,
    'is_estimate': 0,
    'sort_order': 0,
  });
}

void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase base;
  late Database db;

  setUp(() async {
    base = AppDatabase(
      factory: databaseFactoryFfi,
      customPath: inMemoryDatabasePath,
    );
    await base.open();
    db = base.db;
    await _peupler(db);
  });

  tearDown(() => base.close());

  group('L\'ensemble des tables est ferme', () {
    // Le meme raisonnement que la liste close des bancs : un ensemble qu'on
    // enumere a la main se perime en silence. Ici, c'est le **schema** qui dit
    // quelles tables doivent etre synchronisees.
    test('toutes les tables declarees existent', () async {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final noms = {for (final ligne in tables) ligne['name'] as String};
      for (final table in tablesSynchronisables) {
        expect(noms, contains(table.nom), reason: table.nom);
      }
    });

    test('aucune table a pierre tombale n\'est oubliee', () async {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final attendues = <String>[];
      for (final ligne in tables) {
        final nom = ligne['name']! as String;
        final colonnes = await colonnesDe(db, nom);
        if (colonnes.contains('updated_at') &&
            colonnes.contains('deleted_at')) {
          attendues.add(nom);
        }
      }
      final declarees = [for (final t in tablesSynchronisables) t.nom];
      expect(attendues..sort(), equals(declarees..sort()));
    });

    test(
      'chaque table declaree a bien une date et une pierre tombale',
      () async {
        for (final table in tablesSynchronisables) {
          final colonnes = await colonnesDe(db, table.nom);
          expect(colonnes, contains('updated_at'), reason: table.nom);
          expect(colonnes, contains('deleted_at'), reason: table.nom);
          expect(colonnes, contains(table.colonneCle), reason: table.nom);
        }
      },
    );
  });

  group('Aucune colonne n\'est perdue en chemin', () {
    test(
      'le contenu porte toutes les colonnes sauf la cle et le service',
      () async {
        for (final table in tablesSynchronisables) {
          final colonnes = await colonnesDe(db, table.nom);
          final localesSeules = colonnesLocalesSeulesDe(table.nom);
          final attendues = colonnes
              .where((c) => c != table.colonneCle)
              .where((c) => !colonnesDeService.contains(c))
              .where((c) => !localesSeules.contains(c))
              .toSet();
          // Un agregat ajoute ses enfants sous une cle qui n'est pas une
          // colonne : c'est le seul ecart admis, et il est nomme ici.
          if (table.enfant != null) attendues.add(cleDesEnfants);
          final lignes = await lireLignes(db, table);
          expect(lignes, hasLength(1), reason: table.nom);
          expect(
            lignes.single.contenu.keys.toSet(),
            attendues,
            reason: table.nom,
          );
        }
      },
    );

    // Le controle qui compte, et il est **par colonne** : un controle qui
    // compterait les colonnes du contenu ne verrait pas qu'une colonne
    // precise a ete oubliee une fois.
    test(
      'changer une seule colonne change l\'empreinte, pour chaque colonne',
      () async {
        for (final table in tablesSynchronisables) {
          final description = await db.rawQuery(
            'PRAGMA table_info(${table.nom})',
          );
          final types = {
            for (final colonne in description)
              colonne['name']! as String: (colonne['type']! as String),
          };
          final ligne = (await lireLignes(db, table)).single;
          final reference = empreinteDeContenu(ligne.contenu);

          // La liste vient du **schema**, pas du contenu. Iterer sur les cles
          // presentes ne verrait jamais une colonne absente — c'est-a-dire
          // exactement le defaut qu'on cherche a attraper. Le controle porte
          // donc sur ce qui **doit** etre la, pas sur ce qui y est.
          //
          // Les colonnes de `colonnesLocalesSeules` sont retirees de la liste
          // parce qu'elles sont exclues **par decision** : leur valeur est
          // propre a l'appareil. Le test suivant verifie qu'elles sont bien
          // exclues, et que la liste des exclusions est exactement celle-la.
          final localesSeules = colonnesLocalesSeulesDe(table.nom);
          final aEssayer =
              (await colonnesDe(db, table.nom))
                  .where((c) => c != table.colonneCle)
                  .where((c) => !colonnesDeService.contains(c))
                  .where((c) => !localesSeules.contains(c))
                  .toList()
                ..sort();
          if (table.enfant != null) aEssayer.add(cleDesEnfants);
          expect(aEssayer, isNotEmpty, reason: table.nom);
          for (final colonne in aEssayer) {
            // La colonne doit d'abord **etre la**. `_autreValeur` sait rendre
            // une valeur pour une cle absente : sans ce controle, ecrire dans
            // une cle absente *ajouterait* une entree au contenu, l'empreinte
            // changerait, et le controle passerait pour la mauvaise raison —
            // precisement en laissant echapper la colonne oubliee. La presence
            // est donc verifiee avant la participation, colonne par colonne.
            expect(
              ligne.contenu.containsKey(colonne),
              isTrue,
              reason:
                  '${table.nom}.$colonne est au schema mais pas dans le '
                  'contenu : une modification de cette colonne seule serait '
                  'invisible a la synchronisation',
            );
            final modifie = Map<String, Object?>.from(ligne.contenu);
            // Les enfants d'un agregat ne sont pas une colonne : leur type est
            // inconnu du schema, et toute valeur differente fait l'affaire.
            modifie[colonne] = _autreValeur(
              types[colonne] ?? '',
              modifie[colonne],
            );
            expect(
              empreinteDeContenu(modifie),
              isNot(reference),
              reason:
                  '${table.nom}.$colonne ne change pas l\'empreinte : une '
                  'modification de cette colonne seule serait invisible',
            );
          }
        }
      },
    );

    test('les colonnes de service ne sont pas dans le contenu', () async {
      for (final table in tablesSynchronisables) {
        final ligne = (await lireLignes(db, table)).single;
        expect(ligne.contenu, isNot(contains('updated_at')), reason: table.nom);
        expect(ligne.contenu, isNot(contains('deleted_at')), reason: table.nom);
        expect(
          ligne.contenu,
          isNot(contains(table.colonneCle)),
          reason: table.nom,
        );
      }
    });

    test('la cle et la date viennent bien des colonnes du schema', () async {
      final lignes = await lireLignes(db, _table('meals'));
      expect(lignes.single.cle, 'm1');
      expect(lignes.single.updatedAt, 1000);
      expect(lignes.single.deletedAt, isNull);
    });

    test('une date absente vaut zero, jamais 1970', () async {
      await db.insert('favorites', {
        'id': 'f2',
        'kind': 'food',
        'label': 'Sans date',
        'payload_json': '{}',
        'created_at': 900,
        'updated_at': null,
        'deleted_at': null,
      });
      final lignes = await lireLignes(db, _table('favorites'));
      final sansDate = lignes.firstWhere((l) => l.cle == 'f2');
      expect(sansDate.updatedAt, 0);
      expect(sansDate.version.dateConnue, isFalse);
    });
  });

  group('Les pierres tombales sont lues comme des lignes', () {
    test('une ligne supprimee est lue, et marquee supprimee', () async {
      await db.update(
        'meals',
        {'deleted_at': 1200, 'updated_at': 1200},
        where: 'id = ?',
        whereArgs: ['m1'],
      );
      final ligne = (await lireLignes(db, _table('meals'))).single;
      expect(ligne.estSupprimee, isTrue);
      expect(ligne.deletedAt, 1200);
    });

    test('supprimer ne fait pas disparaitre la ligne de la lecture', () async {
      await db.delete('templates', where: 'id = ?', whereArgs: ['t1']);
      expect(await lireLignes(db, _table('templates')), isEmpty);
      // La lecture ne fabrique pas de pierre tombale : c'est le role de la
      // suppression logique, faite par l'application, pas celui de la lecture.
    });
  });

  group('Un agregat porte ses aliments', () {
    test('le contenu d\'un repas contient ses aliments', () async {
      final ligne = (await lireLignes(db, _table('meals'))).single;
      expect(ligne.contenu[cleDesEnfants], isA<List>());
      final items = ligne.contenu[cleDesEnfants]! as List;
      expect(items, hasLength(1));
      expect((items.single as Map)['name'], 'Riz');
    });

    test('la colonne de lien n\'est pas repetee dans l\'aliment', () async {
      final ligne = (await lireLignes(db, _table('meals'))).single;
      final item = (ligne.contenu[cleDesEnfants]! as List).single as Map;
      expect(item.containsKey('meal_id'), isFalse);
      expect(item.containsKey('id'), isTrue);
    });

    test(
      'changer la quantite d\'un aliment change l\'empreinte du repas',
      () async {
        final avant = (await lireLignes(db, _table('meals'))).single;
        await db.update(
          'meal_items',
          {'quantity_g': 200.0},
          where: 'id = ?',
          whereArgs: ['i1'],
        );
        final apres = (await lireLignes(db, _table('meals'))).single;
        expect(apres.version.empreinte, isNot(avant.version.empreinte));
      },
    );

    test(
      'un repas sans aliment porte une liste vide, pas une absence',
      () async {
        await db.delete('meal_items', where: 'meal_id = ?', whereArgs: ['m1']);
        final ligne = (await lireLignes(db, _table('meals'))).single;
        expect(ligne.contenu[cleDesEnfants], isEmpty);
      },
    );

    test('les aliments d\'un autre repas ne se melangent pas', () async {
      await db.insert('meals', {..._lignes['meals']!, 'id': 'm2'});
      await db.insert('meal_items', {
        'id': 'i2',
        'meal_id': 'm2',
        'name': 'Pain',
        'quantity_g': 60.0,
        'source': 'manual',
        'sort_order': 0,
      });
      final lignes = await lireLignes(db, _table('meals'));
      final m1 = lignes.firstWhere((l) => l.cle == 'm1');
      final m2 = lignes.firstWhere((l) => l.cle == 'm2');
      final itemsM1 = (m1.contenu[cleDesEnfants]! as List).single as Map;
      final itemsM2 = (m2.contenu[cleDesEnfants]! as List).single as Map;
      expect(itemsM1['name'], 'Riz');
      expect(itemsM2['name'], 'Pain');
    });
  });

  group('Ecrire une version gagnante', () {
    test('une ligne ecrite se relit a l\'identique', () async {
      final avant = (await lireLignes(db, _table('mesures'))).single;
      await ecrireLigne(db, _table('mesures'), avant);
      final apres = (await lireLignes(db, _table('mesures'))).single;
      expect(apres.version.empreinte, avant.version.empreinte);
      expect(apres.updatedAt, avant.updatedAt);
    });

    test('une version distante gagnante remplace la locale', () async {
      final distante = LigneSynchronisable(
        cle: 's1',
        updatedAt: 2000,
        contenu: {
          'mesure_le': 2000,
          'type': 'hanches',
          'valeur_cm': 95.0,
          'created_at': 900,
        },
      );
      await ecrireLigne(db, _table('mesures'), distante);
      final relue = (await lireLignes(db, _table('mesures'))).single;
      expect(relue.updatedAt, 2000);
      expect(relue.contenu['type'], 'hanches');
      expect(relue.contenu['valeur_cm'], 95.0);
    });

    test('ecrire une pierre tombale la pose, sans effacer la ligne', () async {
      final supprimee = LigneSynchronisable(
        cle: 's1',
        updatedAt: 3000,
        deletedAt: 3000,
        contenu: {
          'mesure_le': 1000,
          'type': 'taille',
          'valeur_cm': 88.0,
          'created_at': 900,
        },
      );
      await ecrireLigne(db, _table('mesures'), supprimee);
      final relue = (await lireLignes(db, _table('mesures'))).single;
      expect(relue.estSupprimee, isTrue);
      expect(relue.contenu['valeur_cm'], 88.0);
    });

    test(
      'ecrire un agregat remplace ses aliments au lieu de les ajouter',
      () async {
        final repas = LigneSynchronisable(
          cle: 'm1',
          updatedAt: 4000,
          contenu: {
            'eaten_at': 1000,
            'name': 'Repas modifie',
            'source': 'photo',
            'is_estimate': 1,
            'created_at': 900,
            cleDesEnfants: [
              {
                'id': 'i9',
                'name': 'Pain',
                'quantity_g': 60.0,
                'source': 'manual',
                'sort_order': 0,
              },
            ],
          },
        );
        await ecrireLigne(db, _table('meals'), repas);
        final relue = (await lireLignes(db, _table('meals'))).single;
        expect(relue.contenu['name'], 'Repas modifie');
        final items = relue.contenu[cleDesEnfants]! as List;
        expect(items, hasLength(1));
        expect((items.single as Map)['name'], 'Pain');
      },
    );

    test('ecrire ne cree pas de doublon', () async {
      final avant = (await lireLignes(db, _table('pesees'))).single;
      await ecrireLigne(db, _table('pesees'), avant);
      await ecrireLigne(db, _table('pesees'), avant);
      expect(await lireLignes(db, _table('pesees')), hasLength(1));
    });

    test(
      'un aller-retour lecture-ecriture ne change pas l\'empreinte',
      () async {
        for (final table in tablesSynchronisables) {
          final avant = (await lireLignes(db, table)).single;
          await ecrireLigne(db, table, avant);
          final apres = (await lireLignes(db, table)).single;
          expect(
            apres.version.empreinte,
            avant.version.empreinte,
            reason: table.nom,
          );
        }
      },
    );
  });
}
