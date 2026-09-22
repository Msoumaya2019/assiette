/// Une session de compte, telle que le serveur d'authentification la rend.
///
/// Ce que ce modele ne porte pas, et pourquoi
/// ------------------------------------------
/// Ni l'adresse electronique, ni le mot de passe. La premiere n'est pas
/// necessaire a la synchronisation, et le second n'a aucune raison de survivre a
/// la requete qui l'a transporte : le garder en memoire, c'est le garder
/// jusqu'au prochain vidage, et le rendre disponible a tout ce qui sait lire un
/// objet en memoire.
library;

class Session {
  const Session({
    required this.jetonAcces,
    required this.jetonRafraichissement,
    required this.expireLe,
    required this.utilisateur,
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
  };

  /// Relit une session rangee, ou rend `null` si la forme ne s'y prete pas.
  ///
  /// **Ne leve jamais.** Ce qui est range dans un trousseau peut avoir ete
  /// ecrit par une version precedente, ou avoir ete tronque : une session
  /// illisible doit se lire comme « pas de session » — donc « se reconnecter »
  /// — plutot que faire tomber l'application au demarrage. C'est le seul
  /// endroit du projet ou une donnee corrompue est une raison de continuer.
  static Session? depuisJson(Object? json) {
    if (json is! Map) return null;

    final acces = json['acces'];
    final rafraichissement = json['rafraichissement'];
    final expireLe = json['expire_le'];
    final utilisateur = json['utilisateur'];

    if (acces is! String || acces.isEmpty) return null;
    if (rafraichissement is! String || rafraichissement.isEmpty) return null;
    if (expireLe is! int) return null;
    if (utilisateur is! String || utilisateur.isEmpty) return null;

    return Session(
      jetonAcces: acces,
      jetonRafraichissement: rafraichissement,
      expireLe: expireLe,
      utilisateur: utilisateur,
    );
  }
}
