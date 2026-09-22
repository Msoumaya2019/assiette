/// Le transport reel, vers Supabase.
///
/// Ou se situe cette couche
/// ------------------------
/// `ServiceSynchronisation` ne connait qu'un contrat de trois methodes —
/// `heureServeur`, `lire`, `ecrire`. Il ne sait pas qu'il y a un serveur, une
/// base ou un reseau. Ce fichier est **une** implementation de ce contrat, la
/// vraie ; les tests de convergence en utilisent une autre, en memoire.
///
/// Ce fichier est donc le seul endroit qui connait a la fois les noms du
/// serveur et ceux du local, et c'est la que les trois familles de conversion
/// sont appliquees : les dates, les booleens et le JSON. Voir
/// `data/distant/correspondance_distant.dart`, qui les **nomme** sans les
/// convertir, et les trois modules qui les convertissent.
///
/// Pourquoi `package:http` et pas le client Supabase
/// -------------------------------------------------
/// Le client officiel apporte une session, un stockage local et un
/// rafraichissement de jeton — trois choses dont l'application a besoin, mais
/// qui n'appartiennent pas au transport. Le transport, lui, a besoin de trois
/// requetes HTTP. Ajouter une dependance pour cela aurait rendu l'epreuve plus
/// difficile : avec `package:http`, le client est injectable, et toute la
/// mecanique ci-dessous s'eprouve contre un faux, sans serveur ni reseau.
///
/// Ce que le serveur impose, et qui n'est pas negociable
/// ----------------------------------------------------
///   - **PostgREST tronque une lecture a mille lignes**, sans le dire. Une
///     lecture qui ne decoupe pas perdrait en silence tout ce qui suit la
///     millieme, et la synchronisation croirait ces lignes absentes du serveur ;
///   - **`meal_items.meal_id` designe l'`uuid` que le serveur genere lui-meme**,
///     et non le `client_id` de l'appareil. Ecrire un repas et ses aliments
///     demande donc deux passages : ecrire le repas, **relire son `uuid`**,
///     puis rattacher les aliments ;
///   - **RLS filtre par `auth.uid()`** : chaque ligne ecrite doit porter son
///     `user_id`, sinon la politique la refuse.
///
/// Ce que ce transport ne fait pas
/// -------------------------------
/// Il ne **decide** rien. Il ne redate rien, il ne choisit pas quelle version
/// garder, il ne compose pas de plan : tout cela appartient au service et a la
/// regle d'arbitrage, qui sont eprouves sans lui. Ici, on transporte ce qu'on
/// nous donne.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/failures.dart';
import '../data/distant/correspondance_distant.dart';
import '../data/distant/dates_distantes.dart';
import '../data/distant/json_distants.dart';
import '../data/local/synchronisation_locale.dart';
import '../models/synchronisation.dart';
import 'synchronisation_service.dart';

/// Le plafond qu'une lecture atteint sans le dire, cote PostgREST.
const int plafondPostgrest = 1000;

/// Le nombre de lignes par requete d'ecriture.
///
/// Un lot trop gros se heurte a la taille maximale d'un corps de requete, et
/// l'erreur ne dit pas laquelle des lignes est en cause. Deux cents lignes
/// restent bien en dessous des limites ordinaires.
const int lignesParLot = 200;

/// Le nombre de pages au-dela duquel une lecture s'arrete.
///
/// Sans cette borne, une table qui rendrait toujours une page pleine ferait
/// tourner la boucle indefiniment. Deux cents pages valent deux cent mille
/// lignes : au-dela, ce n'est plus une synchronisation, c'est une erreur de
/// conception, et elle doit se voir.
const int pagesMax = 200;

/// Le transport qui parle a un projet Supabase.
class TransportSupabase implements TransportSynchronisation {
  TransportSupabase({
    required String url,
    required this.clePublique,
    required this.utilisateur,
    required this.jeton,
    http.Client? client,
    this.lignesParPage = plafondPostgrest,
    this.delai = const Duration(seconds: 30),
  }) : _base = url.replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client(),
       _clientFourni = client != null;

  /// L'adresse du projet, sans barre oblique finale.
  final String _base;

  /// La cle publique du projet. Publique par conception : la protection repose
  /// sur les politiques RLS, pas sur le secret de cette cle.
  final String clePublique;

  /// L'identifiant du compte connecte. Chaque ligne ecrite le porte, parce que
  /// les politiques RLS l'exigent.
  final String utilisateur;

  /// Le jeton de session. C'est lui qui dit au serveur **qui** parle.
  final String jeton;

  /// La taille d'une page de lecture. Injectable pour eprouver le decoupage
  /// sans fabriquer mille lignes.
  final int lignesParPage;

  final Duration delai;
  final http.Client _client;
  final bool _clientFourni;

  /// Ferme le client, s'il appartient a ce transport.
  ///
  /// Un client injecte appartient a l'appelant : le fermer ici rendrait
  /// inutilisable un client qu'un autre usage partage.
  void fermer() {
    if (!_clientFourni) _client.close();
  }

  // --- ce que le contrat demande ----------------------------------------

  @override
  Future<int> heureServeur() async {
    // PostgREST ne rend pas l'heure du serveur : il n'y a pas de colonne
    // « maintenant » a lire. L'en-tete `Date` de la reponse HTTP, lui, est pose
    // par la passerelle — et il est present meme sur une reponse d'erreur, ce
    // qui evite qu'un projet mal configure empeche toute synchronisation.
    //
    // Sa resolution est la **seconde**. L'ecart mesure n'est donc fiable qu'a la
    // seconde : cela suffit, la tolerance qui decide si l'horloge est suspecte
    // est de deux minutes, et l'ecart est mesure au milieu de l'aller-retour.
    final reponse = await _envoyer(
      () => _client.head(Uri.parse('$_base/rest/v1/')),
    );
    final date = _entete(reponse, 'date');
    if (date == null) {
      throw const InvalidResponseFailure();
    }
    try {
      return HttpDate.parse(date).millisecondsSinceEpoch;
    } on HttpException {
      throw const InvalidResponseFailure();
    } on FormatException {
      throw const InvalidResponseFailure();
    }
  }

  @override
  Future<List<LigneSynchronisable>> lire(TableSynchronisable table) async {
    final serveur = tablesDistantes[table.nom];
    if (serveur == null) return const [];

    final lignes = await _lireToutes(serveur);
    final enfant = table.enfant;
    if (enfant == null) {
      return [for (final ligne in lignes) _versLigne(table, ligne)];
    }

    // L'agregat. Les aliments se rattachent par l'`uuid` que le serveur genere,
    // et que la ligne du repas porte : il faut donc lire les repas **d'abord**,
    // pour traduire `meal_id` en cle d'appareil. C'est le deuxieme passage de
    // l'ecriture, dans l'autre sens.
    final cleParUuid = <String, String>{};
    for (final ligne in lignes) {
      final uuid = ligne['id'];
      final cle = _cleDe(table, ligne);
      if (uuid is String && cle != null) cleParUuid[uuid] = cle;
    }

    final parParent = <String, List<Map<String, Object?>>>{};
    final nomEnfant = tablesDistantes[enfant.nom];
    if (nomEnfant != null) {
      final lien = colonneDistante(enfant.nom, enfant.colonneLien);
      for (final ligne in await _lireToutes(nomEnfant)) {
        final parent = cleParUuid[ligne[lien]];
        if (parent == null) continue;
        (parParent[parent] ??= []).add(_contenuDEnfant(enfant, ligne));
      }
    }

    return [
      for (final ligne in lignes)
        _versLigne(
          table,
          ligne,
          // Une liste vide, jamais une absence : un repas sans aliment doit se
          // lire des deux cotes de la meme facon, sinon les empreintes
          // differeraient pour toujours.
          enfants: parParent[_cleDe(table, ligne)] ?? const [],
        ),
    ];
  }

  @override
  Future<void> ecrire(
    TableSynchronisable table,
    List<LigneSynchronisable> lignes,
  ) async {
    if (lignes.isEmpty) return;
    final serveur = tablesDistantes[table.nom];
    if (serveur == null) return;

    for (final lot in _lots(lignes, lignesParLot)) {
      await _ecrireLot(serveur, table, lot);
    }
  }

  // --- lecture -----------------------------------------------------------

  /// Toutes les lignes d'une table, plafond de PostgREST compris.
  ///
  /// Le decoupage se fait par l'en-tete `Range`, et non par `limit`/`offset` :
  /// `offset` oblige le serveur a compter les lignes sautees a chaque page,
  /// pour un resultat identique. La boucle s'arrete sur une page **incomplete**,
  /// ce qui ne depend d'aucun en-tete et ne peut pas mentir.
  Future<List<Map<String, Object?>>> _lireToutes(String table) async {
    final lignes = <Map<String, Object?>>[];
    for (var page = 0; page < pagesMax; page++) {
      final debut = page * lignesParPage;
      final reponse = await _envoyer(
        () => _client.get(
          _uri(table, {'select': '*'}),
          headers: {
            ..._entetes(),
            'Range-Unit': 'items',
            'Range': '$debut-${debut + lignesParPage - 1}',
          },
        ),
      );
      // `206` est la reponse normale d'une lecture bornee par `Range`. Ne
      // l'accepter pas ferait echouer toute lecture des qu'une page est
      // demandee, c'est-a-dire toujours.
      _verifier(reponse, acceptes: const {200, 206});

      final pageLue = _lignesDe(reponse);
      lignes.addAll(pageLue);
      if (pageLue.length < lignesParPage) return lignes;
    }

    throw ProviderFailure(
      'Lecture interrompue : plus de $pagesMax pages dans `$table`',
      hint: 'La table est plus grosse que prevu. Signalez-le depuis Reglages.',
    );
  }

  /// La cle d'appareil d'une ligne distante.
  String? _cleDe(TableSynchronisable table, Map<String, Object?> ligne) {
    final valeur = ligne[colonneCleDistante(table.nom, table.colonneCle)];
    return valeur?.toString();
  }

  /// Les colonnes distantes qui n'entrent pas dans le contenu local.
  ///
  /// Deux familles, et la seconde est celle qui se voit mal.
  ///
  ///   - les colonnes **serveur seules** : `id`, `user_id`, les `total_*`. Le
  ///     local ne les porte pas, et les lui donner ferait entrer dans le contenu
  ///     une valeur que `lireLignes` n'y mettrait jamais ;
  ///   - les colonnes **locales seules** ([colonnesLocalesSeules]) : elles ont
  ///     bien une colonne serveur, mais leur valeur n'est pas transportable.
  ///     `meals.photo_path` en est une.
  ///
  /// La seconde famille est le vrai sujet de cette fonction, et elle se paie
  /// cher quand on l'oublie : `select=*` rend `photo_path` — `null` aujourd'hui,
  /// le chemin d'un objet distant demain. Ce `null` entrerait dans le contenu
  /// sous forme de **cle presente**, alors que le contenu local, lui, n'a pas
  /// cette cle du tout. Les deux empreintes différeraient donc a jamais, pour
  /// une colonne dont la valeur n'a jamais eu a circuler : l'arbitrage
  /// designerait un gagnant a chaque passage, et chaque passage reecrirait la
  /// meme ligne. Une boucle sans erreur, sans trace, et sans fin.
  ///
  /// Les deux familles sont nommees en vocabulaire **local** dans la
  /// declaration ; la traduction est faite ici, une fois, pour que les deux sens
  /// du transport s'accordent meme si une colonne locale-seule venait a etre
  /// renommee cote serveur.
  Set<String> _colonnesHorsContenu(String tableLocale, String tableDistante) =>
      {
        ...?colonnesServeurSeules[tableDistante],
        for (final locale in colonnesLocalesSeulesDe(tableLocale))
          colonneDistante(tableLocale, locale),
      };

  /// Une ligne distante, ramenee en vocabulaire local.
  LigneSynchronisable _versLigne(
    TableSynchronisable table,
    Map<String, Object?> ligne, {
    List<Map<String, Object?>>? enfants,
  }) {
    final serveur = tablesDistantes[table.nom]!;
    final horsContenu = _colonnesHorsContenu(table.nom, serveur);
    final colonneCle = colonneCleDistante(table.nom, table.colonneCle);

    final contenu = <String, Object?>{};
    for (final entree in ligne.entries) {
      final colonne = entree.key;
      if (colonnesDeService.contains(colonne)) continue;
      if (horsContenu.contains(colonne)) continue;
      if (colonne == colonneCle) continue;
      contenu[colonneLocale(table.nom, colonne)] = _versValeurLocale(
        table.nom,
        colonne,
        entree.value,
      );
    }
    if (enfants != null) contenu[cleDesEnfants] = enfants;

    return LigneSynchronisable(
      cle: ligne[colonneCle].toString(),
      // Une date absente vaut zero, jamais 1970 : c'est la convention de
      // `VersionArbitrable`, et `millisecondesDepuisIso` la respecte deja pour
      // une chaine vide comme pour un nul.
      updatedAt: millisecondesDepuisIso(ligne['updated_at']) ?? 0,
      deletedAt: millisecondesDepuisIso(ligne['deleted_at']),
      contenu: contenu,
    );
  }

  /// Le contenu d'un aliment, en vocabulaire local.
  ///
  /// La colonne de lien est exclue, comme `contenuDe` l'exclut : elle est
  /// derivee du parent, et la garder ferait dependre l'empreinte d'une valeur
  /// qui n'appartient pas a la ligne.
  Map<String, Object?> _contenuDEnfant(
    EnfantSynchronisable enfant,
    Map<String, Object?> ligne,
  ) {
    final lien = colonneDistante(enfant.nom, enfant.colonneLien);
    final serveur = tablesDistantes[enfant.nom]!;
    final horsContenu = _colonnesHorsContenu(enfant.nom, serveur);

    final contenu = <String, Object?>{};
    for (final entree in ligne.entries) {
      final colonne = entree.key;
      if (colonne == lien) continue;
      if (colonnesDeService.contains(colonne)) continue;
      if (horsContenu.contains(colonne)) continue;
      contenu[colonneLocale(enfant.nom, colonne)] = _versValeurLocale(
        enfant.nom,
        colonne,
        entree.value,
      );
    }
    return contenu;
  }

  /// La valeur distante, ramenee au type local.
  ///
  /// Les trois familles, dans l'ordre ou elles sont declarees. Une colonne qui
  /// n'appartient a aucune passe telle quelle : c'est le cas des textes et des
  /// nombres, et `empreinte.dart` normalise deja les entiers et les flottants.
  Object? _versValeurLocale(
    String table,
    String colonneDistante,
    Object? valeur,
  ) {
    if (valeur == null) return null;
    final locale = colonneLocale(table, colonneDistante);
    if ((colonnesDatesDistantes[table] ?? const <String>{}).contains(locale)) {
      return millisecondesDepuisIso(valeur);
    }
    if ((colonnesBooleennesDistantes[table] ?? const <String>{}).contains(
      locale,
    )) {
      return valeur == true ? 1 : 0;
    }
    if ((colonnesJsonDistantes[table] ?? const <String>{}).contains(locale)) {
      return texteDepuisJson(valeur);
    }
    return valeur;
  }

  // --- ecriture ----------------------------------------------------------

  Future<void> _ecrireLot(
    String serveur,
    TableSynchronisable table,
    List<LigneSynchronisable> lot,
  ) async {
    final corps = [for (final ligne in lot) _versLigneDistante(table, ligne)];

    final reponse = await _envoyer(
      () => _client.post(
        _uri(serveur, {'on_conflict': _colonnesDeConflit(table)}),
        headers: _entetes(ecriture: true, resolution: true),
        body: jsonEncode(corps),
      ),
    );
    _verifier(reponse, acceptes: const {200, 201, 204});

    final enfant = table.enfant;
    if (enfant == null) return;
    await _ecrireEnfants(enfant, lot);
  }

  /// Ecrit les aliments d'un lot de repas, en deux passages.
  ///
  /// `meal_items.meal_id` designe l'`uuid` que le serveur genere lui-meme :
  /// l'appareil ne peut donc pas le connaitre avant d'avoir ecrit le repas. Il
  /// faut ecrire le repas, **relire son `uuid`**, puis rattacher les aliments.
  ///
  /// Les aliments sont ensuite reecrits **en bloc**, comme `ecrireLigne` le fait
  /// en local : un aliment retire du repas disparaitrait sinon du serveur, et
  /// l'agregat relu des deux cotes ne serait plus le meme.
  ///
  /// Une coupure entre la suppression et l'insertion laisse un repas sans
  /// aliments. Les deux cotes ne sont alors plus d'accord, et le passage suivant
  /// le repare : l'agregat local, lui, n'a pas ete touche. Rien n'est perdu.
  Future<void> _ecrireEnfants(
    EnfantSynchronisable enfant,
    List<LigneSynchronisable> repas,
  ) async {
    final serveurEnfant = tablesDistantes[enfant.nom];
    if (serveurEnfant == null) return;

    final cles = [for (final ligne in repas) ligne.cle];
    final uuidParCle = await _uuidDesRepas(cles);
    final lien = colonneDistante(enfant.nom, enfant.colonneLien);
    final uuids = [
      for (final cle in cles)
        if (uuidParCle[cle] != null) uuidParCle[cle]!,
    ];

    if (uuids.isNotEmpty) {
      final reponse = await _envoyer(
        () => _client.delete(
          _uri(serveurEnfant, {
            lien: 'in.(${uuids.map(_identifiant).join(',')})',
          }),
          headers: _entetes(),
        ),
      );
      _verifier(reponse, acceptes: const {200, 204});
    }

    final rattaches = <Map<String, Object?>>[];
    for (final repasEcrit in repas) {
      final uuid = uuidParCle[repasEcrit.cle];
      if (uuid == null) continue;
      final aliments = repasEcrit.contenu[cleDesEnfants];
      if (aliments is! List) continue;
      for (final aliment in aliments) {
        if (aliment is! Map) continue;
        rattaches.add({
          ..._versEnfantDistant(enfant, aliment.cast<String, Object?>()),
          lien: uuid,
        });
      }
    }
    if (rattaches.isEmpty) return;

    for (final lot in _lots(rattaches, lignesParLot)) {
      final reponse = await _envoyer(
        () => _client.post(
          _uri(serveurEnfant, {
            'on_conflict':
                'user_id,${colonneCleDistante(enfant.nom, enfant.colonneCle)}',
          }),
          headers: _entetes(ecriture: true, resolution: true),
          body: jsonEncode(lot),
        ),
      );
      _verifier(reponse, acceptes: const {200, 201, 204});
    }
  }

  /// L'`uuid` que le serveur a donne a chaque repas, par cle d'appareil.
  ///
  /// Le deuxieme passage. La reponse est demandee en `select=id,client_id` :
  /// c'est le seul endroit ou l'appareil apprend l'`uuid` du serveur, et il ne
  /// peut pas le deviner — c'est le serveur qui le genere.
  Future<Map<String, String>> _uuidDesRepas(List<String> cles) async {
    final resultat = <String, String>{};
    for (final lot in _lots(cles, lignesParLot)) {
      final reponse = await _envoyer(
        () => _client.get(
          _uri('meals', {
            'select': 'id,client_id',
            'client_id': 'in.(${lot.map(_identifiant).join(',')})',
          }),
          headers: _entetes(),
        ),
      );
      _verifier(reponse);
      for (final ligne in _lignesDe(reponse)) {
        final uuid = ligne['id'];
        final cle = ligne['client_id'];
        if (uuid is String && cle is String) resultat[cle] = uuid;
      }
    }
    return resultat;
  }

  /// Une ligne locale, ecrite en vocabulaire serveur.
  Map<String, Object?> _versLigneDistante(
    TableSynchronisable table,
    LigneSynchronisable ligne,
  ) {
    final corps = <String, Object?>{
      colonneCleDistante(table.nom, table.colonneCle): ligne.cle,
      'user_id': utilisateur,
      'updated_at': isoDepuisMillisecondes(ligne.updatedAt),
      'deleted_at': isoDepuisMillisecondes(ligne.deletedAt),
    };
    final localesSeules = colonnesLocalesSeulesDe(table.nom);
    for (final entree in ligne.contenu.entries) {
      // Les aliments ne sont pas une colonne : ils partent par le deuxieme
      // passage.
      if (entree.key == cleDesEnfants) continue;
      // Une colonne locale-seule ne franchit pas la frontiere. `contenuDe` la
      // retire deja de ce qu'il rend ; la retirer **ici aussi** fait de la regle
      // une propriete du transport, et non une propriete de son appelant — une
      // garantie qui dependrait d'un appelant bien eleve finirait par tomber le
      // jour ou un second appelant apparait.
      if (localesSeules.contains(entree.key)) continue;
      corps[colonneDistante(table.nom, entree.key)] = _versValeurDistante(
        table.nom,
        entree.key,
        entree.value,
      );
    }
    return corps;
  }

  /// Le contenu d'un aliment, ecrit en vocabulaire serveur.
  ///
  /// Il ne porte **pas** son `updated_at` : le serveur en pose un a l'insertion,
  /// et le cycle de vie d'un aliment est celui de son repas — c'est ce que dit
  /// `synchronisation_locale.dart`. Lui en donner un ferait apparaitre une date
  /// que rien ne compare.
  Map<String, Object?> _versEnfantDistant(
    EnfantSynchronisable enfant,
    Map<String, Object?> contenu,
  ) {
    final corps = <String, Object?>{'user_id': utilisateur};
    for (final entree in contenu.entries) {
      corps[colonneDistante(enfant.nom, entree.key)] = _versValeurDistante(
        enfant.nom,
        entree.key,
        entree.value,
      );
    }
    return corps;
  }

  /// La valeur locale, ecrite au type du serveur.
  Object? _versValeurDistante(
    String table,
    String colonneLocale,
    Object? valeur,
  ) {
    if (valeur == null) return null;
    if ((colonnesDatesDistantes[table] ?? const <String>{}).contains(
      colonneLocale,
    )) {
      return isoDepuisMillisecondes(valeur is int ? valeur : null);
    }
    if ((colonnesBooleennesDistantes[table] ?? const <String>{}).contains(
      colonneLocale,
    )) {
      // Le local porte un entier, le serveur un booleen. `0` et `false` sont la
      // meme chose ; tout le reste est vrai.
      return valeur != 0;
    }
    if ((colonnesJsonDistantes[table] ?? const <String>{}).contains(
      colonneLocale,
    )) {
      return jsonDepuisTexte(valeur);
    }
    return valeur;
  }

  /// Les colonnes de la contrainte d'unicite du serveur, pour l'`upsert`.
  ///
  /// Elles sont **le** point d'accord entre les deux cotes : sans elles,
  /// PostgREST refuserait la requete au lieu de remplacer la ligne, et la
  /// synchronisation echouerait a chaque passage sans rien perdre — donc sans
  /// que rien ne le signale vraiment.
  String _colonnesDeConflit(TableSynchronisable table) =>
      'user_id,${colonneCleDistante(table.nom, table.colonneCle)}';

  /// Un identifiant, tel que PostgREST l'accepte dans `in.(…)`.
  ///
  /// Les valeurs sont mises entre guillemets : la grammaire de `in` separe par
  /// des virgules, et un identifiant qui en contiendrait une serait coupe en
  /// deux — la requete ne trouverait alors rien, ou trouverait autre chose, et
  /// le deuxieme passage rattacherait des aliments au mauvais repas.
  String _identifiant(String valeur) =>
      '"${valeur.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  // --- plomberie ---------------------------------------------------------

  Map<String, String> _entetes({
    bool ecriture = false,
    bool resolution = false,
  }) {
    return {
      'apikey': clePublique,
      'Authorization': 'Bearer $jeton',
      'Accept': 'application/json',
      if (ecriture) 'Content-Type': 'application/json',
      if (resolution) 'Prefer': 'resolution=merge-duplicates,return=minimal',
    };
  }

  /// Un en-tete de reponse, sans dependre de la casse de son nom.
  ///
  /// `http.Response.headers` est une table **sensible a la casse**, et le client
  /// y recopie le nom tel que le serveur l'a envoye : `Date`, avec sa majuscule,
  /// comme l'envoient les passerelles HTTP. Mesure faite dans le paquet installe
  /// — `http-1.6.0/lib/src/io_client.dart:204` recopie `key` sans le normaliser,
  /// et `dart-sdk/lib/_http/http_headers.dart:120` rend a `forEach` le nom
  /// **d'origine**, pas celui, minuscule, sous lequel il est range.
  ///
  /// Chercher `'date'` en dur rendrait donc `null` contre un vrai serveur. Et la
  /// consequence serait **silencieuse** : `ServiceSynchronisation._decalage`
  /// avale l'echec et rend `null`, donc l'ecart d'horloge disparaitrait sans que
  /// rien ne signale que le diagnostic avait cesse de fonctionner. Un test qui
  /// ecrit ses en-tetes en minuscules ne le verrait jamais — d'ou celui qui les
  /// ecrit avec leur casse reelle.
  String? _entete(http.Response reponse, String nom) {
    for (final entree in reponse.headers.entries) {
      if (entree.key.toLowerCase() == nom) return entree.value;
    }
    return null;
  }

  Uri _uri(String chemin, [Map<String, String>? requete]) {
    final uri = Uri.parse('$_base/rest/v1/$chemin');
    return requete == null ? uri : uri.replace(queryParameters: requete);
  }

  /// Envoie la requete, et traduit les pannes de reseau.
  Future<http.Response> _envoyer(
    Future<http.Response> Function() requete,
  ) async {
    try {
      return await requete().timeout(delai);
    } on SocketException {
      throw const NetworkFailure();
    } on http.ClientException {
      throw const NetworkFailure();
    } on TimeoutException {
      throw const TimeoutFailure();
    }
  }

  /// Verifie le code, et leve la panne correspondante sinon.
  ///
  /// Un `401` ou un `403` n'est pas une panne de reseau : c'est une session
  /// refusee, et l'interface doit le dire autrement — sans quoi l'utilisateur
  /// chercherait un probleme de connexion la ou il faut se reconnecter.
  void _verifier(http.Response reponse, {Set<int> acceptes = const {200}}) {
    if (acceptes.contains(reponse.statusCode)) return;
    switch (reponse.statusCode) {
      case 401:
      case 403:
        throw const SessionRefuseeFailure();
      case 429:
        throw const RateLimitFailure();
      default:
        throw ProviderFailure(
          'La synchronisation a echoue',
          hint: 'Reessayez dans un instant.',
          isRetryable: reponse.statusCode >= 500,
          statusCode: reponse.statusCode,
        );
    }
  }

  List<Map<String, Object?>> _lignesDe(http.Response reponse) {
    if (reponse.bodyBytes.isEmpty) return const [];
    final decode = jsonDecode(utf8.decode(reponse.bodyBytes));
    if (decode is! List) throw const InvalidResponseFailure();
    return [
      for (final element in decode)
        if (element is Map) element.cast<String, Object?>(),
    ];
  }

  /// Decoupe une liste en lots d'au plus [taille] elements.
  Iterable<List<T>> _lots<T>(List<T> elements, int taille) sync* {
    for (var debut = 0; debut < elements.length; debut += taille) {
      final fin = (debut + taille).clamp(0, elements.length);
      yield elements.sublist(debut, fin);
    }
  }
}
