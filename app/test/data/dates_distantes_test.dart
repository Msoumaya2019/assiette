import 'package:assiette/data/distant/dates_distantes.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ce que ces tests ferment
/// ------------------------
/// Le serveur porte des `timestamptz`, le local des entiers en millisecondes.
/// Deux erreurs de conversion ne se voient pas : elles font diverger les
/// empreintes, donc l'arbitrage tranche toujours dans le meme sens et chaque
/// passage reecrit la meme ligne — sans erreur, sans trace, et sans fin.
void main() {
  group('Du local vers le serveur', () {
    test('une date devient un ISO-8601 en UTC, marque d\'un Z', () {
      // Sans le `Z`, le serveur lirait la date dans le fuseau de sa session :
      // deux appareils dans deux fuseaux enregistreraient deux instants
      // differents pour la meme modification.
      final iso = isoDepuisMillisecondes(1700000000000);
      expect(iso, '2023-11-14T22:13:20.000Z');
      expect(iso, endsWith('Z'));
    });

    test('une date absente reste absente', () {
      // Elle ne devient pas 1970 : une pierre tombale nulle et une date nulle
      // sont deux choses differentes. Les confondre ferait d'une ligne jamais
      // supprimee une ligne supprimee en 1970, donc gagnante partout.
      expect(isoDepuisMillisecondes(null), isNull);
      expect(isoDepuisMillisecondes(0), '1970-01-01T00:00:00.000Z');
    });
  });

  group('Du serveur vers le local', () {
    test('un ISO-8601 redevient un entier en millisecondes', () {
      expect(millisecondesDepuisIso('2023-11-14T22:13:20.000Z'), 1700000000000);
    });

    test(
      'un decalage horaire est ramene a l\'instant, pas a l\'heure locale',
      () {
        // Le meme instant, ecrit dans deux fuseaux, doit rendre le meme entier.
        expect(
          millisecondesDepuisIso('2023-11-14T23:13:20.000+01:00'),
          1700000000000,
        );
        expect(
          millisecondesDepuisIso('2023-11-14T17:13:20.000-05:00'),
          1700000000000,
        );
      },
    );

    test('l\'aller-retour redonne l\'entier de depart', () {
      for (final millisecondes in [0, 1, 1700000000000, 4102444800000]) {
        expect(
          millisecondesDepuisIso(isoDepuisMillisecondes(millisecondes)),
          millisecondes,
          reason: '$millisecondes ne revient pas a l\'identique',
        );
      }
    });

    test('une absence reste une absence', () {
      expect(millisecondesDepuisIso(null), isNull);
      expect(
        millisecondesDepuisIso(''),
        isNull,
        reason: 'PostgREST rend une chaine vide pour une colonne nulle',
      );
    });

    test('une date cassee leve, elle ne devient pas une absence', () {
      // La traiter comme une absence en ferait une « date inconnue », qui est
      // une valeur — et une valeur fausse qui se propage est pire qu'une
      // erreur, parce que rien ne la signale.
      expect(() => millisecondesDepuisIso('hier'), throwsFormatException);
      expect(() => millisecondesDepuisIso(4.5), throwsFormatException);
      expect(() => millisecondesDepuisIso(true), throwsFormatException);
    });

    test('un entier est accepte tel quel', () {
      // Certains formats de sortie rendent le nombre plutot que la chaine.
      expect(millisecondesDepuisIso(1700000000000), 1700000000000);
    });
  });
}
