import 'dart:convert';

import 'package:assiette/data/distant/json_distants.dart';
import 'package:flutter_test/flutter_test.dart';

/// La conversion entre `jsonb` et texte
/// ------------------------------------
/// `templates.items` et `favorites.payload` sont des `jsonb` cote serveur, du
/// `TEXT` cote local. Le piege est plus discret que celui des dates : les deux
/// cotes portent « du JSON », donc la colonne a l'air transportable telle
/// quelle. Elle ne l'est pas — le serveur rend une structure, le local attend
/// une chaine.
///
/// Ce qui se teste ici est l'**aller-retour**, sur des valeurs et pas sur un
/// exemple : c'est lui qui decide si les empreintes des deux cotes peuvent
/// tomber d'accord.
void main() {
  group('Ce que le serveur rend devient le texte local', () {
    test('un objet', () {
      expect(texteDepuisJson({'a': 1}), '{"a":1}');
    });

    test('une liste, qui est le cas reel d\'un modele de repas', () {
      expect(texteDepuisJson(const []), '[]');
      expect(texteDepuisJson(const [1, 2, 3]), '[1,2,3]');
    });

    test('une absence reste une absence', () {
      expect(texteDepuisJson(null), isNull);
    });

    test('une chaine garde ses guillemets', () {
      // Le piege que la serialisation inconditionnelle ferme. Un `jsonb` qui
      // contient la chaine `hello` revient en Dart comme la chaine `hello`,
      // sans guillemets ; la rendre telle quelle perdrait l'information, et le
      // local, qui porte `"hello"`, ne retomberait jamais d'accord.
      expect(texteDepuisJson('hello'), '"hello"');
      expect(jsonDecode(texteDepuisJson('hello')!), 'hello');
    });
  });

  group('Le texte local redevient une structure', () {
    test('une liste vide, une liste pleine, un objet', () {
      expect(jsonDepuisTexte('[]'), isEmpty);
      expect(jsonDepuisTexte('[1,2,3]'), [1, 2, 3]);
      expect(jsonDepuisTexte('{"a":1}'), {'a': 1});
    });

    test('une absence reste une absence', () {
      expect(jsonDepuisTexte(null), isNull);
    });

    test('un texte illisible leve, il ne devient pas une absence', () {
      // Une valeur par defaut inventee ferait disparaitre le contenu d'un
      // modele de repas sans que rien ne le signale. Une synchronisation
      // refusee vaut mieux qu'une donnee perdue en silence.
      expect(() => jsonDepuisTexte('hello'), throwsFormatException);
      expect(() => jsonDepuisTexte('{'), throwsFormatException);
    });

    test('une valeur deja decodee passe telle quelle', () {
      // La fonction ne defait pas ce qu'un autre a fait : elle est sure a
      // appeler deux fois.
      expect(jsonDepuisTexte(const [1, 2]), [1, 2]);
      expect(jsonDepuisTexte({'a': 1}), {'a': 1});
    });
  });

  group('L\'aller-retour revient au meme texte', () {
    test('sur les textes que l\'application ecrit', () {
      // La propriete qui compte : si elle ne tenait pas, les empreintes
      // differeraient toujours, l'arbitrage trancherait toujours dans le meme
      // sens, et chaque passage reecrirait la meme ligne.
      for (final texte in const [
        '[]',
        '[1,2,3]',
        '{}',
        '{"a":1}',
        '{"a":1,"b":[2,3]}',
        '"hello"',
        'true',
        'false',
        '42',
        '4.5',
      ]) {
        expect(
          texteDepuisJson(jsonDepuisTexte(texte)),
          texte,
          reason: '« $texte » ne revient pas a lui-meme',
        );
      }
    });

    test('sauf pour le texte « null », et c\'est nomme', () {
      // PostgREST ne distingue pas un `jsonb` qui contient la valeur JSON
      // `null` d'un SQL NULL : les deux reviennent en Dart comme une absence.
      // Le cas est donc degenere, et il est **mesure** plutot que tu :
      //
      //   jsonDepuisTexte('null')  ->  null
      //   texteDepuisJson(null)    ->  null, et non 'null'
      //
      // Consequence : le local, dont ces colonnes sont `NOT NULL`, refuserait
      // l'ecriture — bruyamment, ce qui est le comportement voulu.
      expect(jsonDepuisTexte('null'), isNull);
      expect(texteDepuisJson(null), isNull);
    });
  });
}
