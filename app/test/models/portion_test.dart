import 'package:assiette/models/portion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Accord et libelle', () {
    const gateau = Portion(label: 'gateau', grams: 65);

    test('le singulier s\'applique en dessous de deux', () {
      expect(gateau.libelle(1), '1 gateau');
      // Regle francaise : « 1,5 part », pas « 1,5 parts ».
      expect(gateau.libelle(1.5), '1,5 gateau');
      expect(gateau.libelle(0), '0 gateau');
    });

    test('le pluriel s\'applique a partir de deux', () {
      expect(gateau.libelle(2), '2 gateaux');
      expect(gateau.libelle(3), '3 gateaux');
    });

    test('les mots en -eau et -au prennent un x', () {
      expect(const Portion(label: 'gateau', grams: 65).libelle(2), '2 gateaux');
      expect(const Portion(label: 'noyau', grams: 5).libelle(2), '2 noyaux');
      expect(
        const Portion(label: 'morceau', grams: 20).libelle(2),
        '2 morceaux',
      );
    });

    test('les mots deja termines par s, x ou z restent invariables', () {
      expect(const Portion(label: 'jus', grams: 200).libelle(2), '2 jus');
      expect(const Portion(label: 'riz', grams: 150).libelle(3), '3 riz');
      expect(const Portion(label: 'mais', grams: 90).libelle(2), '2 mais');
    });

    test('les autres mots prennent un s', () {
      expect(const Portion(label: 'part', grams: 80).libelle(2), '2 parts');
      expect(const Portion(label: 'bol', grams: 250).libelle(2), '2 bols');
      expect(
        const Portion(label: 'tranche', grams: 30).libelle(2),
        '2 tranches',
      );
    });

    test('nomPluriel sert aux libelles d\'interface', () {
      expect(const Portion(label: 'jus', grams: 200).nomPluriel, 'jus');
      expect(const Portion(label: 'part', grams: 80).nomPluriel, 'parts');
      expect(const Portion(label: '  part  ', grams: 80).nomSingulier, 'part');
    });

    test('libelleAvecPoids garde le poids visible', () {
      expect(gateau.libelleAvecPoids(2), '2 gateaux · 130 g');
      expect(gateau.libelleAvecPoids(1), '1 gateau · 65 g');
    });

    test('etiquetteUnite annonce l\'unite de reference', () {
      expect(gateau.etiquetteUnite, '1 gateau (65 g)');
    });
  });

  group('Conversion', () {
    const portion = Portion(label: 'part', grams: 80);

    test('un poids se convertit en unites', () {
      expect(portion.unitesPour(160), 2);
      expect(portion.unitesPour(100), 1.25);
      expect(portion.unitesPour(0), 0);
    });

    test('un nombre d\'unites se convertit en poids', () {
      expect(portion.grammesPour(2), 160);
      expect(portion.grammesPour(0.5), 40);
    });

    test('une portion de poids nul ne convertit rien', () {
      // Sans ce garde-fou, `unitesPour` diviserait par zero et rendrait
      // l'infini, qui remonterait jusqu'a l'affichage.
      const absurde = Portion(label: 'rien', grams: 0);
      expect(absurde.estValide, isFalse);
      expect(absurde.unitesPour(100), isNull);
    });
  });

  group('Portion lue depuis une etiquette', () {
    test('« 1 pot (125 g) » donne une portion de 125 g', () {
      final portion = Portion.depuisEtiquette('1 pot (125 g)', 125);
      expect(portion, isNotNull);
      expect(portion!.label, 'pot');
      expect(portion.grams, 125);
    });

    test('« 2 biscuits (25 g) » donne 12,5 g par biscuit', () {
      // Le piege de ces etiquettes : les grammes annonces valent pour **deux**
      // unites. Les prendre pour une seule doublerait la portion proposee, et
      // rien ne le signalerait.
      final portion = Portion.depuisEtiquette('2 biscuits (25 g)', 25);
      expect(portion, isNotNull);
      expect(portion!.label, 'biscuit');
      expect(portion.grams, 12.5);
      expect(portion.libelle(2), '2 biscuits');
    });

    test('« 3 gateaux (195 g) » revient au singulier', () {
      final portion = Portion.depuisEtiquette('3 gateaux (195 g)', 195);
      expect(portion!.label, 'gateau');
      expect(portion.grams, 65);
    });

    test('les formes ambigues ne sont pas devinees', () {
      // Mieux vaut ne proposer aucune portion que d'en proposer une fausse :
      // l'utilisateur peut toujours la definir lui-meme.
      expect(Portion.depuisEtiquette('une part', 80), isNull);
      expect(Portion.depuisEtiquette('125 g', 125), isNull);
      expect(Portion.depuisEtiquette(null, 125), isNull);
      expect(Portion.depuisEtiquette('1 pot (125 g)', null), isNull);
      expect(Portion.depuisEtiquette('1 pot (125 g)', 0), isNull);
    });

    test('une virgule decimale est acceptee', () {
      final portion = Portion.depuisEtiquette('2 biscuits (25,5 g)', 25.5);
      expect(portion!.grams, 12.75);
    });
  });

  group('Serialisation', () {
    test('un aller-retour conserve le nom et le poids', () {
      const portion = Portion(label: 'gateau', grams: 65);
      final relue = Portion.depuisJson(portion.toJson());
      expect(relue, isNotNull);
      expect(relue!.label, 'gateau');
      expect(relue.grams, 65);
      expect(relue, portion);
    });

    test('une portion inexploitable est refusee', () {
      expect(Portion.depuisJson(null), isNull);
      expect(Portion.depuisJson('gateau'), isNull);
      expect(Portion.depuisJson({'label': 'gateau'}), isNull);
      expect(Portion.depuisJson({'grams': 65}), isNull);
      expect(Portion.depuisJson({'label': '', 'grams': 65}), isNull);
      expect(Portion.depuisJson({'label': 'gateau', 'grams': 0}), isNull);
      expect(Portion.depuisJson({'label': 'gateau', 'grams': -5}), isNull);
    });
  });

  group('Cle d\'aliment', () {
    test('la reference de source prime sur le nom', () {
      // Un code-barres designe un produit precis ; un nom peut s'ecrire de deux
      // facons. Deux graphies du meme nom ne doivent pas creer deux portions.
      expect(
        Portion.clePour(
          source: 'openFoodFacts',
          sourceRef: '3033490005247',
          nom: 'Yaourt nature',
        ),
        'openFoodFacts:3033490005247',
      );
      expect(
        Portion.clePour(
          source: 'ciqual',
          sourceRef: '9100',
          nom: 'Riz blanc cuit',
        ),
        'ciqual:9100',
      );
    });

    test('sans reference, le nom normalise sert de cle', () {
      expect(
        Portion.clePour(
          source: 'manual',
          sourceRef: null,
          nom: '  Gateau maison  ',
        ),
        'nom:gateau maison',
      );
      expect(
        Portion.clePour(
          source: 'manual',
          sourceRef: '   ',
          nom: 'Gateau maison',
        ),
        'nom:gateau maison',
      );
    });
  });
}
