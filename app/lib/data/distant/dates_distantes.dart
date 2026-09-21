/// Conversion entre l'entier local et l'horodatage du serveur.
///
/// Le local stocke des **millisecondes depuis l'epoque**, en entier : les
/// comparaisons d'arbitrage sont alors exactes et ne dependent d'aucun fuseau.
/// Le serveur porte des `timestamptz`, que PostgREST rend en ISO-8601 UTC.
///
/// Deux regles, et deux pieges fermes ici :
///
///  * **une date absente reste absente.** Elle ne devient jamais 1970 : une
///    pierre tombale nulle et une date nulle sont deux choses differentes, et
///    les confondre ferait d'une ligne jamais supprimee une ligne supprimee en
///    1970 — donc gagnante partout, et invisible.
///  * **l'ecriture se fait en UTC.** `toIso8601String()` sur une date locale
///    n'ajoute pas de `Z`, et le serveur l'interpreterait dans le fuseau de sa
///    session : deux appareils dans deux fuseaux dateraient differemment la
///    meme modification.
///
/// Une chaine non vide et illisible **leve**, elle ne rend pas `null`. Un
/// serveur qui rend une date cassee doit se voir : la traiter comme une absence
/// la ferait passer pour « date inconnue », ce qui est une valeur, et une valeur
/// fausse qui se propage est pire qu'une erreur.
library;

/// L'horodatage ISO-8601 UTC d'un entier local, ou `null` s'il est absent.
String? isoDepuisMillisecondes(int? millisecondes) => millisecondes == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(
        millisecondes,
        isUtc: true,
      ).toIso8601String();

/// L'entier local d'un horodatage serveur, ou `null` s'il est absent.
///
/// Accepte ce que PostgREST rend : une chaine ISO-8601, un entier, ou `null`.
/// Une chaine vide vaut une absence — PostgREST en rend pour une colonne nulle
/// dans certains formats de sortie.
int? millisecondesDepuisIso(Object? valeur) {
  if (valeur == null) return null;
  if (valeur is int) return valeur;
  if (valeur is String) {
    if (valeur.isEmpty) return null;
    final date = DateTime.tryParse(valeur);
    if (date == null) {
      throw FormatException('horodatage illisible : « $valeur »');
    }
    return date.toUtc().millisecondsSinceEpoch;
  }
  throw FormatException('horodatage de type inattendu : ${valeur.runtimeType}');
}
