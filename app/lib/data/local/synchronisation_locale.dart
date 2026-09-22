/// Lecture et ecriture des lignes locales, pour la synchronisation.
///
/// Ou se situe cette couche
/// ------------------------
/// `models/synchronisation.dart` compare deux etats et rend un plan. Il ne sait
/// rien de SQLite. Ce fichier fait le pont : il lit une table et en fait des
/// [LigneSynchronisable], puis reecrit la version gagnante.
///
/// Le risque, et comment il est ferme
/// ----------------------------------
/// Une empreinte est aveugle a ce qu'on ne lui donne pas. Si le contenu d'un
/// repas omettait `notes`, alors deux repas differant **par leurs seules notes**
/// seraient declares identiques a date egale, et la modification cesserait de
/// circuler — sans erreur, sans trace, et sans qu'aucun test ne le voie.
///
/// Les colonnes ne sont donc **pas recopiees ici** : elles sont lues dans le
/// schema reel (`PRAGMA table_info`). Une colonne ajoutee plus tard entre dans
/// le contenu d'elle-meme. C'est la meme discipline que la liste close des
/// bancs : un ensemble ferme vaut mieux qu'une enumeration qu'on oublie de
/// mettre a jour.
///
/// Les deux colonnes de service sont exclues du contenu, parce qu'elles sont
/// portees **a cote** par [VersionArbitrable] : `updated_at` est deja la date
/// comparee, `deleted_at` est deja l'etat compare. Les remettre dans l'empreinte
/// n'ajouterait rien — l'empreinte ne sert qu'a departager des dates **egales**.
///
/// Une troisieme famille est exclue, pour une raison differente : les colonnes
/// de [colonnesLocalesSeules] — aujourd'hui `meals.photo_path` — portent une
/// valeur **propre a cet appareil**, un chemin absolu dans son dossier de
/// documents. Les faire circuler enverrait a l'autre appareil un chemin qui
/// n'existe pas chez lui, et l'ecriture locale ecraserait sa photo. Cette
/// exclusion-la est **nommee** dans la declaration, ce qui la distingue d'un
/// oubli : une colonne oubliee reste un defaut, et le controle par colonne de
/// `synchronisation_locale_test.dart` continue de la chercher.
///
/// L'agregat
/// ---------
/// Un repas et ses aliments sont **une seule ligne** : `saveMeal` reecrit les
/// aliments en bloc et horodate le repas dans le meme geste. Le contenu d'un
/// repas porte donc ses aliments, sous la cle `items`. La table `meal_items`
/// n'est pas synchronisable pour elle-meme — elle n'a ni `updated_at` ni
/// `deleted_at`, et son cycle de vie est celui de son repas.
library;

import 'package:sqflite/sqflite.dart';

import '../../models/synchronisation.dart';
import '../distant/correspondance_distant.dart';

/// Colonnes portees par [VersionArbitrable] plutot que par le contenu.
const Set<String> colonnesDeService = {'updated_at', 'deleted_at'};

/// La cle sous laquelle un agregat range ses lignes filles.
const String cleDesEnfants = 'items';

/// Une table que la synchronisation sait lire, et sa forme.
class TableSynchronisable {
  const TableSynchronisable({
    required this.nom,
    required this.colonneCle,
    this.enfant,
  });

  /// Nom de la table locale.
  final String nom;

  /// Colonne qui porte l'identifiant **stable entre appareils**.
  ///
  /// `id` partout, sauf `portions`, dont la cle est le nom de l'aliment — un
  /// choix du schema local, pas de cette couche.
  final String colonneCle;

  /// Table fille, quand la ligne est un agregat.
  final EnfantSynchronisable? enfant;
}

/// Une table fille dont le cycle de vie est celui de sa ligne parente.
class EnfantSynchronisable {
  const EnfantSynchronisable({
    required this.nom,
    required this.colonneLien,
    this.colonneCle = 'id',
  });

  final String nom;

  /// Colonne qui porte la cle du parent.
  final String colonneLien;

  /// Colonne qui porte l'identifiant **stable entre appareils** de l'enfant.
  ///
  /// Nommee plutot que supposee : le transport en a besoin pour designer la
  /// contrainte d'unicite du serveur a l'ecriture, et l'ecrire `'id'` en dur
  /// ferait dependre un accord entre deux schemas d'une convention non dite.
  final String colonneCle;
}

/// Les tables qui portent un cycle de vie complet : une date de modification et
/// une pierre tombale.
///
/// `meal_items` n'y est pas : elle n'a ni l'une ni l'autre, et son cycle de vie
/// est celui de son repas — voir [cleDesEnfants].
const List<TableSynchronisable> tablesSynchronisables = [
  TableSynchronisable(
    nom: 'meals',
    colonneCle: 'id',
    enfant: EnfantSynchronisable(nom: 'meal_items', colonneLien: 'meal_id'),
  ),
  TableSynchronisable(nom: 'templates', colonneCle: 'id'),
  TableSynchronisable(nom: 'favorites', colonneCle: 'id'),
  TableSynchronisable(nom: 'pesees', colonneCle: 'id'),
  TableSynchronisable(nom: 'mesures', colonneCle: 'id'),
  TableSynchronisable(nom: 'portions', colonneCle: 'cle'),
];

/// Lit toutes les lignes d'une table, pretes a etre comparees.
///
/// Les pierres tombales sont **incluses** : une ligne supprimee doit etre
/// comparee comme les autres, sinon une suppression ne se propagerait jamais.
Future<List<LigneSynchronisable>> lireLignes(
  DatabaseExecutor db,
  TableSynchronisable table,
) async {
  final colonnes = await colonnesDe(db, table.nom);
  final lignes = await db.query(table.nom);

  final resultat = <LigneSynchronisable>[];
  for (final ligne in lignes) {
    final contenu = contenuDe(
      colonnes,
      ligne,
      table.colonneCle,
      table: table.nom,
    );
    final enfant = table.enfant;
    if (enfant != null) {
      contenu[cleDesEnfants] = await _lireEnfants(
        db,
        enfant,
        ligne[table.colonneCle],
      );
    }
    resultat.add(
      LigneSynchronisable(
        cle: ligne[table.colonneCle]! as String,
        updatedAt: (ligne['updated_at'] as int?) ?? 0,
        deletedAt: ligne['deleted_at'] as int?,
        contenu: contenu,
      ),
    );
  }
  return resultat;
}

/// Ecrit une version gagnante, en remplacant la ligne et ses enfants.
///
/// L'ecriture est un **remplacement**, jamais une fusion : la ligne gagnante est
/// celle qu'un arbitrage a designee, et melanger deux versions produirait une
/// troisieme que personne n'a jamais vue.
///
/// Une exception a ce remplacement, et une seule : les colonnes de
/// [colonnesLocalesSeules] ne viennent pas de la ligne distante, elles sont
/// **relues** dans la base et remises telles quelles. `insert` avec
/// `ConflictAlgorithm.replace` supprime la ligne puis la reinsere : une colonne
/// absente du contenu retomberait a `NULL`. Pour `meals.photo_path`, cela
/// effacerait la photo de l'utilisateur a chaque passage — sans erreur, et sans
/// que rien ne le signale.
///
/// Quand la ligne n'existe pas encore localement, il n'y a rien a relire : la
/// colonne reste absente et vaut `NULL`. C'est exact — cet appareil-la n'a pas
/// cette photo.
Future<void> ecrireLigne(
  DatabaseExecutor db,
  TableSynchronisable table,
  LigneSynchronisable ligne,
) async {
  final charge = Map<String, Object?>.from(ligne.contenu)
    ..remove(cleDesEnfants);

  final localesSeules = colonnesLocalesSeulesDe(table.nom);
  if (localesSeules.isNotEmpty) {
    final existante = await db.query(
      table.nom,
      columns: localesSeules.toList()..sort(),
      where: '${table.colonneCle} = ?',
      whereArgs: [ligne.cle],
      limit: 1,
    );
    if (existante.isNotEmpty) charge.addAll(existante.first);
  }

  await db.insert(table.nom, {
    table.colonneCle: ligne.cle,
    'updated_at': ligne.updatedAt,
    'deleted_at': ligne.deletedAt,
    ...charge,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  final enfant = table.enfant;
  if (enfant == null) return;

  // Reecriture en bloc, comme `_ecrireItems` : plus simple et plus sur qu'un
  // differentiel, et le volume par repas reste faible.
  await db.delete(
    enfant.nom,
    where: '${enfant.colonneLien} = ?',
    whereArgs: [ligne.cle],
  );
  final enfants = ligne.contenu[cleDesEnfants];
  if (enfants is! List) return;
  final lot = db.batch();
  for (final element in enfants) {
    lot.insert(enfant.nom, {
      ...(element! as Map).cast<String, Object?>(),
      enfant.colonneLien: ligne.cle,
    });
  }
  await lot.commit(noResult: true);
}

/// Les colonnes d'une table, telles que le schema les declare.
///
/// Lues dans la base et non recopiees : une colonne ajoutee plus tard entre dans
/// le contenu d'elle-meme, au lieu de disparaitre en silence.
Future<List<String>> colonnesDe(DatabaseExecutor db, String table) async {
  final description = await db.rawQuery('PRAGMA table_info($table)');
  return [for (final colonne in description) colonne['name']! as String];
}

/// Le contenu d'une ligne : tout sauf la cle, les colonnes de service, et les
/// colonnes qui restent sur l'appareil.
///
/// Fonction separee, et **pure**, pour que la regle d'exclusion soit visible et
/// eprouvable sans base.
///
/// [table] est le nom de la table en vocabulaire **local** : c'est lui qui
/// designe les colonnes de [colonnesLocalesSeules]. Le passer plutot que de le
/// deduire evite qu'un appelant oublie la troisieme famille d'exclusions.
Map<String, Object?> contenuDe(
  List<String> colonnes,
  Map<String, Object?> ligne,
  String colonneCle, {
  required String table,
}) {
  final localesSeules = colonnesLocalesSeulesDe(table);
  final contenu = <String, Object?>{};
  for (final colonne in colonnes) {
    if (colonne == colonneCle) continue;
    if (colonnesDeService.contains(colonne)) continue;
    if (localesSeules.contains(colonne)) continue;
    contenu[colonne] = ligne[colonne];
  }
  return contenu;
}

Future<List<Map<String, Object?>>> _lireEnfants(
  DatabaseExecutor db,
  EnfantSynchronisable enfant,
  Object? cleParent,
) async {
  final lignes = await db.query(
    enfant.nom,
    where: '${enfant.colonneLien} = ?',
    whereArgs: [cleParent],
  );
  final colonnes = await colonnesDe(db, enfant.nom);
  return [
    for (final ligne in lignes)
      contenuDe(colonnes, ligne, enfant.colonneLien, table: enfant.nom),
  ];
}
