import 'package:assiette/models/suivi_poids.dart';
import 'package:flutter_test/flutter_test.dart';

Pesee pesee(String id, DateTime le, double kg) =>
    Pesee(id: id, le: le, poidsKg: kg);

Mesure mesure(String id, DateTime le, TypeMesure type, double cm) =>
    Mesure(id: id, le: le, type: type, valeurCm: cm);

void main() {
  group('Serie de poids', () {
    test('les points sortent du plus ancien au plus recent', () {
      final serie = SeriePoids.depuis([
        pesee('c', DateTime(2026, 9, 12), 70),
        pesee('a', DateTime(2026, 9, 10), 71),
        pesee('b', DateTime(2026, 9, 11), 70.5),
      ]);

      expect(serie.longueur, 3);
      expect(serie.points.map((p) => p.kg), [71, 70.5, 70]);
      expect(serie.premier!.le, DateTime(2026, 9, 10));
      expect(serie.dernier!.le, DateTime(2026, 9, 12));
    });

    test('une journee ne fait qu\'un point, le dernier', () {
      // Se peser matin et soir ne doit pas dessiner un aller-retour vertical
      // sur la courbe. Rien n'est perdu : la liste complete reste consultable
      // sous le graphique.
      final serie = SeriePoids.depuis([
        pesee('matin', DateTime(2026, 9, 10, 7), 71),
        pesee('soir', DateTime(2026, 9, 10, 21), 72),
        pesee('lendemain', DateTime(2026, 9, 11, 7), 70.5),
      ]);

      expect(serie.longueur, 2);
      expect(serie.points.first.kg, 72, reason: 'le dernier de la journee');
      expect(serie.points.last.kg, 70.5);
    });

    test('l\'ordre d\'arrivee ne change rien au point retenu', () {
      final serie = SeriePoids.depuis([
        pesee('soir', DateTime(2026, 9, 10, 21), 72),
        pesee('matin', DateTime(2026, 9, 10, 7), 71),
      ]);

      expect(serie.longueur, 1);
      expect(serie.points.single.kg, 72);
    });

    test('la fenetre ecarte ce qui precede', () {
      final serie = SeriePoids.depuis([
        pesee('vieux', DateTime(2026, 8, 1), 75),
        pesee('recent', DateTime(2026, 9, 10), 71),
      ], depuis: DateTime(2026, 9, 1));

      expect(serie.longueur, 1);
      expect(serie.points.single.kg, 71);
    });

    test('une serie vide ne rend rien, sans lever', () {
      final serie = SeriePoids.depuis(const []);
      expect(serie.estVide, isTrue);
      expect(serie.derniereKg, isNull);
      expect(serie.premiereKg, isNull);
      expect(serie.variationKg, isNull);
      expect(serie.minKg, isNull);
      expect(serie.maxKg, isNull);
    });

    test('la variation demande deux points', () {
      expect(
        SeriePoids.depuis([pesee('a', DateTime(2026, 9, 10), 71)]).variationKg,
        isNull,
      );

      final serie = SeriePoids.depuis([
        pesee('a', DateTime(2026, 9, 10), 72),
        pesee('b', DateTime(2026, 9, 12), 70.5),
      ]);
      // Le signe est rendu tel quel : l'application ne juge pas s'il est
      // souhaitable, elle l'affiche.
      expect(serie.variationKg, -1.5);
    });

    test('le minimum et le maximum portent sur toute la serie', () {
      final serie = SeriePoids.depuis([
        pesee('a', DateTime(2026, 9, 10), 72),
        pesee('b', DateTime(2026, 9, 11), 69.5),
        pesee('c', DateTime(2026, 9, 12), 71),
      ]);

      expect(serie.minKg, 69.5);
      expect(serie.maxKg, 72);
    });
  });

  group('Bornes du graphique', () {
    test('l\'objectif est compris dans le cadre', () {
      // Une ligne de cible hors du cadre serait invisible, et l'utilisateur
      // croirait qu'elle a disparu.
      final serie = SeriePoids.depuis([pesee('a', DateTime(2026, 9, 10), 72)]);

      final bornes = serie.bornes(objectifKg: 65);
      expect(bornes.min, lessThanOrEqualTo(65));
      expect(bornes.max, greaterThanOrEqualTo(72));
    });

    test('un kilo de marge est laisse de chaque cote', () {
      final serie = SeriePoids.depuis([
        pesee('a', DateTime(2026, 9, 10), 70),
        pesee('b', DateTime(2026, 9, 12), 75),
      ]);

      final bornes = serie.bornes();
      expect(bornes.min, 69);
      expect(bornes.max, 76);
    });

    test('une serie plate ne degenere pas en axe de hauteur nulle', () {
      final serie = SeriePoids.depuis([
        pesee('a', DateTime(2026, 9, 10), 70),
        pesee('b', DateTime(2026, 9, 11), 70),
      ]);

      final bornes = serie.bornes();
      expect(bornes.max - bornes.min, greaterThanOrEqualTo(2));
      expect(bornes.min, lessThan(70));
      expect(bornes.max, greaterThan(70));
    });

    test('sans aucun point, les bornes restent exploitables', () {
      final bornes = SeriePoids.vide.bornes();
      expect(bornes.max, greaterThan(bornes.min));
    });
  });

  group('Suivi complet', () {
    final suivi = SuiviPoids(
      pesees: [
        pesee('p1', DateTime(2026, 9, 12), 70),
        pesee('p2', DateTime(2026, 9, 10), 71),
      ],
      mesures: [
        mesure('m1', DateTime(2026, 9, 12), TypeMesure.taille, 82),
        mesure('m2', DateTime(2026, 9, 1), TypeMesure.taille, 84),
        mesure('m3', DateTime(2026, 9, 12), TypeMesure.hanches, 96),
      ],
      objectif: const ObjectifPoids(cibleKg: 68),
    );

    test('la serie se construit depuis les pesees', () {
      expect(suivi.serie().longueur, 2);
      expect(suivi.serie().derniereKg, 70);
    });

    test('les mesures se filtrent par type', () {
      expect(suivi.mesuresDe(TypeMesure.taille), hasLength(2));
      expect(suivi.mesuresDe(TypeMesure.hanches), hasLength(1));
      expect(suivi.mesuresDe(TypeMesure.cou), isEmpty);
    });

    test('la derniere valeur connue est retenue par type', () {
      // Les mesures arrivent de la plus recente a la plus ancienne : c'est cet
      // ordre qui donne « la derniere », et non la date la plus grande.
      final dernieres = suivi.dernieresMesures();
      expect(dernieres[TypeMesure.taille], 82);
      expect(dernieres[TypeMesure.hanches], 96);
      expect(dernieres.containsKey(TypeMesure.cou), isFalse);
    });

    test('un suivi vide ne se signale pas comme rempli', () {
      expect(SuiviPoids.vide.estVide, isTrue);
      expect(SuiviPoids.vide.objectif.estDefini, isFalse);
      expect(suivi.estVide, isFalse);
    });
  });

  group('Objectif de poids', () {
    test('aucun objectif n\'est propose par defaut', () {
      expect(ObjectifPoids.aucun.cibleKg, isNull);
      expect(ObjectifPoids.aucun.estDefini, isFalse);
    });

    test('un aller-retour conserve la cible', () {
      const objectif = ObjectifPoids(cibleKg: 68.5);
      expect(ObjectifPoids.fromJson(objectif.toJson()).cibleKg, 68.5);
    });

    test(
      'un objectif se retire, il ne se remplace pas par une valeur inventee',
      () {
        const objectif = ObjectifPoids(cibleKg: 68);
        expect(objectif.copyWith(effacer: true).cibleKg, isNull);
        expect(objectif.copyWith(cibleKg: 70).cibleKg, 70);
        // Sans argument, rien ne change.
        expect(objectif.copyWith().cibleKg, 68);
      },
    );
  });

  group('Serialisation des mesures et des pesees', () {
    test('une pesee fait un aller-retour', () {
      final originale = Pesee(
        id: 'p1',
        le: DateTime(2026, 9, 12, 8),
        poidsKg: 70.4,
        note: 'a jeun',
      );
      final relue = Pesee.depuisJson(originale.toJson());
      expect(relue, isNotNull);
      expect(relue!.id, 'p1');
      expect(relue.le, DateTime(2026, 9, 12, 8));
      expect(relue.poidsKg, 70.4);
      expect(relue.note, 'a jeun');
    });

    test('une pesee sans poids ou sans date est refusee', () {
      expect(
        Pesee.depuisJson({'id': 'p1', 'le': '2026-09-12T08:00:00'}),
        isNull,
      );
      expect(Pesee.depuisJson({'id': 'p1', 'poidsKg': 70}), isNull);
      expect(
        Pesee.depuisJson({'id': 'p1', 'le': 'pas-une-date', 'poidsKg': 70}),
        isNull,
      );
    });

    test('une mesure fait un aller-retour', () {
      final originale = mesure(
        'm1',
        DateTime(2026, 9, 12),
        TypeMesure.hanches,
        96,
      );
      final relue = Mesure.depuisJson(originale.toJson());
      expect(relue, isNotNull);
      expect(relue!.type, TypeMesure.hanches);
      expect(relue.valeurCm, 96);
    });

    test('un type de mesure inconnu est ecarte, pas devine', () {
      // Une version plus recente de l'application peut avoir ajoute un type.
      // Une version plus ancienne doit continuer de lire le reste au lieu de
      // faire echouer la lecture entiere.
      expect(
        Mesure.depuisJson({
          'id': 'm1',
          'le': '2026-09-12T08:00:00',
          'type': 'tour-de-mollet',
          'valeurCm': 38,
        }),
        isNull,
      );
    });
  });

  group('Types de mesure', () {
    test('chaque type a un libelle et une precision', () {
      for (final type in TypeMesure.values) {
        expect(type.displayLabel, isNotEmpty);
        expect(type.precision, isNotEmpty);
      }
      expect(TypeMesure.unite, 'cm');
    });

    test('un identifiant inconnu ne leve pas', () {
      expect(TypeMesure.fromId('taille'), TypeMesure.taille);
      expect(TypeMesure.fromId('inconnu'), isNull);
      expect(TypeMesure.fromId(null), isNull);
    });
  });
}
