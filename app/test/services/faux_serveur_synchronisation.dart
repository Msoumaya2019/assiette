/// Un serveur en memoire, pour eprouver la convergence sans reseau.
///
/// Il porte des lignes telles quelles et ne redate rien : c'est exactement ce
/// que le service attend d'un transport. Le remplacer par le vrai client
/// Supabase ne changera pas un seul test de convergence.
library;

import 'package:assiette/data/local/synchronisation_locale.dart';
import 'package:assiette/models/synchronisation.dart';
import 'package:assiette/services/synchronisation_service.dart';

class FauxServeur implements TransportSynchronisation {
  FauxServeur({this.heure = 1700000000000})
    : _tables = {
        for (final table in tablesSynchronisables)
          table.nom: <LigneSynchronisable>[],
      };

  /// L'heure annoncee par le serveur, en millisecondes depuis l'epoque.
  int heure;

  /// Vrai si le serveur ne sait pas donner l'heure. Un transport qui ne repond
  /// pas a cette question-la ne doit pas empecher la synchronisation.
  bool heureIndisponible = false;

  final Map<String, List<LigneSynchronisable>> _tables;

  /// Tables que le serveur refuse. Sert a eprouver qu'une table en panne
  /// n'emporte pas les autres.
  final Set<String> tablesRefusees = {};

  /// Les appels recus, dans l'ordre.
  final List<String> appels = [];

  @override
  Future<int> heureServeur() async {
    if (heureIndisponible) throw StateError('heure indisponible');
    return heure;
  }

  @override
  Future<List<LigneSynchronisable>> lire(TableSynchronisable table) async {
    appels.add('lire:${table.nom}');
    _refuserSiEnPanne(table);
    return List.of(_tables[table.nom]!);
  }

  @override
  Future<void> ecrire(
    TableSynchronisable table,
    List<LigneSynchronisable> lignes,
  ) async {
    appels.add('ecrire:${table.nom}');
    _refuserSiEnPanne(table);
    final distantes = _tables[table.nom]!;
    for (final ligne in lignes) {
      distantes.removeWhere((existante) => existante.cle == ligne.cle);
      distantes.add(ligne);
    }
  }

  /// Les lignes du serveur pour une table.
  List<LigneSynchronisable> lignes(String nom) => List.of(_tables[nom]!);

  /// Une ligne du serveur, par sa cle.
  LigneSynchronisable? ligne(String nom, String cle) {
    for (final ligne in _tables[nom]!) {
      if (ligne.cle == cle) return ligne;
    }
    return null;
  }

  /// Depose une ligne, comme le ferait un autre appareil.
  void deposer(String nom, LigneSynchronisable ligne) {
    final distantes = _tables[nom]!;
    distantes.removeWhere((existante) => existante.cle == ligne.cle);
    distantes.add(ligne);
  }

  void _refuserSiEnPanne(TableSynchronisable table) {
    if (tablesRefusees.contains(table.nom)) {
      throw StateError('le serveur refuse la table ${table.nom}');
    }
  }
}
