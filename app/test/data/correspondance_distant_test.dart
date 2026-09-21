import 'package:assiette/data/distant/correspondance_distant.dart';
import 'package:assiette/data/local/synchronisation_locale.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ce que ce fichier tient, et ce qu'il ne tient pas
/// -------------------------------------------------
/// L'accord entre la declaration et les migrations serveur est tenu **hors de
/// Dart**, par `tools/check_migration_serveur.py`, qui lit ce fichier et
/// confronte les deux schemas dans les deux sens. Le refaire ici serait un
/// second controle a maintenir pour la meme propriete.
///
/// Ce qui se teste ici est different : le **comportement** des deux fonctions
/// que le transport appellera, et les deux accords qui se verifient sans lire
/// de fichier — chaque table synchronisable a une destination, et la cle d'une
/// ligne ne peut pas etre une colonne que le serveur remplit lui-meme.
void main() {
  group('Le nom d\'une colonne chez le serveur', () {
    test('une colonne non renommee passe telle quelle', () {
      expect(colonneDistante('meals', 'name'), 'name');
      expect(colonneDistante('meals', 'eaten_at'), 'eaten_at');
      expect(colonneDistante('portions', 'grams'), 'grams');
    });

    test('les renommages declares sont appliques', () {
      expect(colonneDistante('pesees', 'poids_kg'), 'weight_kg');
      expect(colonneDistante('pesees', 'mesure_le'), 'measured_at');
      expect(colonneDistante('mesures', 'type'), 'kind');
      expect(colonneDistante('mesures', 'valeur_cm'), 'value_cm');
      expect(colonneDistante('favorites', 'payload_json'), 'payload');
      expect(colonneDistante('templates', 'items_json'), 'items');
      expect(colonneDistante('meal_items', 'portion'), 'portion_size');
    });

    test('un renommage ne vaut que pour sa table', () {
      // `mesure_le` est renomme dans `pesees` et dans `mesures`, mais une
      // colonne du meme nom ailleurs ne doit pas l'etre par contagion.
      expect(renommagesDistants.containsKey('meals.mesure_le'), isFalse);
      expect(colonneDistante('meals', 'mesure_le'), 'mesure_le');
    });
  });

  group('La cle qui reconnait une ligne d\'un appareil a l\'autre', () {
    test('l\'identifiant local devient client_id', () {
      for (final table in ['meals', 'meal_items', 'templates', 'favorites']) {
        expect(colonneCleDistante(table, 'id'), 'client_id', reason: table);
      }
      expect(colonneCleDistante('pesees', 'id'), 'client_id');
      expect(colonneCleDistante('mesures', 'id'), 'client_id');
    });

    test('la cle de portions reste cle', () {
      // Son identifiant local est deja le nom de l'aliment : le renommer
      // ferait diverger la cle primaire `(user_id, cle)` du serveur.
      expect(colonneCleDistante('portions', 'cle'), 'cle');
    });
  });

  group('Les deux declarations ne peuvent pas se contredire', () {
    test('chaque table synchronisable a une destination serveur', () {
      for (final table in tablesSynchronisables) {
        expect(
          tablesDistantes.containsKey(table.nom),
          isTrue,
          reason:
              '${table.nom} est synchronisable mais n\'a pas de table serveur '
              'declaree : la synchronisation l\'ignorerait en silence',
        );
      }
    });

    test('la cle d\'une ligne n\'est jamais une colonne du serveur seul', () {
      // Si la cle etait une colonne que le serveur remplit lui-meme — son
      // `id`, un `user_id` — l'appareil ne pourrait pas la connaitre hors
      // ligne, et ne reconnaitrait donc pas la ligne qu'il a creee.
      for (final table in tablesSynchronisables) {
        final serveur = tablesDistantes[table.nom];
        if (serveur == null) continue;
        final cle = colonneCleDistante(table.nom, table.colonneCle);
        expect(
          colonnesServeurSeules[serveur] ?? const <String>{},
          isNot(contains(cle)),
          reason: 'la cle de ${table.nom} est declaree colonne du serveur seul',
        );
      }
    });

    test('aucune table synchronisable n\'est declaree serveur seul', () {
      final synchronisables = {
        for (final table in tablesSynchronisables) tablesDistantes[table.nom],
      };
      expect(
        synchronisables.intersection(tablesEntierementDistantes),
        isEmpty,
        reason:
            'une table declaree des deux cotes serait synchronisee par une '
            'moitie du code et ignoree par l\'autre',
      );
    });
  });
}
