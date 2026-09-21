/// Planification d'une synchronisation, a partir des deux etats.
///
/// Ou se situe cette couche
/// ------------------------
/// La regle d'arbitrage (`arbitrage.dart`) decide, pour **une** ligne presente
/// des deux cotes, quelle version garder. Ce fichier decide, pour **un
/// ensemble** de lignes, ce qu'il y a a envoyer et ce qu'il y a a ecrire.
///
/// La difference n'est pas cosmetique : la regle ne dit rien d'une ligne
/// presente d'un seul cote — ce n'est pas un arbitrage, c'est une insertion —
/// et c'est ici que ce cas est traite. C'est aussi ici que se pose la question
/// qui n'existe pas a l'echelle d'une ligne : **deux lignes de meme cle**.
///
/// Aucune entree/sortie
/// --------------------
/// Ce fichier ne lit ni le reseau, ni la base, ni l'heure. Il prend deux listes
/// et rend un plan. C'est ce qui permet de l'eprouver sans serveur — et c'est
/// deliberé : le jour ou un serveur existera, la partie qui peut se tromper en
/// silence sera deja tenue par des tests.
///
/// Ce que le plan ne fait pas
/// --------------------------
/// - Il ne **resout** pas une horloge fausse : il applique la regle, qui donne
///   raison a l'appareil avance. Le remede est un horodatage serveur.
/// - Il ne **compose** pas les agregats. Un repas et ses aliments sont une
///   seule ligne du point de vue de la synchronisation, parce que
///   `saveMeal` reecrit les aliments en bloc et horodate le repas dans le meme
///   geste. C'est a l'appelant de presenter l'agregat comme une ligne.
/// - Il ne **pagine** ni ne filtre : il compare ce qu'on lui donne.
library;

import 'arbitrage.dart';
import 'empreinte.dart';

/// Une ligne, telle qu'un des deux cotes de la synchronisation la voit.
///
/// La version arbitrable est construite **ici**, depuis le contenu, et jamais
/// recue de l'exterieur. C'est la meme lecon que l'affichage des glucides par
/// portion : un nombre et ce qu'il resume ne doivent pas pouvoir se contredire.
/// Ici, l'empreinte et le contenu dont elle est tiree ne peuvent pas diverger,
/// parce qu'il n'existe pas de constructeur qui les prenne separement.
class LigneSynchronisable {
  LigneSynchronisable({
    required this.cle,
    required this.updatedAt,
    required Map<String, Object?> contenu,
    this.deletedAt,
  }) : contenu = Map<String, Object?>.unmodifiable(contenu),
       version = VersionArbitrable(
         updatedAt: updatedAt,
         deletedAt: deletedAt,
         empreinte: empreinteDeContenu(contenu),
       );

  /// Identifiant stable **entre appareils**.
  ///
  /// C'est le `client_id` du schema, jamais la cle primaire locale : deux
  /// appareils generent chacun la leur, et la meme ligne n'aurait alors aucune
  /// chance de se reconnaitre d'un cote a l'autre.
  final String cle;

  /// Derniere modification, en millisecondes depuis l'epoque.
  ///
  /// Zero signifie « inconnue », comme pour la regle d'arbitrage : une ligne
  /// ecrite avant que la colonne existe n'en porte pas.
  final int updatedAt;

  /// Date de suppression, ou `null` si la ligne est vivante.
  final int? deletedAt;

  /// Le contenu de la ligne, sans son identifiant.
  final Map<String, Object?> contenu;

  /// La version, telle que la regle d'arbitrage la veut.
  final VersionArbitrable version;

  bool get estSupprimee => version.estSupprimee;

  @override
  String toString() => 'LigneSynchronisable($cle, $version)';
}

/// Ce qu'une synchronisation doit faire.
///
/// Les listes sont **triees par cle**, et non dans l'ordre ou les lignes ont ete
/// fournies : deux appareils qui comparent le meme etat obtiennent ainsi le meme
/// plan, dans le meme ordre. Sans ce tri, le plan dependrait de l'ordre des
/// lectures SQL, qui n'est garanti par rien.
class PlanDeSynchronisation {
  const PlanDeSynchronisation({
    required this.aPousser,
    required this.aAppliquer,
    required this.identiques,
  });

  /// Lignes locales a envoyer au serveur.
  ///
  /// Elles sont soit **gagnantes** d'un arbitrage, soit **absentes en face**.
  final List<LigneSynchronisable> aPousser;

  /// Lignes distantes a ecrire localement.
  ///
  /// Meme composition, en miroir.
  final List<LigneSynchronisable> aAppliquer;

  /// Cles ou les deux cotes portent deja la meme version : rien a faire.
  final List<String> identiques;

  bool get estVide => aPousser.isEmpty && aAppliquer.isEmpty;

  /// Nombre de lignes vues des deux cotes, arbitrees ou non.
  int get vuesDesDeuxCotes =>
      aPousser.length + aAppliquer.length + identiques.length;

  @override
  String toString() =>
      'PlanDeSynchronisation(aPousser: ${aPousser.length}, '
      'aAppliquer: ${aAppliquer.length}, identiques: ${identiques.length})';
}

/// Compare deux etats et rend ce qu'il faut faire pour les accorder.
///
/// Le plan est **symetrique** : appele avec `(locales: a, distantes: b)` il
/// rend, en `aPousser`, exactement les cles qu'il rend en `aAppliquer` appele
/// avec `(locales: b, distantes: a)`. C'est la propriete qui fait converger
/// deux appareils, et elle est verifiee pour chaque paire d'un jeu d'etats.
///
/// Une cle presente **des deux cotes** est arbitree ; une cle presente **d'un
/// seul cote** est une insertion, et elle est envoyee ou ecrite. Une ligne
/// locale supprimee que la distante ne connait pas est donc **poussee** : les
/// deux cotes finissent avec la meme pierre tombale, ce qui est le but. Le
/// contraire laisserait une difference invisible, et une difference invisible
/// est une difference qu'aucun test ne rattrape.
///
/// Leve si une cle apparait **deux fois du meme cote**. Deux lignes de meme cle
/// rendraient le plan dependant de l'ordre des listes : la ligne gagnante
/// dependrait de celle qui a ete lue en dernier.
PlanDeSynchronisation planifierSynchronisation({
  required List<LigneSynchronisable> locales,
  required List<LigneSynchronisable> distantes,
}) {
  final localesParCle = _indexer(locales, 'locale');
  final clesDistantes = _indexer(distantes, 'distante').keys.toSet();

  final aPousser = <LigneSynchronisable>[];
  final aAppliquer = <LigneSynchronisable>[];
  final identiques = <String>[];

  for (final distante in distantes) {
    final locale = localesParCle[distante.cle];
    if (locale == null) {
      aAppliquer.add(distante);
      continue;
    }
    switch (arbitrer(locale: locale.version, distante: distante.version)) {
      case VerdictArbitrage.prendreDistante:
        aAppliquer.add(distante);
      case VerdictArbitrage.garderLocale:
        aPousser.add(locale);
      case VerdictArbitrage.identiques:
        identiques.add(distante.cle);
    }
  }

  for (final locale in locales) {
    if (!clesDistantes.contains(locale.cle)) aPousser.add(locale);
  }

  return PlanDeSynchronisation(
    aPousser: aPousser..sort(_parCle),
    aAppliquer: aAppliquer..sort(_parCle),
    identiques: identiques..sort(),
  );
}

int _parCle(LigneSynchronisable gauche, LigneSynchronisable droite) =>
    gauche.cle.compareTo(droite.cle);

Map<String, LigneSynchronisable> _indexer(
  List<LigneSynchronisable> lignes,
  String cote,
) {
  final index = <String, LigneSynchronisable>{};
  for (final ligne in lignes) {
    if (index.containsKey(ligne.cle)) {
      throw ArgumentError(
        'Cle $cote en double : « ${ligne.cle} ». Deux lignes de meme cle '
        'rendraient le plan dependant de l\'ordre de la liste, donc la ligne '
        'gagnante dependrait de celle qui a ete lue en dernier.',
      );
    }
    index[ligne.cle] = ligne;
  }
  return index;
}
