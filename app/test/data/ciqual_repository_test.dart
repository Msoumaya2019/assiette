import 'dart:convert';

import 'package:assiette/data/ciqual_repository.dart';
import 'package:assiette/models/food.dart';
import 'package:flutter_test/flutter_test.dart';

/// Jeu de donnees reduit, avec les memes cles que le fichier embarque.
const List<Map<String, dynamic>> _sample = [
  {
    'code': '9100',
    'name': 'Riz blanc, cuit',
    'n': 'riz blanc cuit',
    'group': '09',
    'groupName': 'Cereales et derives',
    'kcal': 145,
    'carbs': 31.5,
    'sugars': 0.1,
    'starch': 31.2,
    'protein': 2.7,
    'fat': 0.3,
    'fiber': 0.9,
    'salt': 0.01,
  },
  {
    'code': '9101',
    'name': 'Riz complet, cuit',
    'n': 'riz complet cuit',
    'group': '09',
    'groupName': 'Cereales et derives',
    'kcal': 165,
    'carbs': 34.0,
    'sugars': 0.4,
    'starch': 33.0,
    'protein': 3.5,
    'fat': 1.0,
    'fiber': 1.8,
    'salt': 0.01,
  },
  {
    'code': '1000',
    'name': 'Poulet, grille',
    'n': 'poulet grille',
    'group': '04',
    'groupName': 'Viandes',
    'kcal': 165,
    'carbs': 0.0,
    'sugars': 0.0,
    'starch': 0.0,
    'protein': 31.0,
    'fat': 3.6,
    'fiber': 0.0,
    'salt': 0.2,
  },
  {
    'code': '7000',
    'name': 'Pain, baguette, courante',
    'n': 'pain baguette courante',
    'group': '07',
    'groupName': 'Pains et pates',
    'kcal': 274,
    'carbs': 55.6,
    'sugars': 2.5,
    'starch': 52.0,
    'protein': 9.0,
    'fat': 1.3,
    'fiber': 2.6,
    'salt': 1.3,
  },
  {
    'code': '2000',
    'name': 'Yaourt nature',
    'n': 'yaourt nature',
    'group': '19',
    'groupName': 'Produits laitiers',
    'kcal': 58,
    'carbs': 4.5,
    'sugars': 4.5,
    'starch': 0.0,
    'protein': 3.8,
    'fat': 2.5,
    'fiber': 0.0,
    'salt': 0.12,
  },
];

CiqualRepository repository() {
  final repo = CiqualRepository();
  repo.loadFromJsonString(
    jsonEncode({'count': _sample.length, 'foods': _sample}),
  );
  return repo;
}

void main() {
  group('normalizeForSearch', () {
    test('supprime les accents et passe en minuscules', () {
      expect(normalizeForSearch('Creme brûlée'), 'creme brulee');
      expect(normalizeForSearch('Pêche'), 'peche');
      expect(normalizeForSearch('CEleri-Rave'), 'celeri rave');
    });

    test('normalise les espaces et la ponctuation', () {
      expect(normalizeForSearch('  riz    blanc ,  cuit '), 'riz blanc cuit');
      expect(normalizeForSearch('pain (baguette)'), 'pain baguette');
    });

    test('traite les ligatures', () {
      expect(normalizeForSearch('boeuf'), 'boeuf');
      expect(normalizeForSearch('œuf'), 'oeuf');
    });

    test('une chaine vide reste vide', () {
      expect(normalizeForSearch(''), '');
      expect(normalizeForSearch('   '), '');
      expect(normalizeForSearch('---'), '');
    });
  });

  group('Chargement', () {
    test('les aliments sont indexes par code', () {
      final repo = repository();
      expect(repo.isLoaded, isTrue);
      expect(repo.count, _sample.length);
      expect(repo.byCode('9100')?.name, 'Riz blanc, cuit');
      expect(repo.byCode('inconnu'), isNull);
    });

    test('les valeurs nutritionnelles sont lues correctement', () {
      final repo = repository();
      final riz = repo.byCode('9100')!;

      expect(riz.per100g.kcal, 145);
      expect(riz.per100g.carbs, 31.5);
      expect(riz.per100g.protein, 2.7);
      expect(riz.source, FoodSource.ciqual);
      expect(riz.category, 'Cereales et derives');
    });

    test('les categories sont dedupliquees et triees', () {
      final repo = repository();
      expect(repo.categories, [
        'Cereales et derives',
        'Pains et pates',
        'Produits laitiers',
        'Viandes',
      ]);
    });
  });

  group('Recherche', () {
    test('trouve un aliment quelle que soit la saisie accentuee', () {
      final repo = repository();
      // « cuit » ne porte pas d'accent, mais « grille » est ecrit « grille »
      // dans la table : la recherche doit tolerer les deux formes.
      expect(repo.search('grille').map((food) => food.sourceRef), contains('1000'));
      expect(repo.search('grillé').map((food) => food.sourceRef), contains('1000'));
    });

    test('trouve un aliment meme si la requete contient un accent', () {
      final repo = repository();
      expect(repo.search('céréales'), isNotEmpty);
      expect(repo.search('cereales'), isNotEmpty);
    });

    test('une requete vide ne renvoie rien', () {
      final repo = repository();
      expect(repo.search(''), isEmpty);
      expect(repo.search('   '), isEmpty);
    });

    test('les noms commencant par la requete passent en premier', () {
      final repo = repository();
      final results = repo.search('riz');
      expect(results.length, 2);
      expect(results.first.name, startsWith('Riz'));
    });

    test('la limite est respectee', () {
      final repo = repository();
      expect(repo.search('riz', limit: 1).length, 1);
    });

    test('une recherche sans correspondance renvoie une liste vide', () {
      final repo = repository();
      expect(repo.search('chocolat'), isEmpty);
    });
  });

  group('Correspondance automatique', () {
    test('un nom exact est reconnu', () {
      final repo = repository();
      final match = repo.findBestMatch('Riz blanc, cuit');
      expect(match?.sourceRef, '9100');
    });

    test('un nom sans accents est reconnu', () {
      final repo = repository();
      expect(repo.findBestMatch('poulet grille')?.sourceRef, '1000');
    });

    test('une formulation proche est reconnue', () {
      final repo = repository();
      expect(repo.findBestMatch('riz blanc cuit')?.sourceRef, '9100');
      expect(repo.findBestMatch('pain baguette')?.sourceRef, '7000');
    });

    test('un aliment absent de la table ne produit aucune correspondance', () {
      final repo = repository();
      // Mieux vaut ne rien proposer que d'attribuer de fausses valeurs.
      expect(repo.findBestMatch('tofu fumé aux algues'), isNull);
      expect(repo.findBestMatch(''), isNull);
    });

    test('la correspondance ne confond pas deux aliments proches', () {
      final repo = repository();
      expect(repo.findBestMatch('riz complet cuit')?.sourceRef, '9101');
      expect(repo.findBestMatch('riz blanc cuit')?.sourceRef, '9100');
    });
  });
}
