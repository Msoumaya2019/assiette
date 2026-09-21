/// Arbitrage entre deux versions d'une meme ligne, venues de deux appareils.
///
/// Le probleme
/// -----------
/// Deux appareils modifient la meme ligne hors ligne. Quand ils se retrouvent,
/// il faut decider laquelle garder — et surtout, il faut que **les deux
/// appareils prennent la meme decision**. Deux appareils qui se croient chacun
/// vainqueur ne convergent jamais : ils s'echangent leurs versions
/// indefiniment, et la ligne reste fausse des deux cotes.
///
/// La regle
/// --------
///   1. la modification la plus recente gagne (`updatedAt`) ;
///   2. a date egale, **la suppression gagne** ;
///   3. sinon, la plus grande empreinte de contenu gagne ;
///   4. empreintes egales : les versions sont identiques, il n'y a rien a faire.
///
/// Pourquoi ces choix
/// ------------------
/// **Aucune des trois premieres regles ne regarde quel cote est « le mien ».**
/// C'est la propriete qui fait converger : la decision ne depend que de la
/// paire, donc inverser les deux cotes inverse le verdict, et les deux appareils
/// tombent d'accord. Une regle du genre « en cas d'egalite je garde ma version »
/// est plus intuitive et **ne converge pas** : c'est le piege principal de ce
/// morceau, et c'est ce que les tests verifient en premier.
///
/// **La suppression l'emporte a date egale** parce qu'une pierre tombale existe
/// precisement pour qu'une ligne supprimee ne revienne pas. Ressusciter est le
/// defaut qu'on cherche a eviter, pas celui qu'on accepte. C'est deja la regle
/// de la restauration de sauvegarde, qui refuse de ressusciter un repas supprime
/// ici : les deux chemins ne peuvent pas dire le contraire.
///
/// **L'empreinte departage** le cas ou deux appareils ont modifie la meme ligne
/// a la meme milliseconde. Le choix est arbitraire, et il est assume : ce qui
/// compte n'est pas qu'il soit juste, mais qu'il soit **le meme des deux
/// cotes**. Elle doit porter sur le **contenu** — un identifiant ne dit rien du
/// contenu, et deux versions differentes seraient alors declarees identiques.
///
/// Ce que la regle ne fait pas
/// ---------------------------
/// - Elle ne dit rien d'une ligne presente **d'un seul cote** : ce n'est pas un
///   arbitrage, c'est une insertion. Ce cas se traite a l'appelant.
/// - Elle ne corrige pas une **horloge fausse**. Un appareil avance de trois
///   jours gagne pendant trois jours. Le remede est un horodatage venu du
///   serveur, pas une regle de plus ici : une garde « la date est dans le futur »
///   ne supprimerait pas la divergence, elle deplacerait seulement la perte sur
///   l'appareil juste. A trancher quand la synchronisation existera.
///
/// Cette regle vit **d'un seul cote**, volontairement : c'est le client qui
/// connait les deux versions et qui decide, puis qui pousse la gagnante. Un
/// serveur qui appliquerait la meme regle serait une seconde implementation a
/// tenir d'accord avec celle-ci — exactement le genre d'accord qui se defait en
/// silence.
library;

/// Tolerance de comparaison des dates, en millisecondes.
///
/// Deux horodatages egaux a la milliseconde pres viennent du meme geste : ils
/// sont traites comme une egalite. Ce n'est pas une tolerance de « presque
/// egal » — deux dates distantes d'une milliseconde restent comparees.
const int _aucuneTolerance = 0;

/// Une version d'une ligne, telle qu'un appareil la connait.
class VersionArbitrable {
  const VersionArbitrable({
    required this.updatedAt,
    required this.deletedAt,
    required this.empreinte,
  });

  /// Derniere modification, en millisecondes depuis l'epoque.
  ///
  /// **Zero signifie « inconnue »**, pas « modifiee en 1970 » : une sauvegarde
  /// ecrite avant que la colonne existe n'en porte pas, et la relire lui donne
  /// zero. Une date inconnue perd donc contre toute date connue, ce qui est le
  /// comportement voulu — mais deux dates inconnues ne se departagent pas par
  /// la date, et retombent sur l'empreinte.
  final int updatedAt;

  /// Date de suppression, ou `null` si la ligne est vivante.
  final int? deletedAt;

  /// Empreinte stable du **contenu** de la ligne.
  ///
  /// Sert d'arbitre a date egale. Elle doit etre calculee depuis le contenu, et
  /// jamais depuis un identifiant : deux versions differentes d'une meme ligne
  /// partagent leur identifiant, donc un identifiant les declarerait identiques.
  final String empreinte;

  bool get estSupprimee => deletedAt != null;

  /// Vrai si la date de modification est connue.
  bool get dateConnue => updatedAt > 0;

  @override
  String toString() =>
      'VersionArbitrable(updatedAt: $updatedAt, deletedAt: $deletedAt, '
      'empreinte: $empreinte)';
}

/// Ce qu'il faut faire de la version distante.
enum VerdictArbitrage {
  /// La version distante est la meme que la locale : ne rien ecrire.
  identiques,

  /// La version locale est la plus recente : garder la locale.
  garderLocale,

  /// La version distante l'emporte : l'ecrire.
  prendreDistante,
}

/// Decide laquelle de deux versions de la meme ligne garder.
///
/// Le verdict est **symetrique** : `arbitrer(locale: a, distante: b)` rend
/// [VerdictArbitrage.garderLocale] si et seulement si
/// `arbitrer(locale: b, distante: a)` rend [VerdictArbitrage.prendreDistante].
/// C'est cette propriete qui garantit que deux appareils convergent, et elle est
/// verifiee pour chaque paire d'un jeu de cas.
///
/// La fonction est **pure** : elle ne lit ni l'heure ni la base. L'appelant qui
/// veut dater une modification passe sa propre date.
VerdictArbitrage arbitrer({
  required VersionArbitrable locale,
  required VersionArbitrable distante,
}) {
  // 1. La plus recente gagne. Les dates inconnues (zero) perdent ici, sans cas
  //    particulier : zero est plus petit que toute date connue.
  final comparaison = _comparerDates(distante.updatedAt, locale.updatedAt);
  if (comparaison > 0) return VerdictArbitrage.prendreDistante;
  if (comparaison < 0) return VerdictArbitrage.garderLocale;

  // 2. Dates egales : une suppression l'emporte sur une ligne vivante.
  if (distante.estSupprimee != locale.estSupprimee) {
    return distante.estSupprimee
        ? VerdictArbitrage.prendreDistante
        : VerdictArbitrage.garderLocale;
  }

  // 3. Meme etat de suppression : l'empreinte departage. La comparaison porte
  //    sur les deux cotes a la fois, donc elle est symetrique.
  final ordre = distante.empreinte.compareTo(locale.empreinte);
  if (ordre > 0) return VerdictArbitrage.prendreDistante;
  if (ordre < 0) return VerdictArbitrage.garderLocale;

  // 4. Meme date, meme etat, meme empreinte : les versions sont identiques.
  return VerdictArbitrage.identiques;
}

/// Compare deux dates de modification.
///
/// Separee pour que la tolerance soit nommee a un seul endroit : le jour ou l'on
/// decidera qu'une seconde d'ecart vaut une egalite, c'est ici et nulle part
/// ailleurs.
int _comparerDates(int gauche, int droite) {
  if (gauche > droite + _aucuneTolerance) return 1;
  if (gauche < droite - _aucuneTolerance) return -1;
  return 0;
}
