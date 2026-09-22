/// L'heure qui sert a estampiller une modification.
///
/// Le probleme
/// -----------
/// La synchronisation arbitre deux versions d'une meme ligne a leur **date de
/// modification** (`models/arbitrage.dart`). Cette date est posee par
/// l'appareil. Un appareil dont l'horloge avance de trois jours gagne donc
/// **tous** les arbitrages pendant trois jours : il ecrase les modifications de
/// l'autre appareil, et rien ne le signale. L'inverse est aussi faux — un
/// appareil en retard perd tout ce qu'il ecrit.
///
/// Le remede, et pourquoi c'est celui-la
/// -------------------------------------
/// Estampiller avec l'heure du **serveur**. La note de conception
/// d'`arbitrage.dart` l'avait nomme avant que le besoin n'existe, et avait
/// ecarte l'autre candidat : « une garde "la date est dans le futur" ne
/// supprimerait pas la divergence, elle deplacerait seulement la perte sur
/// l'appareil juste ».
///
/// L'application doit pourtant pouvoir ecrire **hors ligne** : on ne peut pas
/// demander l'heure a chaque ecriture. On retient donc l'**ecart** mesure
/// pendant un passage reussi, et on l'applique a l'horloge de l'appareil.
///
/// Deux horloges en une, et pourquoi
/// ---------------------------------
/// [brutMs] est l'horloge de l'appareil, non corrigee. [maintenantMs] est
/// l'heure a estampiller. La mesure de l'ecart doit se faire sur [brutMs] :
/// mesurer sur l'horloge corrigee rendrait un ecart **nul** a chaque fois, et
/// une horloge franchement fausse se declarerait juste. C'est le piege
/// principal de ce morceau, et il est muet.
///
/// Ce que cette classe ne corrige pas
/// ----------------------------------
/// Seules les dates d'**arbitrage** passent par ici — `updated_at` et
/// `deleted_at`. Les dates que l'utilisateur choisit ou voit, comme `eaten_at`
/// ou `mesure_le`, n'y passent pas : elles disent ce que l'utilisateur a vecu, et
/// l'heure du serveur n'en sait rien.
///
/// Elle ne **redate** jamais une ligne existante : une date posee une fois
/// voyage telle quelle. Redater ferait de chaque passage une modification, et
/// les deux appareils se renverraient la meme ligne sans fin.
library;

/// En deca de cet ecart, on ne corrige pas : l'ecart est indiscernable de zero.
///
/// Ce n'est pas une prudence, c'est la **resolution de la mesure**. L'heure du
/// serveur vient de l'en-tete HTTP `Date` (`TransportSupabase.heureServeur`),
/// dont la resolution est la seconde : l'ecart calcule porte donc une
/// incertitude d'une demi-seconde, et un ecart d'une seconde ne se distingue pas
/// d'une horloge juste.
///
/// Corriger quand meme decalerait **chaque** estampille d'un appareil pourtant
/// juste, d'une seconde tiree au hasard. Appliquer du bruit n'est pas corriger.
const int ecartMesurableMs = 1000;

/// L'horloge de l'appareil, corrigee de l'ecart mesure avec le serveur.
class Horloge {
  Horloge({DateTime Function()? source, Future<void> Function(int)? retenir})
    : _source = source ?? DateTime.now,
      _retenir = retenir;

  /// L'horloge de l'appareil, telle quelle.
  final DateTime Function() _source;

  /// Ou ranger l'ecart, pour qu'il survive au redemarrage.
  ///
  /// `null` : nulle part. C'est le cas des tests, qui n'ont pas de base.
  ///
  /// Un ecart n'est pas une donnee d'utilisateur, c'est un **etat de
  /// l'appareil** : il vaut pour cet appareil-ci, et il doit etre range la ou il
  /// ne voyage pas. Voir `BackupService`, qui l'ecarte des sauvegardes.
  Future<void> Function(int)? _retenir;

  int _decalageMs = 0;

  /// L'ecart que l'on sait deja range.
  ///
  /// Distinguer « l'ecart applique » de « l'ecart range » evite d'ecrire a chaque
  /// passage : la mesure d'un appareil juste vaut zero, et reecrire zero a chaque
  /// synchronisation serait une ecriture pour rien. Une ecriture ne se justifie
  /// que par un **changement**.
  int _retenu = 0;

  /// L'ecart applique, en millisecondes. Zero : l'horloge de l'appareil.
  int get decalageMs => _decalageMs;

  /// L'horloge de l'appareil, **non corrigee**.
  ///
  /// C'est elle qui sert a mesurer l'ecart avec le serveur, et elle seule : voir
  /// l'en-tete.
  int brutMs() => _source().millisecondsSinceEpoch;

  /// L'heure a estampiller sur une modification.
  int maintenantMs() => brutMs() + _decalageMs;

  /// Cable la retenue, une fois la base ouverte.
  ///
  /// Posee apres coup parce qu'elle ecrit en base : la construire avant
  /// l'ouverture demanderait une base qui n'existe pas encore.
  void retenirAvec(Future<void> Function(int) retenir) => _retenir = retenir;

  /// Reprend un ecart range, **sans le reecrire**.
  ///
  /// Appelee a l'ouverture, sur ce qui vient d'etre lu : le reecrire serait une
  /// ecriture pour rien, a chaque demarrage. Elle note aussi la valeur comme
  /// « deja rangee », sans quoi la premiere mesure identique la reecrirait.
  void reprendre(int? decalageMs) {
    _decalageMs = decalageMs ?? 0;
    _retenu = _decalageMs;
  }

  /// Applique un ecart mesure.
  ///
  /// Un ecart **inconnu** (`null` : le serveur n'a pas su donner l'heure)
  /// conserve la mesure precedente au lieu de la jeter. Le contraire ramenerait
  /// l'appareil a son horloge fausse a la premiere coupure reseau — c'est-a-dire
  /// au defaut qu'on corrige, et au moment ou l'on s'y attend le moins.
  ///
  /// Le prix est borne et connu : si l'utilisateur regle l'horloge de son
  /// telephone entre deux passages, l'ecart range devient faux jusqu'au premier
  /// passage reussi. Une horloge ne se regle pas souvent, et ce passage arrive
  /// vite.
  ///
  /// L'ecriture n'a lieu que si la valeur **change** : un appareil juste mesure
  /// zero a chaque passage, et n'a rien a ranger.
  Future<void> corriger(int? decalageMs) async {
    if (decalageMs != null) {
      _decalageMs = decalageMs.abs() < ecartMesurableMs ? 0 : decalageMs;
    }

    final retenir = _retenir;
    if (retenir == null || _retenu == _decalageMs) return;

    _retenu = _decalageMs;
    await retenir(_decalageMs);
  }
}
