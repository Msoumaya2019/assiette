import 'dart:io';

import 'package:assiette/core/horloge.dart';
import 'package:assiette/data/local/app_database.dart';
import 'package:assiette/data/local/synchronisation_locale.dart';
import 'package:assiette/models/synchronisation.dart';
import 'package:assiette/services/synchronisation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'faux_serveur_synchronisation.dart';

/// Ouvre une base neuve sur SQLite natif.
///
/// Le chemin est un **fichier**, jamais `inMemoryDatabasePath` : deux ouvertures
/// du meme chemin rendent la meme base, et deux appareils deviendraient un seul.
/// Le projet l'a deja mesure une fois — voir `backup_service_test.dart`.
late Directory repertoireDesBases;

Future<AppDatabase> _baseNeuve(String nom, {Horloge? horloge}) async {
  final base = AppDatabase(
    factory: databaseFactoryFfi,
    customPath: p.join(repertoireDesBases.path, '$nom.db'),
    horloge: horloge,
  );
  await base.open();
  return base;
}

TableSynchronisable _table(String nom) =>
    tablesSynchronisables.firstWhere((table) => table.nom == nom);

/// Un appareil : sa base, et le service qui la relie au serveur.
class Appareil {
  Appareil(this.base, this.service);

  final AppDatabase base;
  final ServiceSynchronisation service;

  Database get db => base.db;

  /// Pose une ligne localement, par le meme chemin qu'une version gagnante.
  Future<void> poser(String nom, LigneSynchronisable ligne) =>
      ecrireLigne(db, _table(nom), ligne);

  Future<List<LigneSynchronisable>> lire(String nom) =>
      lireLignes(db, _table(nom));

  Future<LigneSynchronisable> ligne(String nom, String cle) async {
    final lignes = await lire(nom);
    return lignes.firstWhere((l) => l.cle == cle);
  }

  Future<RapportSynchronisation> synchroniser() => service.synchroniser();
}

// --- fixtures ---------------------------------------------------------------

Map<String, Object?> _aliment(String id, String nom, {double grams = 100}) => {
  'id': id,
  'name': nom,
  'quantity_g': grams,
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
  'brand': null,
  'image_url': null,
  'confidence': 0.9,
  'portion': null,
  'portion_label': null,
  'portion_grams': null,
  'is_estimate': 0,
  'sort_order': 0,
};

LigneSynchronisable _repas(
  String id, {
  required String nom,
  String? notes = 'note',
  int updatedAt = 1000,
  int? deletedAt,
  List<Map<String, Object?>> items = const [],
}) => LigneSynchronisable(
  cle: id,
  updatedAt: updatedAt,
  deletedAt: deletedAt,
  contenu: {
    'eaten_at': 1000,
    'name': nom,
    'source': 'manual',
    'notes': notes,
    'photo_path': null,
    'is_estimate': 0,
    'created_at': 900,
    cleDesEnfants: items,
  },
);

LigneSynchronisable _pesee(
  String id, {
  double kg = 72.5,
  int updatedAt = 1000,
}) => LigneSynchronisable(
  cle: id,
  updatedAt: updatedAt,
  contenu: {'mesure_le': 1000, 'poids_kg': kg, 'note': null, 'created_at': 900},
);

LigneSynchronisable _portion(
  String cle, {
  double grams = 65,
  int updatedAt = 1000,
}) => LigneSynchronisable(
  cle: cle,
  updatedAt: updatedAt,
  contenu: {'label': 'gateau', 'grams': grams},
);

void main() {
  setUpAll(sqfliteFfiInit);

  late Appareil a;
  late Appareil b;
  late FauxServeur serveur;

  /// Un appareil dont l'horloge est celle du serveur, sauf indication.
  ///
  /// L'horloge est posee sur la **base**, puis reprise par le service : une seule
  /// instance des deux cotes, exactement comme en production. Deux instances
  /// corrigeraient les estampilles d'un cote et pas de l'autre, et le defaut
  /// serait muet — le meme piege que la correction elle-meme cherche a eviter.
  Future<Appareil> appareil(String nom, {Horloge? horloge}) async {
    final base = await _baseNeuve(
      nom,
      horloge:
          horloge ??
          Horloge(
            source: () => DateTime.fromMillisecondsSinceEpoch(serveur.heure),
          ),
    );
    return Appareil(
      base,
      ServiceSynchronisation(
        db: base.db,
        transport: serveur,
        horloge: base.horloge,
      ),
    );
  }

  setUp(() async {
    repertoireDesBases = Directory.systemTemp.createTempSync('assiette-sync');
    serveur = FauxServeur();
    a = await appareil('a');
    b = await appareil('b');
  });

  tearDown(() async {
    await a.base.close();
    await b.base.close();
    repertoireDesBases.deleteSync(recursive: true);
  });

  group('Un appareil seul envoie ce qu\'il a', () {
    test(
      'la premiere synchronisation envoie tout, et le serveur le recoit',
      () async {
        await a.poser('meals', _repas('m1', nom: 'Repas'));
        await a.poser('pesees', _pesee('p1'));
        await a.poser('portions', _portion('nom:gateau'));

        final rapport = await a.synchroniser();

        expect(rapport.poussees, 3);
        expect(rapport.appliquees, 0);
        expect(rapport.aEchoue, isFalse);
        expect(serveur.lignes('meals'), hasLength(1));
        expect(serveur.ligne('meals', 'm1')!.contenu['name'], 'Repas');
        expect(serveur.lignes('pesees'), hasLength(1));
        expect(serveur.lignes('portions'), hasLength(1));
      },
    );

    test('la deuxieme synchronisation ne fait plus rien', () async {
      await a.poser('meals', _repas('m1', nom: 'Repas'));
      await a.synchroniser();

      final rapport = await a.synchroniser();

      expect(rapport.estVide, isTrue);
      expect(rapport.identiques, 1);
      expect(rapport.poussees, 0);
      expect(rapport.appliquees, 0);
    });

    test(
      'rien n\'est envoye quand les deux cotes sont deja d\'accord',
      () async {
        await a.poser('meals', _repas('m1', nom: 'Repas'));
        final ligne = await a.ligne('meals', 'm1');
        serveur.deposer('meals', ligne);

        final rapport = await a.synchroniser();

        expect(rapport.estVide, isTrue);
        expect(rapport.identiques, 1);
      },
    );

    test(
      'une ligne que l\'appareil gagne n\'est pas ecrasee par la version distante',
      () async {
        // Le defaut vise : appliquer **tout** ce que le serveur envoie, au lieu
        // des seules versions qu'il gagne. La version perdante ecraserait la
        // version gagnee, qui serait renvoyee juste apres — et si l'application
        // s'arretait entre les deux, la modification locale serait perdue. Le
        // rapport, lui, annoncerait zero ligne appliquee : il decrirait un plan
        // qui n'est pas ce qui a ete ecrit.
        await a.poser('meals', _repas('m1', nom: 'Repas'));
        await a.synchroniser();
        await a.poser(
          'meals',
          _repas('m1', nom: 'Repas du soir', updatedAt: 2000),
        );

        final rapport = await a.synchroniser();

        expect(rapport.appliquees, 0);
        expect((await a.ligne('meals', 'm1')).contenu['name'], 'Repas du soir');
        expect((await a.ligne('meals', 'm1')).updatedAt, 2000);
      },
    );

    test('les tables hors de l\'ensemble ne sont jamais visitees', () async {
      // `settings` vit dans la meme base, mais ne porte ni date ni pierre
      // tombale : elle ne doit pas etre transportee.
      await a.db.insert('settings', {'key': 'theme', 'value': 'sombre'});
      await a.poser('meals', _repas('m1', nom: 'Repas'));

      await a.synchroniser();

      final visites = {
        for (final appel in serveur.appels) appel.split(':').last,
      };
      expect(
        visites,
        equals({for (final t in tablesSynchronisables) t.nom}),
        reason: 'le transport ne doit voir que les tables synchronisables',
      );
      expect(
        await a.db.query('settings'),
        hasLength(1),
        reason:
            'la synchronisation ne touche pas aux reglages. La seule cle '
            'qu\'elle puisse ecrire est l\'ecart d\'horloge, et elle ne l\'ecrit '
            'que s\'il change : ici l\'appareil a l\'heure du serveur, donc rien '
            'n\'est ecrit. Un ecart qui changerait, lui, s\'ecrirait — c\'est ce '
            'que `horloge_test.dart` mesure.',
      );
    });
  });

  group('Deux appareils convergent', () {
    /// Les deux appareils partagent le meme etat de depart : un repas avec un
    /// aliment, une pesee, une portion.
    Future<void> etatPartage() async {
      final repas = _repas(
        'm1',
        nom: 'Repas',
        items: [_aliment('i1', 'Riz', grams: 150)],
      );
      for (final appareil in [a, b]) {
        await appareil.poser('meals', repas);
        await appareil.poser('pesees', _pesee('p1'));
        await appareil.poser('portions', _portion('nom:gateau'));
      }
      await a.synchroniser();
      await b.synchroniser();
    }

    test(
      'une modification faite sur un appareil arrive sur l\'autre',
      () async {
        await etatPartage();

        await a.poser(
          'meals',
          _repas('m1', nom: 'Repas du soir', updatedAt: 2000),
        );
        await a.synchroniser();
        await b.synchroniser();

        expect((await b.ligne('meals', 'm1')).contenu['name'], 'Repas du soir');
        expect((await b.ligne('meals', 'm1')).updatedAt, 2000);
      },
    );

    test(
      'une suppression faite sur un appareil supprime sur l\'autre',
      () async {
        await etatPartage();

        await a.poser(
          'meals',
          _repas('m1', nom: 'Repas', updatedAt: 3000, deletedAt: 3000),
        );
        await a.synchroniser();
        await b.synchroniser();

        final surB = await b.ligne('meals', 'm1');
        expect(surB.estSupprimee, isTrue);
        expect(surB.deletedAt, 3000);
        expect(
          surB.contenu['name'],
          'Repas',
          reason: 'la pierre tombale ne doit pas emporter le contenu',
        );
      },
    );

    test('la modification la plus recente gagne, dans les deux sens', () async {
      /// Un tour complet, en donnant la main au premier appareil indique.
      Future<String?> tour(String premier) async {
        await etatPartage();
        await a.poser('meals', _repas('m1', nom: 'Chez A', updatedAt: 2000));
        await b.poser('meals', _repas('m1', nom: 'Chez B', updatedAt: 2500));

        final ordre = premier == 'a' ? [a, b] : [b, a];
        for (final appareil in ordre) {
          await appareil.synchroniser();
        }
        // Un second passage des deux cotes : c'est la convergence, pas le
        // premier echange, qui est en jeu.
        for (final appareil in ordre) {
          await appareil.synchroniser();
        }
        return (await a.ligne('meals', 'm1')).contenu['name'] as String?;
      }

      expect(await tour('a'), 'Chez B');
      expect(await tour('b'), 'Chez B');
    });

    test(
      'apres convergence, une nouvelle synchronisation ne fait plus rien',
      () async {
        await etatPartage();
        await a.poser(
          'meals',
          _repas('m1', nom: 'Repas du soir', updatedAt: 2000),
        );
        await a.synchroniser();
        await b.synchroniser();
        await b.synchroniser();

        expect((await a.synchroniser()).estVide, isTrue);
        expect((await b.synchroniser()).estVide, isTrue);
      },
    );

    test('un aliment ajoute a un repas arrive avec son repas', () async {
      await etatPartage();

      await a.poser(
        'meals',
        _repas(
          'm1',
          nom: 'Repas',
          updatedAt: 2000,
          items: [
            _aliment('i1', 'Riz', grams: 150),
            _aliment('i2', 'Pain', grams: 60),
          ],
        ),
      );
      await a.synchroniser();
      await b.synchroniser();

      final items =
          (await b.ligne('meals', 'm1')).contenu[cleDesEnfants]! as List;
      expect(items, hasLength(2));
      expect(
        {for (final item in items) (item as Map)['name']},
        {'Riz', 'Pain'},
      );
    });

    test('un aliment retire d\'un repas disparait chez l\'autre', () async {
      await etatPartage();

      await a.poser(
        'meals',
        _repas('m1', nom: 'Repas', updatedAt: 2000, items: []),
      );
      await a.synchroniser();
      await b.synchroniser();

      expect((await b.ligne('meals', 'm1')).contenu[cleDesEnfants], isEmpty);
    });
  });

  group('Une table en panne n\'arrete pas les autres', () {
    test('la table en echec est nommee, les autres passent', () async {
      await a.poser('meals', _repas('m1', nom: 'Repas'));
      await a.poser('pesees', _pesee('p1'));
      serveur.tablesRefusees.add('meals');

      final rapport = await a.synchroniser();

      expect(rapport.tablesEnEchec, ['meals']);
      expect(rapport.poussees, 1, reason: 'la pesee doit etre passee');
      expect(serveur.lignes('pesees'), hasLength(1));
      expect(serveur.lignes('meals'), isEmpty);
      expect(
        serveur.appels,
        contains('lire:portions'),
        reason: 'les tables suivantes doivent tout de meme etre visitees',
      );
    });

    test('l\'echec se repare au passage suivant', () async {
      await a.poser('meals', _repas('m1', nom: 'Repas'));
      serveur.tablesRefusees.add('meals');
      await a.synchroniser();

      serveur.tablesRefusees.clear();
      final rapport = await a.synchroniser();

      expect(rapport.aEchoue, isFalse);
      expect(rapport.poussees, 1);
      expect(serveur.lignes('meals'), hasLength(1));
    });

    test('la panne est traduite, sans trace technique', () async {
      await a.poser('meals', _repas('m1', nom: 'Repas'));
      serveur.tablesRefusees.add('meals');

      final rapport = await a.synchroniser();

      final panne = rapport.parTable['meals']!.panne;
      expect(panne, isNotNull);
      expect(panne!.message, isNot(contains('StateError')));
      expect(panne.message, isNot(contains('le serveur refuse')));
    });
  });

  group('L\'ecart d\'horloge est mesure, signale, et retenu', () {
    test('les dates traversees ne sont pas reecrites', () async {
      await a.poser('meals', _repas('m1', nom: 'Repas', updatedAt: 1234));
      await a.synchroniser();
      await b.synchroniser();

      expect(serveur.ligne('meals', 'm1')!.updatedAt, 1234);
      expect((await b.ligne('meals', 'm1')).updatedAt, 1234);
      expect(
        (await b.ligne('meals', 'm1')).version.empreinte,
        (await a.ligne('meals', 'm1')).version.empreinte,
      );
    });

    test('un ecart d\'horloge important est signale', () async {
      serveur.heure = 1700000000000;
      final enAvance = Appareil(
        a.base,
        ServiceSynchronisation(
          db: a.db,
          transport: serveur,
          // Horloge **de l'appareil seul** : ce test porte sur ce que le rapport
          // mesure, pas sur ce que la base estampille. Une instance distincte est
          // donc volontaire ici — ailleurs, c'est la meme des deux cotes.
          horloge: Horloge(
            source: () => DateTime.fromMillisecondsSinceEpoch(
              serveur.heure + 3 * 3600 * 1000,
            ),
          ),
        ),
      );
      await enAvance.poser('meals', _repas('m1', nom: 'Repas'));

      final rapport = await enAvance.synchroniser();

      expect(rapport.decalageMs, -3 * 3600 * 1000);
      expect(rapport.horlogeSuspecte, isTrue);
    });

    test('un ecart nul n\'est pas signale', () async {
      await a.poser('meals', _repas('m1', nom: 'Repas'));

      final rapport = await a.synchroniser();

      expect(rapport.decalageMs, 0);
      expect(rapport.horlogeSuspecte, isFalse);
    });

    test('l\'ecart est mesure au milieu de l\'aller-retour', () async {
      serveur.heure = 1700000000000;
      var appels = 0;
      final lent = Appareil(
        a.base,
        ServiceSynchronisation(
          db: a.db,
          transport: serveur,
          // L'horloge avance de 1000 ms entre le debut et la fin de l'appel :
          // le milieu vaut donc +500, et l'ecart -500. Mesurer avant ou apres
          // l'appel donnerait 0 ou -1000, et compterait le temps de la requete
          // comme une avance de l'appareil.
          horloge: Horloge(
            source: () => DateTime.fromMillisecondsSinceEpoch(
              serveur.heure + 1000 * appels++,
            ),
          ),
        ),
      );

      final rapport = await lent.synchroniser();

      expect(rapport.decalageMs, -500);
    });

    test(
      'un serveur qui ne donne pas l\'heure laisse l\'ecart inconnu, sans bloquer',
      () async {
        await a.poser('meals', _repas('m1', nom: 'Repas'));
        serveur.heureIndisponible = true;

        final rapport = await a.synchroniser();

        expect(rapport.decalageMs, isNull);
        expect(rapport.horlogeSuspecte, isFalse);
        expect(
          rapport.poussees,
          1,
          reason: 'l\'ecart est un diagnostic, pas une condition',
        );
      },
    );

    test('une horloge fausse ne fait pas boucler la synchronisation', () async {
      // Un appareil trois jours en avance : sa modification porte une date que
      // l'autre appareil n'atteindra jamais. Si le service redatait la ligne en
      // l'appliquant, l'autre appareil la trouverait plus recente a chaque
      // passage, et les deux se renverraient la meme ligne sans fin.
      const dansTroisJours = 1700000000000 + 3 * 24 * 3600 * 1000;
      serveur.heure = 1700000000000;
      final enAvance = Appareil(
        a.base,
        ServiceSynchronisation(
          db: a.db,
          transport: serveur,
          horloge: Horloge(
            source: () => DateTime.fromMillisecondsSinceEpoch(
              serveur.heure + 3 * 24 * 3600 * 1000,
            ),
          ),
        ),
      );
      await enAvance.poser(
        'meals',
        _repas('m1', nom: 'Depuis le futur', updatedAt: dansTroisJours),
      );
      await enAvance.synchroniser();

      await b.synchroniser();
      expect(
        (await b.ligne('meals', 'm1')).updatedAt,
        dansTroisJours,
        reason:
            'la date est transportee, jamais refabriquee avec l\'heure du receveur',
      );
      expect((await b.ligne('meals', 'm1')).contenu['name'], 'Depuis le futur');

      final retour = await enAvance.synchroniser();
      expect(retour.estVide, isTrue, reason: 'rien ne doit repartir');
      expect((await b.synchroniser()).estVide, isTrue);
    });

    test('un ecart mesure survit a la fermeture de la base', () async {
      // Un appareil dont l'horloge **retarde** de trois heures.
      serveur.heure = 1700000000000;
      final retard = await appareil(
        'retard',
        horloge: Horloge(
          source: () => DateTime.fromMillisecondsSinceEpoch(
            serveur.heure - 3 * 3600 * 1000,
          ),
        ),
      );

      await retard.synchroniser();
      expect(retard.base.horloge.decalageMs, 3 * 3600 * 1000);
      await retard.base.close();

      // La meme base, rouverte avec une horloge **ordinaire** : l'ecart doit
      // revenir avant la premiere ecriture. Sans cela, un appareil dont
      // l'horloge est fausse estampillerait ses premieres modifications au
      // moment meme ou l'on ouvre la base pour les ecrire — et le remede ne
      // vaudrait que pour la session qui a mesure.
      final rouverte = await _baseNeuve('retard');
      expect(
        rouverte.horloge.decalageMs,
        3 * 3600 * 1000,
        reason:
            'l\'ecart est un etat de l\'appareil : il se relit au demarrage',
      );
      expect(
        (rouverte.horloge.maintenantMs() - rouverte.horloge.brutMs())
            .toDouble(),
        closeTo(3 * 3600 * 1000, 5),
        reason: 'l\'ecart relu est bien celui qui est applique',
      );
      await rouverte.close();
    });

    test('un deuxieme passage ne remet pas l\'ecart a zero', () async {
      // Le piege muet de tout ce mecanisme : mesurer l'ecart sur l'horloge
      // **corrigee** rendrait zero des que la correction est appliquee.
      // L'appareil se declarerait juste au deuxieme passage, et la correction
      // s'annulerait elle-meme — sans qu'aucun test du premier passage ne le
      // voie.
      serveur.heure = 1700000000000;
      final retard = await appareil(
        'retard-deux',
        horloge: Horloge(
          source: () => DateTime.fromMillisecondsSinceEpoch(
            serveur.heure - 3 * 3600 * 1000,
          ),
        ),
      );

      await retard.synchroniser();
      expect(retard.base.horloge.decalageMs, 3 * 3600 * 1000);

      final deuxieme = await retard.synchroniser();

      expect(
        deuxieme.decalageMs,
        3 * 3600 * 1000,
        reason:
            'la mesure se fait sur l\'horloge brute : la faire sur '
            'l\'horloge corrigee rendrait un ecart nul, et une horloge '
            'franchement fausse se declarerait juste',
      );
      expect(retard.base.horloge.decalageMs, 3 * 3600 * 1000);
      await retard.base.close();
    });
  });
}
