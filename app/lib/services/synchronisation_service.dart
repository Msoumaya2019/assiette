/// Le service qui fait converger deux appareils.
///
/// Ce qu'il fait, dans l'ordre
/// ---------------------------
/// Pour chaque table synchronisable : lire les lignes locales, lire les lignes
/// distantes, demander le plan a `models/synchronisation.dart`, appliquer les
/// versions distantes gagnantes **en une transaction**, puis pousser les
/// versions locales gagnantes.
///
/// L'ordre entre les deux n'a pas d'importance, et c'est une propriete du plan :
/// une meme cle n'est jamais a la fois a pousser et a appliquer. Les deux
/// ensembles sont disjoints, donc une coupure entre les deux ne peut pas perdre
/// une version — le passage suivant reprend ou le precedent s'est arrete. C'est
/// ce qui rend le service sur a rappeler apres une panne reseau.
///
/// Ce qu'il ne fait jamais
/// -----------------------
/// Il ne **redate** rien. Une ligne transporte sa date ; le service ne la
/// remplace ni par l'heure locale, ni par l'heure du serveur. Redater ferait de
/// chaque passage une modification : chaque appareil trouverait l'autre plus
/// recent, et les deux se renverraient la meme ligne sans fin. L'ecart
/// d'horloge entre l'appareil et le serveur est **mesure et signale**, jamais
/// applique aux dates.
///
/// Une table en echec n'arrete pas les autres
/// ------------------------------------------
/// Chaque table est synchronisee independamment. Un serveur qui refuse une
/// table laisse les cinq autres converger, et le rapport nomme celle qui a
/// echoue. Comme tout est idempotent, le passage suivant repare ce qui manque.
library;

import 'package:sqflite/sqflite.dart';

import '../core/failures.dart';
import '../data/local/synchronisation_locale.dart';
import '../models/synchronisation.dart';

/// Au-dela de cet ecart, l'horloge de l'appareil est signalee comme suspecte.
///
/// Deux minutes : assez large pour absorber une derive ordinaire et le temps
/// d'un aller-retour, assez etroit pour qu'une heure franchement fausse soit
/// vue. La valeur n'est **pas** appliquee aux dates — voir l'en-tete.
const int ecartHoraireTolerantMs = 2 * 60 * 1000;

/// Ce qu'un transport doit savoir faire, et rien de plus.
///
/// Le service ne connait que ce contrat : il ignore qu'il y a un serveur, une
/// base ou un reseau. L'implementation reelle parlera a Supabase ; l'epreuve se
/// fait contre un faux, en memoire — meme discipline que le moteur d'analyse
/// d'image.
abstract class TransportSynchronisation {
  /// L'instant du serveur, en millisecondes depuis l'epoque.
  Future<int> heureServeur();

  /// Les lignes distantes d'une table, pierres tombales comprises.
  Future<List<LigneSynchronisable>> lire(TableSynchronisable table);

  /// Ecrit ces lignes **telles quelles**, sans les redater.
  Future<void> ecrire(
    TableSynchronisable table,
    List<LigneSynchronisable> lignes,
  );
}

/// Ce qu'un passage a fait sur une table.
class RapportTable {
  const RapportTable({
    this.poussees = 0,
    this.appliquees = 0,
    this.identiques = 0,
    this.erreur,
  });

  /// Lignes locales envoyees au serveur.
  final int poussees;

  /// Lignes distantes ecrites en local.
  final int appliquees;

  /// Lignes vues des deux cotes, et deja d'accord.
  final int identiques;

  /// L'erreur qui a interrompu cette table, ou `null`.
  ///
  /// Gardee brute : c'est [panne] qui la traduit pour l'interface.
  final Object? erreur;

  bool get aEchoue => erreur != null;

  /// L'erreur traduite, sans trace technique.
  AppFailure? get panne => erreur == null ? null : AppFailure.from(erreur!);

  int get vues => poussees + appliquees + identiques;
}

/// Ce qu'un passage a fait, table par table.
class RapportSynchronisation {
  const RapportSynchronisation({required this.parTable, this.decalageMs});

  /// Dans l'ordre de [tablesSynchronisables].
  final Map<String, RapportTable> parTable;

  /// L'ecart entre l'horloge de l'appareil et celle du serveur, ou `null` si le
  /// serveur n'a pas su donner l'heure.
  final int? decalageMs;

  int get poussees => _somme((r) => r.poussees);
  int get appliquees => _somme((r) => r.appliquees);
  int get identiques => _somme((r) => r.identiques);

  /// Vrai si rien n'a eu a bouger : les deux cotes etaient deja d'accord.
  bool get estVide => poussees == 0 && appliquees == 0;

  /// Les tables qui ont echoue, dans l'ordre des tables.
  List<String> get tablesEnEchec => [
    for (final entree in parTable.entries)
      if (entree.value.aEchoue) entree.key,
  ];

  bool get aEchoue => tablesEnEchec.isNotEmpty;

  /// Vrai si l'ecart d'horloge est connu et au-dela de la tolerance.
  bool get horlogeSuspecte =>
      decalageMs != null && decalageMs!.abs() > ecartHoraireTolerantMs;

  int _somme(int Function(RapportTable) champ) =>
      parTable.values.fold(0, (total, rapport) => total + champ(rapport));
}

/// Fait converger la base locale et un serveur, table par table.
class ServiceSynchronisation {
  ServiceSynchronisation({
    required this.db,
    required this.transport,
    DateTime Function()? horloge,
  }) : _horloge = horloge ?? DateTime.now;

  final Database db;
  final TransportSynchronisation transport;

  /// L'heure de l'appareil. Injectable, pour eprouver l'ecart d'horloge sans
  /// dependre de l'horloge de la machine qui lance les tests.
  final DateTime Function() _horloge;

  /// Un passage complet.
  ///
  /// Ne leve pas : une table en echec est rapportee, les autres passent.
  Future<RapportSynchronisation> synchroniser() async {
    final decalage = await _decalage();
    final parTable = <String, RapportTable>{};
    for (final table in tablesSynchronisables) {
      parTable[table.nom] = await _synchroniserTable(table);
    }
    return RapportSynchronisation(parTable: parTable, decalageMs: decalage);
  }

  Future<RapportTable> _synchroniserTable(TableSynchronisable table) async {
    try {
      final locales = await lireLignes(db, table);
      final distantes = await transport.lire(table);
      final plan = planifierSynchronisation(
        locales: locales,
        distantes: distantes,
      );

      if (plan.aAppliquer.isNotEmpty) {
        // Une transaction : une table a moitie ecrite serait un etat que
        // personne n'a jamais produit, et que le prochain passage devrait
        // demeler.
        await db.transaction((transaction) async {
          for (final ligne in plan.aAppliquer) {
            await ecrireLigne(transaction, table, ligne);
          }
        });
      }

      if (plan.aPousser.isNotEmpty) {
        await transport.ecrire(table, plan.aPousser);
      }

      return RapportTable(
        poussees: plan.aPousser.length,
        appliquees: plan.aAppliquer.length,
        identiques: plan.identiques.length,
      );
    } on Object catch (erreur) {
      return RapportTable(erreur: erreur);
    }
  }

  /// L'ecart entre l'horloge de l'appareil et celle du serveur.
  ///
  /// Mesure au **milieu** de l'aller-retour, comme le fait un protocole de
  /// synchronisation d'horloge : sans cela, le temps de la requete serait
  /// compte comme une avance de l'appareil.
  ///
  /// Un echec rend `null` et n'interrompt rien : l'ecart est un **diagnostic**,
  /// pas une condition. Un serveur qui ne sait pas donner l'heure ne doit pas
  /// empecher la synchronisation.
  Future<int?> _decalage() async {
    try {
      final avant = _horloge().millisecondsSinceEpoch;
      final serveur = await transport.heureServeur();
      final apres = _horloge().millisecondsSinceEpoch;
      final milieu = avant + (apres - avant) ~/ 2;
      return serveur - milieu;
    } on Object {
      return null;
    }
  }
}
