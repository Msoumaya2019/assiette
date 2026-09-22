/// L'affichage d'un apercu, tenu a un seul endroit
/// -----------------------------------------------
/// Un ecran qui recoit un `Apercu` peut composer son texte lui-meme, et c'est
/// ainsi qu'est ne le defaut : deux ecrans annoncaient "pour 1 pot (125 g)"
/// sous le chiffre des 100 g. Le chiffre comparable est construit en un seul
/// endroit (`ligneComparable`) et le bloc qui l'affiche aussi (`ApercuValeurs`),
/// tous deux dans `ui/widgets/common.dart`.
///
/// Ce que ce fichier tient, et qu'aucun test de fonction ne peut tenir : **les
/// ecrans qui recoivent un apercu passent bien par cet endroit**. La mesure qui
/// a motive ce controle est nommee ici parce qu'elle est le sujet : un troisieme
/// ecran, celui du code-barres, composait son texte seul, et n'affichait donc
/// pas le chiffre comparable. Aucun banc ne pouvait le voir : les bancs mesurent
/// la fonction et le bloc, pas leurs appelants.
///
/// La liste des appelants est **derivee** des sources, jamais recopiee : un
/// ecran ajoute plus tard est mesure sans qu'on ait a y penser. C'est la
/// difference entre un controle qui suit le depot et un controle qui le fige.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Le dossier `lib/ui`, trouve en remontant depuis le dossier courant.
///
/// `flutter test` lance les tests depuis la racine du paquet (`app/`), donc le
/// chemin relatif serait `lib/ui`. Le chercher est plus sur qu'y croire : un
/// test qui ne trouve pas ses fichiers doit le dire, pas passer au vert.
Directory _dossierUi() {
  var dossier = Directory.current;
  for (var niveau = 0; niveau < 6; niveau++) {
    final candidat = Directory(
      '${dossier.path}${Platform.pathSeparator}lib'
      '${Platform.pathSeparator}ui',
    );
    if (candidat.existsSync()) return candidat;
    dossier = dossier.parent;
  }
  fail('dossier lib/ui introuvable depuis ${Directory.current.path}');
}

/// Le nom court d'un fichier, pour un message lisible.
String _nom(File fichier) => fichier.path.split(Platform.pathSeparator).last;

void main() {
  test('chaque ecran qui recoit un apercu passe par le point unique', () {
    final sources = _dossierUi()
        .listSync(recursive: true)
        .whereType<File>()
        .where((fichier) => fichier.path.endsWith('.dart'))
        .toList();

    // Plancher de lecture : un motif qui ne trouve plus rien doit faire tomber
    // le test, pas le laisser vert sur une liste vide.
    expect(
      sources.length,
      greaterThanOrEqualTo(10),
      reason: 'lib/ui parait vide : le dossier n a pas ete lu',
    );

    final appelants = sources
        .where(
          (fichier) => fichier.readAsStringSync().contains('apercuDePortion('),
        )
        .toList();

    // Un plancher, et non une liste recopiee : ajouter un quatrieme ecran ne
    // doit pas faire echouer ce test, mais casser le motif doit le faire.
    expect(
      appelants.length,
      greaterThanOrEqualTo(3),
      reason:
          'moins de trois ecrans recoivent un apercu : le motif ne lit plus '
          'les sources, ou un ecran a cesse de passer par lui',
    );

    final fautifs = <String>[];
    for (final fichier in appelants) {
      final source = fichier.readAsStringSync();
      final passeParLePointUnique =
          source.contains('ApercuValeurs(') ||
          source.contains('ligneComparable(');
      if (!passeParLePointUnique) fautifs.add(_nom(fichier));
    }

    expect(
      fautifs,
      isEmpty,
      reason:
          'ces ecrans composent leur texte eux-memes, donc peuvent remettre '
          'un chiffre sous l etiquette d une autre base : $fautifs',
    );
  });
}
