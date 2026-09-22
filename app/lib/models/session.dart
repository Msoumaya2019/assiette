/// Une session de compte, telle que le serveur d'authentification la rend.
///
/// Ce que ce modele porte, et ce qu'il ne porte pas
/// ------------------------------------------------
/// Le mot de passe, jamais : il n'a aucune raison de survivre a la requete qui
/// l'a transporte. Le garder en memoire, c'est le garder jusqu'au prochain
/// vidage, et le rendre disponible a tout ce qui sait lire un objet en memoire.
///
/// L'adresse electronique, oui — et ce point a d'abord ete ecrit dans l'autre
/// sens. Le raisonnement d'alors etait : « elle n'est pas necessaire a la
/// synchronisation ». C'etait vrai, et c'etait repondre a cote. La question
/// n'est pas ce dont la synchronisation a besoin, mais ce qu'un ecran doit
/// pouvoir dire : une section « Compte » qui ne saurait pas **de quel compte**
/// il s'agit ne servirait a rien, et le seul autre identifiant disponible est un
/// uuid, qui ne dit rien a personne.
///
/// L'adresse se range donc dans le trousseau du systeme, avec les jetons — le
/// meme endroit protege — et jamais dans la base locale.
library;

class Session {
  const Session({
    required this.jetonAcces,
    required this.jetonRafraichissement,
    required this.expireLe,
    required this.utilisateur,
    this.adresse,
  });

  /// Le jeton qui accompagne chaque requete de donnees.
  final String jetonAcces;

  /// Le jeton qui permet d'en obtenir un autre **sans mot de passe**.
  ///
  /// Il vit plus longtemps que [jetonAcces] : c'est lui, et lui seul, qui est
  /// conserve entre deux lancements de l'application.
  final String jetonRafraichissement;

  /// L'instant d'expiration de [jetonAcces], en millisecondes depuis l'epoque.
  ///
  /// **Zero veut dire « inconnu »**, jamais « 1970 » : c'est la convention du
  /// projet pour une date absente. Voir [estExpireeA].
  final int expireLe;

  /// L'identifiant du compte, tel que les politiques RLS l'attendent.
  final String utilisateur;

  /// L'adresse du compte, quand le serveur l'annonce.
  ///
  /// **Optionnelle**, et c'est le serveur qui le dit : sa specification ne
  /// classe pas `email` parmi les champs obligatoires de l'objet `user` — un
  /// compte ouvert par telephone n'en porte pas. Un champ facultatif absent se
  /// lit donc comme une absence, jamais comme une erreur : refuser la session
  /// entiere priverait l'utilisateur de la synchronisation pour une etiquette
  /// manquante.
  final String? adresse;

  /// La marge appliquee avant l'expiration reelle.
  ///
  /// Un jeton qui expire dans deux secondes est deja expire pour une requete
  /// qui met une seconde a partir : le renouveler au dernier moment revient a
  /// essuyer un refus pour rien.
  static const Duration marge = Duration(seconds: 60);

  /// Vrai si [jetonAcces] ne doit plus etre presente au serveur.
  ///
  /// Une expiration **inconnue** (zero) ne declenche aucun renouvellement.
  /// Renouveler a chaque appel sans savoir pourquoi serait un remede pire que
  /// le mal : le serveur sait refuser un jeton perime, et c'est ce refus-la qui
  /// fait foi. Le cas ne devrait pas se produire — le serveur declare
  /// `expires_at` — mais un modele qui devine est un modele qui ment.
  bool estExpireeA(int maintenant) {
    if (expireLe == 0) return false;
    return maintenant + marge.inMilliseconds >= expireLe;
  }

  /// La forme rangee dans le trousseau.
  ///
  /// Une seule valeur, ecrite en une fois. Un enregistrement en plusieurs
  /// morceaux pourrait laisser une session a moitie ecrite — et une session a
  /// moitie ecrite ne se distingue pas d'une session valide tant qu'on n'a pas
  /// essaye de s'en servir.
  Map<String, Object?> versJson() => {
    'acces': jetonAcces,
    'rafraichissement': jetonRafraichissement,
    'expire_le': expireLe,
    'utilisateur': utilisateur,
    'adresse': adresse,
  };

  /// Relit une session rangee, ou rend `null` si la forme ne s'y prete pas.
  ///
  /// **Ne leve jamais.** Ce qui est range dans un trousseau peut avoir ete
  /// ecrit par une version precedente, ou avoir ete tronque : une session
  /// illisible doit se lire comme « pas de session » — donc « se reconnecter »
  /// — plutot que faire tomber l'application au demarrage. C'est le seul
  /// endroit du projet ou une donnee corrompue est une raison de continuer.
  ///
  /// Les quatre champs **exiges** refusent la session ; l'adresse, facultative,
  /// degrade en absence. Deux traitements pour deux natures de champ : une
  /// adresse d'un type inattendu ne doit pas emporter une session par ailleurs
  /// intacte.
  static Session? depuisJson(Object? json) {
    if (json is! Map) return null;

    final acces = json['acces'];
    final rafraichissement = json['rafraichissement'];
    final expireLe = json['expire_le'];
    final utilisateur = json['utilisateur'];
    final adresseBrute = json['adresse'];

    if (acces is! String || acces.isEmpty) return null;
    if (rafraichissement is! String || rafraichissement.isEmpty) return null;
    if (expireLe is! int) return null;
    if (utilisateur is! String || utilisateur.isEmpty) return null;

    return Session(
      jetonAcces: acces,
      jetonRafraichissement: rafraichissement,
      expireLe: expireLe,
      utilisateur: utilisateur,
      adresse: adresseBrute is String ? adresseBrute : null,
    );
  }
}
