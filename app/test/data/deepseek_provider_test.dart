import 'dart:convert';
import 'dart:typed_data';

import 'package:assiette/core/failures.dart';
import 'package:assiette/data/vision/deepseek_provider.dart';
import 'package:assiette/data/vision/vision_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Ces tests portent sur la requete **reellement transmise**, pas sur des
/// constantes lues dans le code. C'est la seule facon de voir qu'un champ a
/// cesse d'etre envoye : un test qui relirait le source passerait au vert le
/// jour ou le champ disparait.
///
/// La reponse de repas est volontairement exploitable : `analyzeMeal` refuse un
/// resultat vide, donc une reponse vide ferait echouer le test pour une raison
/// qui n'a rien a voir avec ce qu'il mesure.
const _repas =
    '{"foods":[{"name":"Riz blanc cuit","estimatedWeightG":150,'
    '"confidence":0.8}],"overallConfidence":0.8}';

const _etiquette =
    '{"carbohydrates":28,"proteins":2.7,"fat":0.3,'
    '"energyKcal":130,"confidence":0.9}';

const _cle = 'cle-de-test-0123456789';

String _enveloppe(String contenu) => jsonEncode({
  'choices': [
    {
      'message': {'content': contenu},
    },
  ],
});

/// Banc d'essai : enregistre chaque requete emise, puis repond une valeur fixe.
class _Banc {
  _Banc({this.contenu = _repas, this.statut = 200}) {
    provider = DeepSeekVisionProvider(
      apiKey: _cle,
      client: MockClient((requete) async {
        requetes.add(requete);
        if (statut != 200) {
          return http.Response(
            jsonEncode({
              'error': {'message': 'refuse par le fournisseur'},
            }),
            statut,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(
          _enveloppe(contenu),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
  }

  final String contenu;
  final int statut;
  final List<http.Request> requetes = [];
  late final DeepSeekVisionProvider provider;

  Map<String, dynamic> get corps =>
      jsonDecode(requetes.single.body) as Map<String, dynamic>;

  /// Les blocs du message utilisateur, types.
  ///
  /// Passer par un getter type evite les acces sur `dynamic`, que le projet
  /// refuse (`avoid_dynamic_calls`) : un acces dynamique ne serait pas verifie a
  /// la compilation, donc une faute de frappe dans une cle passerait pour un
  /// `null` et le test mesurerait autre chose que ce qu'il annonce.
  List<Map<String, dynamic>> get blocsUtilisateur {
    final messages = corps['messages'] as List<dynamic>;
    final contenu = (messages[1] as Map<String, dynamic>)['content'];
    return (contenu as List<dynamic>).cast<Map<String, dynamic>>();
  }

  /// En-tetes d'une requete, en minuscules pour ne pas dependre de la casse.
  Map<String, String> enTetes() => {
    for (final entree in requetes.single.headers.entries)
      entree.key.toLowerCase(): entree.value,
  };
}

void main() {
  final image = Uint8List.fromList(List<int>.generate(64, (i) => i));

  group('transport de la requete', () {
    test(
      'le mode reflexion est desactive et la temperature transmise',
      () async {
        final banc = _Banc();
        await banc.provider.analyzeMeal(MealAnalysisRequest(image: image));

        // Le fournisseur active la reflexion par defaut : ne rien envoyer
        // reviendrait a la payer.
        expect(banc.corps['thinking'], {'type': 'disabled'});
        expect(banc.corps['temperature'], 0.2);
      },
    );

    test('la temperature de l\'etiquette suit la meme regle', () async {
      final banc = _Banc(contenu: _etiquette);
      await banc.provider.analyzeLabel(LabelAnalysisRequest(image: image));

      expect(banc.corps['thinking'], {'type': 'disabled'});
      expect(banc.corps['temperature'], 0.1);
    });

    test('le modele et le format JSON sont transmis', () async {
      final banc = _Banc();
      await banc.provider.analyzeMeal(MealAnalysisRequest(image: image));

      expect(banc.corps['model'], 'deepseek-flash');
      expect(banc.corps['response_format'], {'type': 'json_object'});
    });

    test('l\'image part en data URL et le texte precede l\'image', () async {
      final banc = _Banc();
      await banc.provider.analyzeMeal(MealAnalysisRequest(image: image));

      final blocs = banc.blocsUtilisateur;
      expect(blocs.first['type'], 'text');
      expect(blocs[1]['type'], 'image_url');

      final imageEnvoyee = blocs[1]['image_url'] as Map<String, dynamic>;
      expect(imageEnvoyee['url'], startsWith('data:image/jpeg;base64,'));
      expect(imageEnvoyee['detail'], 'high');
    });

    test('une seconde image ajoute un second bloc', () async {
      final banc = _Banc();
      await banc.provider.analyzeMeal(
        MealAnalysisRequest(image: image, secondImage: image),
      );

      final blocs = banc.blocsUtilisateur;
      expect(blocs, hasLength(3));
      expect(blocs[2]['type'], 'image_url');
    });

    test('la cle part en en-tete et jamais dans le corps', () async {
      final banc = _Banc();
      await banc.provider.analyzeMeal(MealAnalysisRequest(image: image));

      expect(banc.enTetes()['authorization'], 'Bearer $_cle');
      // Une cle recopiee dans le corps finirait dans les journaux du
      // fournisseur et dans toute trace de la requete.
      expect(banc.requetes.single.body.contains(_cle), isFalse);
    });
  });

  group('erreurs du fournisseur', () {
    test('un 401 est signale comme cle refusee, sans reessai', () async {
      final banc = _Banc(statut: 401);

      await expectLater(
        banc.provider.analyzeMeal(MealAnalysisRequest(image: image)),
        throwsA(
          isA<MissingCredentialFailure>().having(
            (e) => e.rejected,
            'rejected',
            isTrue,
          ),
        ),
      );
      // Une cle refusee ne se retente pas : trois appels identiques seraient
      // trois refus payes.
      expect(banc.requetes, hasLength(1));
    });

    test('un 429 est signale comme limite de debit, sans reessai', () async {
      final banc = _Banc(statut: 429);

      await expectLater(
        banc.provider.analyzeMeal(MealAnalysisRequest(image: image)),
        throwsA(isA<RateLimitFailure>()),
      );
      expect(banc.requetes, hasLength(1));
    });

    test('une cle absente n\'emet aucune requete', () async {
      final banc = _Banc();
      final sansCle = DeepSeekVisionProvider(
        apiKey: '   ',
        client: MockClient((requete) async {
          banc.requetes.add(requete);
          return http.Response(_enveloppe(_repas), 200);
        }),
      );

      await expectLater(
        sansCle.analyzeMeal(MealAnalysisRequest(image: image)),
        throwsA(isA<MissingCredentialFailure>()),
      );
      expect(banc.requetes, isEmpty);
    });
  });
}
