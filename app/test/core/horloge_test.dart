import 'package:assiette/core/horloge.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ce que ces tests protegent
/// --------------------------
/// L'horloge decide de la date que porte **chaque** modification, et cette date
/// decide de quel appareil gagne quand deux versions d'une meme ligne se
/// rencontrent. Une horloge corrigee a l'envers, ou pas corrigee du tout, perd
/// des donnees sans rien signaler.
///
/// Le piege principal est muet, et c'est pour cela qu'il est eprouve ici :
/// mesurer l'ecart sur l'horloge **corrigee** rendrait zero a chaque fois. Une
/// horloge fausse de trois heures se declarerait juste, la correction
/// s'annulerait au deuxieme passage, et rien n'aurait l'air casse.
void main() {
  late int appareil;

  Horloge horloge({Future<void> Function(int)? retenir}) => Horloge(
    source: () => DateTime.fromMillisecondsSinceEpoch(appareil),
    retenir: retenir,
  );

  setUp(() => appareil = 1700000000000);

  test('sans correction, l\'heure estampillee est celle de l\'appareil', () {
    final h = horloge();

    expect(h.maintenantMs(), appareil);
    expect(h.decalageMs, 0);
  });

  test(
    'une correction deplace l\'heure estampillee, pas l\'horloge brute',
    () async {
      final h = horloge();
      // L'appareil retarde de trois heures : l'ecart mesure vaut +3 h.
      await h.corriger(3 * 3600 * 1000);

      expect(h.maintenantMs(), appareil + 3 * 3600 * 1000);
      expect(
        h.brutMs(),
        appareil,
        reason:
            'la mesure de l\'ecart se fait sur l\'horloge non corrigee. La faire '
            'sur l\'horloge corrigee rendrait un ecart nul a chaque fois, et une '
            'horloge franchement fausse se declarerait juste',
      );
    },
  );

  test('une correction negative est appliquee', () async {
    final h = horloge();
    // L'appareil avance de trois heures : l'ecart mesure vaut -3 h.
    await h.corriger(-3 * 3600 * 1000);

    expect(h.maintenantMs(), appareil - 3 * 3600 * 1000);
  });

  test(
    'un ecart sous la resolution de la mesure n\'est pas applique',
    () async {
      final h = horloge();
      // L'heure du serveur vient d'un en-tete HTTP, dont la resolution est la
      // seconde : un ecart de 900 ms ne se distingue pas d'une horloge juste.
      await h.corriger(900);

      expect(
        h.decalageMs,
        0,
        reason:
            'corriger quand meme decalerait chaque estampille d\'une seconde '
            'tiree au hasard. Appliquer du bruit n\'est pas corriger',
      );
      expect(h.maintenantMs(), appareil);
    },
  );

  test('un ecart egal a la resolution est applique', () async {
    final h = horloge();
    await h.corriger(1000);

    expect(h.decalageMs, 1000);
  });

  test('un ecart inconnu conserve la correction precedente', () async {
    final h = horloge();
    await h.corriger(3 * 3600 * 1000);
    await h.corriger(null);

    expect(
      h.decalageMs,
      3 * 3600 * 1000,
      reason:
          'jeter la mesure sur une coupure reseau ramenerait l\'appareil a son '
          'horloge fausse — le defaut qu\'on corrige, au moment ou on s\'y '
          'attend le moins',
    );
  });

  test('un ecart change est range, un ecart identique ne l\'est pas', () async {
    final ranges = <int>[];
    final h = horloge(retenir: (ms) async => ranges.add(ms));

    await h.corriger(0);
    expect(ranges, isEmpty, reason: 'un appareil juste n\'a rien a ranger');

    await h.corriger(3 * 3600 * 1000);
    expect(ranges, [3 * 3600 * 1000]);

    await h.corriger(3 * 3600 * 1000);
    expect(
      ranges,
      [3 * 3600 * 1000],
      reason:
          'reecrire la meme valeur n\'est pas un changement, et une '
          'ecriture a chaque passage serait une ecriture pour rien',
    );
  });

  test('reprendre applique un ecart range sans le reecrire', () async {
    final ranges = <int>[];
    final h = horloge(retenir: (ms) async => ranges.add(ms));

    h.reprendre(3 * 3600 * 1000);

    expect(h.decalageMs, 3 * 3600 * 1000);
    expect(h.maintenantMs(), appareil + 3 * 3600 * 1000);
    expect(
      ranges,
      isEmpty,
      reason:
          'l\'ecart vient d\'etre lu : le reecrire serait une ecriture '
          'pour rien a chaque demarrage',
    );

    // La premiere mesure identique ne le reecrit pas non plus : `reprendre` a
    // note la valeur comme deja rangee.
    await h.corriger(3 * 3600 * 1000);
    expect(ranges, isEmpty);
  });

  test('sans retenue, corriger ne leve pas', () async {
    // Une horloge sans base — le cas des tests et des objets isoles.
    final h = horloge();
    await h.corriger(3 * 3600 * 1000);

    expect(h.decalageMs, 3 * 3600 * 1000);
  });
}
