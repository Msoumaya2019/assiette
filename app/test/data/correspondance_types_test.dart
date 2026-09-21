import 'dart:io';

import 'package:assiette/data/distant/correspondance_distant.dart';
import 'package:assiette/data/local/synchronisation_locale.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les types declares, confrontes aux migrations
/// ---------------------------------------------
/// `tools/check_migration_serveur.py` tient l'accord des **noms**. Il ne dit
/// rien des **types**, et c'est la que se cache une boucle silencieuse : le
/// serveur porte `eaten_at` en `timestamptz` et `is_estimate` en `boolean`, le
/// local les porte en entier. Sans conversion, les deux cotes ne decrivent
/// jamais la meme chose : l'arbitrage tranche toujours dans le meme sens, chaque
/// passage reecrit la meme ligne, et rien ne le signale.
///
/// Ce fichier confronte donc les deux declarations de types aux migrations
/// reelles, **dans les deux sens** : rien de declare qui ne soit du bon type, et
/// aucune colonne datee ou booleenne du serveur oubliee.

/// Le dossier des migrations, trouve en remontant depuis le dossier courant.
///
/// `flutter test` lance les tests depuis la racine du paquet (`app/`), donc le
/// chemin relatif serait `../backend/...`. Le chercher est plus sur qu'y croire :
/// un test qui ne trouve pas ses fichiers doit le dire, pas passer au vert.
Directory _dossierDesMigrations() {
  var dossier = Directory.current;
  for (var niveau = 0; niveau < 6; niveau++) {
    final candidat = Directory(
      '${dossier.path}${Platform.pathSeparator}backend'
      '${Platform.pathSeparator}supabase${Platform.pathSeparator}migrations',
    );
    if (candidat.existsSync()) return candidat;
    dossier = dossier.parent;
  }
  fail('migrations introuvables depuis ${Directory.current.path}');
}

/// Table serveur -> colonne -> type, tel que les migrations le declarent.
Map<String, Map<String, String>> _typesServeur() {
  final tables = <String, Map<String, String>>{};

  final motifTable = RegExp(
    r'create table if not exists\s+(?:public\.)?(\w+)\s*\(',
    caseSensitive: false,
  );
  final motifAjout = RegExp(
    r'add column if not exists\s+(\w+)\s+(\w+)',
    caseSensitive: false,
  );

  final fichiers =
      _dossierDesMigrations()
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final fichier in fichiers) {
    // Les commentaires citent des colonnes : les garder ferait lire des
    // declarations qui n'en sont pas. Meme precaution que le controle Python.
    final texte = fichier.readAsStringSync().replaceAll(
      RegExp(r'--[^\n]*'),
      '',
    );

    for (final ajout in motifAjout.allMatches(texte)) {
      final table = _tableDeLAjout(texte, ajout.start);
      if (table == null) continue;
      tables.putIfAbsent(table, () => {})[ajout.group(1)!] = ajout.group(2)!;
    }

    for (final table in motifTable.allMatches(texte)) {
      final nom = table.group(1)!;
      final fin = texte.indexOf('\n);', table.end);
      final corps = texte.substring(table.end, fin < 0 ? texte.length : fin);
      final colonnes = tables.putIfAbsent(nom, () => {});
      for (final ligne in corps.split('\n')) {
        final mots = ligne.trim().split(RegExp(r'\s+'));
        if (mots.length < 2) continue;
        if (const {
          'unique',
          'primary',
          'foreign',
          'check',
          'constraint',
        }.contains(mots.first.toLowerCase())) {
          continue;
        }
        colonnes[mots[0]] = mots[1].toLowerCase();
      }
    }
  }

  return tables;
}

/// La table que vise un `alter table`, pour l'ajout qui commence a [position].
String? _tableDeLAjout(String texte, int position) {
  final debut = texte.lastIndexOf('alter table', position);
  if (debut < 0) return null;
  final motif = RegExp(
    r'alter table\s+(?:public\.)?(\w+)',
    caseSensitive: false,
  );
  return motif.firstMatch(texte.substring(debut, position))?.group(1);
}

void main() {
  late Map<String, Map<String, String>> types;

  setUpAll(() => types = _typesServeur());

  /// Les colonnes d'une table locale, en vocabulaire serveur.
  Map<String, String> serveurDe(String tableLocale) {
    final nom = tablesDistantes[tableLocale];
    expect(nom, isNotNull, reason: '$tableLocale n\'a pas de table serveur');
    final colonnes = types[nom];
    expect(
      colonnes,
      isNotNull,
      reason: 'la table serveur `$nom` est introuvable dans les migrations',
    );
    return colonnes!;
  }

  test('les migrations ont bien ete lues', () {
    // Un lecteur qui ne trouve rien rendrait tous les tests suivants verts.
    expect(types.length, greaterThanOrEqualTo(8));
    expect(types['meals'], isNotNull);
    expect(types['meals']!.length, greaterThanOrEqualTo(18));
  });

  test('chaque colonne declaree comme datee est un timestamptz', () {
    for (final entree in colonnesDatesDistantes.entries) {
      final colonnes = serveurDe(entree.key);
      for (final locale in entree.value) {
        final distante = colonneDistante(entree.key, locale);
        expect(
          colonnes[distante],
          'timestamptz',
          reason:
              '${entree.key}.$locale est declaree datee, mais '
              '${tablesDistantes[entree.key]}.$distante est '
              '« ${colonnes[distante]} »',
        );
      }
    }
  });

  test('chaque colonne declaree comme booleenne est un boolean', () {
    for (final entree in colonnesBooleennesDistantes.entries) {
      final colonnes = serveurDe(entree.key);
      for (final locale in entree.value) {
        final distante = colonneDistante(entree.key, locale);
        expect(
          colonnes[distante],
          'boolean',
          reason:
              '${entree.key}.$locale est declaree booleenne, mais '
              '${tablesDistantes[entree.key]}.$distante est '
              '« ${colonnes[distante]} »',
        );
      }
    }
  });

  test('aucune colonne datee du serveur n\'est oubliee', () {
    _verifierAucunOubli(types, 'timestamptz', colonnesDatesDistantes);
  });

  test('aucune colonne booleenne du serveur n\'est oubliee', () {
    _verifierAucunOubli(types, 'boolean', colonnesBooleennesDistantes);
  });

  test('les colonnes de service et du serveur seul sont hors du contenu', () {
    // Le controle de completude ci-dessus les exclut : ce test dit pourquoi il
    // a le droit de le faire. Si `updated_at` entrait un jour dans le contenu,
    // il faudrait le declarer date — et cet oubli serait sinon invisible.
    for (final table in tablesSynchronisables) {
      final serveur = tablesDistantes[table.nom]!;
      for (final colonne in colonnesDeService) {
        expect(
          colonnesDatesDistantes[table.nom] ?? const <String>{},
          isNot(contains(colonne)),
          reason: '$colonne est une colonne de service, pas du contenu',
        );
      }
      expect(colonnesServeurSeules[serveur], isNotNull);
    }
  });
}

/// Le sens inverse : toute colonne du serveur d'un type donne, qui appartient au
/// contenu, doit figurer dans la declaration.
void _verifierAucunOubli(
  Map<String, Map<String, String>> types,
  String type,
  Map<String, Set<String>> declarees,
) {
  final localDe = {
    for (final entree in tablesDistantes.entries) entree.value: entree.key,
  };

  for (final entree in localDe.entries) {
    final serveur = entree.key;
    final local = entree.value;
    final horsContenu = colonnesServeurSeules[serveur] ?? const <String>{};
    for (final colonne in (types[serveur] ?? const <String, String>{}).keys) {
      if (types[serveur]![colonne] != type) continue;
      if (colonnesDeService.contains(colonne)) continue;
      if (horsContenu.contains(colonne)) continue;
      final enLocal = colonneLocale(local, colonne);
      expect(
        declarees[local] ?? const <String>{},
        contains(enLocal),
        reason:
            'le serveur porte $serveur.$colonne en $type, et rien ne le '
            'declare : la synchronisation ne convergerait jamais',
      );
    }
  }
}
