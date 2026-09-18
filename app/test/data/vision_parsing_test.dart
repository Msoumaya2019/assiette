import 'package:assiette/core/failures.dart';
import 'package:assiette/data/vision/vision_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractJsonObject', () {
    test('lit un objet JSON simple', () {
      final decoded = extractJsonObject('{"a": 1}');
      expect(decoded, isA<Map>());
      expect((decoded! as Map)['a'], 1);
    });

    test('tolere les balises Markdown', () {
      final decoded = extractJsonObject('```json\n{"foods": []}\n```');
      expect(decoded, isA<Map>());
      expect((decoded! as Map)['foods'], isEmpty);
    });

    test('tolere un balisage sans indication de langage', () {
      final decoded = extractJsonObject('```\n{"a": true}\n```');
      expect((decoded! as Map)['a'], isTrue);
    });

    test('ignore le texte place avant et apres l\'objet', () {
      const raw = 'Voici le resultat :\n{"carbs": 42}\nJ\'espere que cela aide.';
      final decoded = extractJsonObject(raw);
      expect((decoded! as Map)['carbs'], 42);
    });

    test('gere les accolades a l\'interieur des chaines', () {
      const raw = '{"note": "accolade { et } dans le texte", "carbs": 10}';
      final decoded = extractJsonObject(raw) as Map;
      expect(decoded['carbs'], 10);
      expect(decoded['note'], 'accolade { et } dans le texte');
    });

    test('gere les guillemets echappes dans les chaines', () {
      const raw = r'{"note": "il a dit \"bonjour\"", "carbs": 5}';
      final decoded = extractJsonObject(raw);
      expect((decoded! as Map)['carbs'], 5);
    });

    test('renvoie null lorsque aucun objet n\'est present', () {
      expect(extractJsonObject('aucun objet ici'), isNull);
      expect(extractJsonObject(''), isNull);
    });

    test('renvoie null lorsque l\'objet est incomplet', () {
      expect(extractJsonObject('{"foods": [{"name": "riz"'), isNull);
    });

    test('lit un objet imbrique complet', () {
      const raw = '{"outer": {"inner": {"deep": 3}}}';
      final decoded = extractJsonObject(raw) as Map;
      expect(((decoded['outer'] as Map)['inner'] as Map)['deep'], 3);
    });
  });

  group('parseMealAnalysis', () {
    test('lit une reponse nominale', () {
      const raw = '''
      {
        "foods": [
          {"name": "Riz blanc cuit", "estimatedWeightG": 180, "confidence": 0.86},
          {"name": "Poulet grille", "estimatedWeightG": 145, "confidence": 0.91}
        ],
        "overallConfidence": 0.88,
        "notes": "Assiette standard."
      }
      ''';

      final result = parseMealAnalysis(raw, promptVersion: 'meal-v1');

      expect(result.foods.length, 2);
      expect(result.foods.first.name, 'Riz blanc cuit');
      expect(result.foods.first.estimatedWeightG, 180);
      expect(result.foods.first.confidence, closeTo(0.86, 1e-9));
      expect(result.overallConfidence, closeTo(0.88, 1e-9));
      expect(result.notes, 'Assiette standard.');
      expect(result.promptVersion, 'meal-v1');
      expect(result.isEmpty, isFalse);
    });

    test('une liste vide est acceptee et signalee', () {
      final result = parseMealAnalysis('{"foods": [], "overallConfidence": 0, "notes": "Pas de nourriture."}');
      expect(result.isEmpty, isTrue);
      expect(result.notes, 'Pas de nourriture.');
    });

    test('une reponse sans objet JSON leve une erreur de reponse invalide', () {
      expect(
        () => parseMealAnalysis('je ne peux pas analyser cette image'),
        throwsA(isA<InvalidResponseFailure>()),
      );
    });

    test('les aliments sans nom sont ecartes', () {
      const raw = '{"foods": [{"name": "", "estimatedWeightG": 100}, {"name": "Riz", "estimatedWeightG": 100}]}';
      final result = parseMealAnalysis(raw);
      expect(result.foods.length, 1);
      expect(result.foods.first.name, 'Riz');
    });

    test('un poids negatif ou nul devient zero', () {
      const raw = '{"foods": [{"name": "Riz", "estimatedWeightG": -50}, {"name": "Pain", "estimatedWeightG": 0}]}';
      final result = parseMealAnalysis(raw);
      expect(result.foods[0].estimatedWeightG, 0);
      expect(result.foods[1].estimatedWeightG, 0);
    });

    test('un poids absurde est borne', () {
      const raw = '{"foods": [{"name": "Riz", "estimatedWeightG": 999999}]}';
      final result = parseMealAnalysis(raw);
      expect(result.foods.first.estimatedWeightG, 5000);
    });

    test('une confiance hors bornes est ramenee entre 0 et 1', () {
      const raw = '{"foods": ['
          '{"name": "Riz", "estimatedWeightG": 100, "confidence": 5},'
          '{"name": "Pain", "estimatedWeightG": 100, "confidence": -2}'
          ']}';
      final result = parseMealAnalysis(raw);
      expect(result.foods[0].confidence, 1.0);
      expect(result.foods[1].confidence, 0.0);
    });

    test('une confiance non numerique retombe sur une valeur prudente', () {
      const raw = '{"foods": [{"name": "Riz", "estimatedWeightG": 100, "confidence": "elevee"}]}';
      final result = parseMealAnalysis(raw);
      expect(result.foods.first.confidence, 0.5);
    });

    test('sans confiance globale, la moyenne des aliments est utilisee', () {
      const raw = '{"foods": ['
          '{"name": "Riz", "estimatedWeightG": 100, "confidence": 0.8},'
          '{"name": "Pain", "estimatedWeightG": 100, "confidence": 0.6}'
          ']}';
      final result = parseMealAnalysis(raw);
      expect(result.overallConfidence, closeTo(0.7, 1e-9));
    });

    test('les nombres envoyes sous forme de chaines sont acceptes', () {
      const raw = '{"foods": [{"name": "Riz", "estimatedWeightG": "180", "confidence": "0.9"}]}';
      final result = parseMealAnalysis(raw);
      expect(result.foods.first.estimatedWeightG, 180);
      expect(result.foods.first.confidence, closeTo(0.9, 1e-9));
    });

    test('la virgule decimale francaise est acceptee', () {
      const raw = '{"foods": [{"name": "Riz", "estimatedWeightG": "180,5"}]}';
      final result = parseMealAnalysis(raw);
      expect(result.foods.first.estimatedWeightG, closeTo(180.5, 1e-9));
    });

    test('un nom trop long est tronque', () {
      final longName = 'a' * 400;
      final result = parseMealAnalysis('{"foods": [{"name": "$longName", "estimatedWeightG": 100}]}');
      expect(result.foods.first.name.length, 120);
    });

    test('le nombre d\'aliments est plafonne', () {
      final foods = List.generate(60, (index) => '{"name": "Aliment $index", "estimatedWeightG": 100}').join(',');
      final result = parseMealAnalysis('{"foods": [$foods]}');
      expect(result.foods.length, 25);
    });

    test('une entree qui n\'est pas un objet est ignoree', () {
      const raw = '{"foods": ["riz", 42, null, {"name": "Pain", "estimatedWeightG": 60}]}';
      final result = parseMealAnalysis(raw);
      expect(result.foods.length, 1);
      expect(result.foods.first.name, 'Pain');
    });

    test('le champ foods manquant produit un resultat vide, sans erreur', () {
      final result = parseMealAnalysis('{"overallConfidence": 0.5}');
      expect(result.isEmpty, isTrue);
    });
  });

  group('parseLabelExtraction', () {
    test('lit une etiquette complete', () {
      const raw = '''
      {
        "productName": "Cereales au chocolat",
        "brand": "Exemple",
        "basis": "100g",
        "packageQuantity": "375 g",
        "energyKcal": 412,
        "fat": 12.5,
        "saturatedFat": 4.2,
        "carbohydrates": 66.3,
        "sugars": 24.1,
        "fiber": 5.4,
        "proteins": 7.8,
        "salt": 0.62,
        "confidence": 0.82,
        "notes": "Tableau lisible."
      }
      ''';

      final extraction = parseLabelExtraction(raw, promptVersion: 'label-v1');

      expect(extraction.productName, 'Cereales au chocolat');
      expect(extraction.brand, 'Exemple');
      expect(extraction.per100g.carbs, closeTo(66.3, 1e-9));
      expect(extraction.per100g.kcal, closeTo(412, 1e-9));
      expect(extraction.per100g.protein, closeTo(7.8, 1e-9));
      expect(extraction.per100g.salt, closeTo(0.62, 1e-9));
      expect(extraction.saturatedFat, closeTo(4.2, 1e-9));
      expect(extraction.basis, '100g');
      expect(extraction.confidence, closeTo(0.82, 1e-9));
      expect(extraction.isLowConfidence, isFalse);
    });

    test('les valeurs illisibles restent nulles plutot que devinees', () {
      const raw = '{"carbohydrates": 12, "proteins": null, "fat": null, "confidence": 0.4}';
      final extraction = parseLabelExtraction(raw);

      expect(extraction.per100g.carbs, 12);
      expect(extraction.per100g.protein, 0);
      expect(extraction.per100g.fat, 0);
      expect(extraction.isLowConfidence, isTrue);
    });

    test('une valeur negative est rejetee', () {
      const raw = '{"carbohydrates": -5, "energyKcal": 100}';
      final extraction = parseLabelExtraction(raw);
      expect(extraction.per100g.carbs, 0);
      expect(extraction.per100g.kcal, 100);
    });

    test('une valeur aberrante est rejetee', () {
      const raw = '{"carbohydrates": 999999999}';
      final extraction = parseLabelExtraction(raw);
      expect(extraction.per100g.carbs, 0);
    });

    test('la base 100 ml est conservee, toute autre valeur retombe sur 100 g', () {
      expect(parseLabelExtraction('{"basis": "100ml"}').basis, '100ml');
      expect(parseLabelExtraction('{"basis": "portion"}').basis, '100g');
      expect(parseLabelExtraction('{}').basis, '100g');
    });

    test('le nom suggere combine produit et marque', () {
      expect(
        parseLabelExtraction('{"productName": "Cereales", "brand": "Exemple"}').suggestedName,
        'Cereales — Exemple',
      );
      expect(parseLabelExtraction('{"productName": "Cereales"}').suggestedName, 'Cereales');
      expect(parseLabelExtraction('{}').suggestedName, 'Produit etiquete');
    });

    test('les chaines vides ou « null » sont traitees comme absentes', () {
      const raw = '{"productName": "", "brand": "null", "packageQuantity": "   "}';
      final extraction = parseLabelExtraction(raw);
      expect(extraction.productName, isNull);
      expect(extraction.brand, isNull);
      expect(extraction.packageQuantity, isNull);
    });

    test('une reponse sans objet JSON leve une erreur', () {
      expect(
        () => parseLabelExtraction('je ne vois pas d\'etiquette'),
        throwsA(isA<InvalidResponseFailure>()),
      );
    });
  });
}
