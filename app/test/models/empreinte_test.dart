import 'package:assiette/models/empreinte.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Une empreinte ne depend que du contenu', () {
    test('deux maps de meme contenu rendent la meme empreinte', () {
      final a = empreinteDeContenu({'nom': 'Yaourt', 'glucides': 12.0});
      final b = empreinteDeContenu({'nom': 'Yaourt', 'glucides': 12.0});
      expect(a, b);
    });

    test('l\'ordre des cles ne change rien', () {
      final a = empreinteDeContenu({'nom': 'Yaourt', 'glucides': 12.0});
      final b = empreinteDeContenu({'glucides': 12.0, 'nom': 'Yaourt'});
      expect(a, b);
    });

    test(
      'l\'ordre des cles ne change rien non plus dans un objet imbrique',
      () {
        final a = empreinteDeContenu({
          'portion': {'label': 'pot', 'grams': 125.0},
        });
        final b = empreinteDeContenu({
          'portion': {'grams': 125.0, 'label': 'pot'},
        });
        expect(a, b);
      },
    );

    test('un contenu different rend une empreinte differente', () {
      final a = empreinteDeContenu({'nom': 'Yaourt'});
      final b = empreinteDeContenu({'nom': 'Gateau'});
      expect(a, isNot(b));
    });

    test('une cle en plus change l\'empreinte', () {
      final a = empreinteDeContenu({'nom': 'Yaourt'});
      final b = empreinteDeContenu({'nom': 'Yaourt', 'note': null});
      expect(a, isNot(b));
    });

    test('le contenu vide a une empreinte, et elle est stable', () {
      expect(empreinteDeContenu(const {}), empreinteDeContenu(const {}));
      expect(empreinteDeContenu(const {}), isNot(empreinteDeContenu({'a': 1})));
    });
  });

  group('Le format ne confond pas deux contenus', () {
    // Le cas qui justifie les longueurs : une concatenation nue rendrait la
    // meme chose pour ces deux objets, et deux lignes differentes seraient
    // declarees identiques.
    test('une valeur ne peut pas deborder sur la cle suivante', () {
      final a = empreinteDeContenu({'a': 'bc'});
      final b = empreinteDeContenu({'ab': 'c'});
      expect(a, isNot(b));
    });

    test('deux valeurs voisines ne peuvent pas se confondre', () {
      final a = empreinteDeContenu({'a': 'x', 'b': 'yz'});
      final b = empreinteDeContenu({'a': 'xy', 'b': 'z'});
      expect(a, isNot(b));
    });

    test('une chaine vide et une absence ne se confondent pas', () {
      expect(
        empreinteDeContenu({'note': ''}),
        isNot(empreinteDeContenu({'note': null})),
      );
    });

    test('un texte et un nombre de meme ecriture ne se confondent pas', () {
      expect(
        empreinteDeContenu({'valeur': '1'}),
        isNot(empreinteDeContenu({'valeur': 1})),
      );
    });

    test('un booleen et un texte ne se confondent pas', () {
      expect(
        empreinteDeContenu({'valeur': true}),
        isNot(empreinteDeContenu({'valeur': 'true'})),
      );
    });

    test('une liste et un objet ne se confondent pas', () {
      expect(
        empreinteDeContenu({
          'valeur': [1],
        }),
        isNot(
          empreinteDeContenu({
            'valeur': {'0': 1},
          }),
        ),
      );
    });
  });

  group('Les nombres sont normalises', () {
    // Le cas reel : la meme valeur lue depuis SQLite (REAL) et depuis JSON peut
    // arriver tantot entiere, tantot flottante. Les separer ferait passer une
    // ligne inchangee pour modifiee, et la synchronisation la pousserait sans
    // fin.
    test('un entier et le flottant de meme valeur se confondent', () {
      expect(
        empreinteDeContenu({'poids': 1}),
        empreinteDeContenu({'poids': 1.0}),
      );
    });

    test('zero et moins zero se confondent', () {
      expect(
        empreinteDeContenu({'poids': 0}),
        empreinteDeContenu({'poids': -0.0}),
      );
    });

    test('deux nombres reellement differents ne se confondent pas', () {
      expect(
        empreinteDeContenu({'poids': 1}),
        isNot(empreinteDeContenu({'poids': 1.5})),
      );
    });

    test('un grand flottant entier garde une forme stable', () {
      final a = empreinteDeContenu({'valeur': 1234567.0});
      final b = empreinteDeContenu({'valeur': 1234567});
      expect(a, b);
    });
  });

  group('Les listes gardent leur ordre', () {
    test('deux listes de meme contenu mais d\'ordre different different', () {
      final a = empreinteDeContenu({
        'items': ['riz', 'poulet'],
      });
      final b = empreinteDeContenu({
        'items': ['poulet', 'riz'],
      });
      expect(a, isNot(b));
    });

    test('une liste vide et une liste a un element vide different', () {
      expect(
        empreinteDeContenu({'items': <Object?>[]}),
        isNot(
          empreinteDeContenu({
            'items': <Object?>[''],
          }),
        ),
      );
    });
  });

  group('Les dates se comparent en UTC', () {
    test('le meme instant dans deux fuseaux rend la meme empreinte', () {
      final utc = empreinteDeContenu({
        'eaten_at': DateTime.parse('2026-09-21T12:00:00Z'),
      });
      final paris = empreinteDeContenu({
        'eaten_at': DateTime.parse('2026-09-21T14:00:00+02:00'),
      });
      expect(utc, paris);
    });

    test('deux instants differents ne se confondent pas', () {
      expect(
        empreinteDeContenu({
          'eaten_at': DateTime.parse('2026-09-21T12:00:00Z'),
        }),
        isNot(
          empreinteDeContenu({
            'eaten_at': DateTime.parse('2026-09-21T12:00:01Z'),
          }),
        ),
      );
    });
  });

  group('Un type non representable est refuse', () {
    // Refuser plutot que de retomber sur `toString()` : le `toString()` par
    // defaut d'un objet contient son adresse memoire, donc l'empreinte
    // changerait d'une execution a l'autre — une modification fantome.
    test(
      'un objet quelconque fait lever, au lieu de rendre un texte instable',
      () {
        expect(
          () => empreinteDeContenu({'valeur': Object()}),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('le refus nomme le type fautif', () {
      try {
        empreinteDeContenu({'valeur': Object()});
        fail('l\'empreinte aurait du refuser un objet quelconque');
      } on ArgumentError catch (erreur) {
        expect(erreur.message, contains('Object'));
        expect(erreur.message, contains('adresse'));
      }
    });

    test('un objet quelconque imbrique dans une liste est refuse aussi', () {
      expect(
        () => empreinteDeContenu({
          'items': [Object()],
        }),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
