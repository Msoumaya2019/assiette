/// Empreinte stable du **contenu** d'une ligne, pour l'arbitrage.
///
/// A quoi elle sert
/// ----------------
/// `VersionArbitrable.empreinte` departage deux versions quand la date et
/// l'etat de suppression sont identiques. Deux contenus **egaux** doivent donc
/// rendre la **meme** empreinte, et deux contenus **differents** deux
/// empreintes differentes. Le premier point est une exigence de correction : une
/// empreinte instable ferait passer une ligne inchangee pour modifiee, et la
/// synchronisation pousserait sans fin des lignes qui n'ont pas bouge.
///
/// Pourquoi pas un hachage
/// -----------------------
/// Un hachage bornerait la taille, au prix d'une dependance (`crypto`) pour un
/// besoin qui tient en quelques lignes, et il rendrait l'empreinte **opaque** :
/// devant deux empreintes differentes, on ne saurait pas dire ce qui differe.
/// La forme canonique ci-dessous se lit, se compare et se journalise.
///
/// Le format
/// ---------
/// Chaque champ est precede de sa **longueur** : `<n>:<valeur>`. C'est ce qui
/// rend le format non ambigu **par construction**, sans aucun echappement. Une
/// concatenation nue confondrait `{'a': 'bc'}` et `{'ab': 'c'}` ; ici, non.
///
/// Chaque valeur porte une **etiquette de tete** (`s`, `d`, `b`…), pour que la
/// chaine `'1'` et le nombre `1` ne rendent pas la meme chose.
///
/// Les cles d'un objet sont **triees** : l'ordre d'insertion d'une `Map` n'est
/// pas une information, et deux appareils ne l'ont pas forcement le meme.
/// L'ordre d'une **liste**, lui, est conserve — il fait partie du contenu.
///
/// Ce que la fonction refuse
/// -------------------------
/// Un type qu'elle ne sait pas representer **leve**, au lieu de retomber sur
/// `toString()`. C'est deliberе : le `toString()` par defaut d'un objet contient
/// son adresse memoire, donc deux executions du meme programme rendraient deux
/// empreintes differentes pour le meme contenu. Une empreinte qui change toute
/// seule est pire qu'une erreur — elle ne se voit qu'a la synchronisation
/// suivante, et elle ressemble a une modification de l'utilisateur.
library;

/// Rend la forme canonique du contenu d'une ligne.
///
/// Le resultat ne contient aucune information d'identite : ni la cle de la
/// ligne, ni un horodatage. Deux lignes de contenu egal rendent la meme chose,
/// meme si ce sont deux lignes differentes.
String empreinteDeContenu(Map<String, Object?> contenu) {
  final tampon = StringBuffer();
  _ecrireObjet(tampon, contenu);
  return tampon.toString();
}

/// Etiquettes de tete, une par type representable.
const String _teteNull = 'n';
const String _teteBooleen = 'b';
const String _teteNombre = 'd';
const String _teteTexte = 's';
const String _teteDate = 't';
const String _teteListe = 'l';
const String _teteObjet = 'm';

void _ecrireObjet(StringBuffer tampon, Map<String, Object?> objet) {
  tampon.write(_teteObjet);
  final cles = objet.keys.toList()..sort();
  _ecrireEntier(tampon, cles.length);
  for (final cle in cles) {
    _ecrireTexte(tampon, cle);
    _ecrireValeur(tampon, objet[cle]);
  }
}

void _ecrireValeur(StringBuffer tampon, Object? valeur) {
  if (valeur == null) {
    tampon.write(_teteNull);
    return;
  }
  if (valeur is bool) {
    tampon.write(_teteBooleen);
    tampon.write(valeur ? '1' : '0');
    return;
  }
  if (valeur is num) {
    tampon.write(_teteNombre);
    _ecrireTexte(tampon, _nombreCanonique(valeur));
    return;
  }
  if (valeur is String) {
    tampon.write(_teteTexte);
    _ecrireTexte(tampon, valeur);
    return;
  }
  if (valeur is DateTime) {
    tampon.write(_teteDate);
    // En UTC, et sous une forme unique : deux appareils dans deux fuseaux
    // decrivent le meme instant, donc doivent rendre la meme empreinte.
    _ecrireTexte(tampon, valeur.toUtc().toIso8601String());
    return;
  }
  if (valeur is List) {
    tampon.write(_teteListe);
    _ecrireEntier(tampon, valeur.length);
    for (final element in valeur) {
      _ecrireValeur(tampon, element);
    }
    return;
  }
  if (valeur is Map) {
    _ecrireObjet(tampon, valeur.cast<String, Object?>());
    return;
  }
  throw ArgumentError.value(
    valeur,
    'valeur',
    'Type non representable dans une empreinte : ${valeur.runtimeType}. '
        'Un `toString()` par defaut contient l\'adresse de l\'objet, donc deux '
        'executions rendraient deux empreintes differentes pour le meme '
        'contenu. Convertir la valeur en texte, en nombre ou en liste.',
  );
}

/// Ecrit une longueur, suivie de `:`.
void _ecrireEntier(StringBuffer tampon, int valeur) {
  tampon.write(valeur);
  tampon.write(':');
}

/// Ecrit un texte precede de sa longueur, en **unites UTF-16**.
///
/// `String.length` compte les unites UTF-16, ni des octets ni des points de
/// code. Le choix est delibere : c'est la seule de ces mesures qui soit la meme
/// en Dart et en JavaScript, donc la seule qu'une reimplementation cote serveur
/// pourrait reproduire a l'identique.
void _ecrireTexte(StringBuffer tampon, String valeur) {
  _ecrireEntier(tampon, valeur.length);
  tampon.write(valeur);
}

/// Forme canonique d'un nombre.
///
/// Deux ecritures de la meme valeur doivent rendre la meme chose : `1` (entier)
/// et `1.0` (flottant) viennent souvent de la meme donnee — l'un lu depuis
/// SQLite, l'autre depuis JSON — et les separer ferait passer une ligne
/// inchangee pour modifiee. `-0.0` et `0.0` sont la meme valeur et rendent donc
/// la meme chose.
///
/// Au-dela de 2^53, un flottant ne represente plus tous les entiers : la forme
/// entiere n'est alors plus appliquee, et la valeur garde sa forme flottante.
String _nombreCanonique(num valeur) {
  if (valeur is int) return valeur.toString();
  final flottant = valeur.toDouble();
  if (flottant.isNaN) return 'nan';
  if (flottant.isInfinite) return flottant.isNegative ? '-inf' : 'inf';
  if (flottant == 0) return '0';
  if (flottant == flottant.roundToDouble() && flottant.abs() < 1e15) {
    return flottant.toInt().toString();
  }
  return flottant.toString();
}
