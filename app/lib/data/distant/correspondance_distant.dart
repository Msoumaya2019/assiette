/// La correspondance entre le schema local et le schema serveur.
///
/// Une seule source
/// ----------------
/// Cette declaration est **la** source. `tools/check_migration_serveur.py` la
/// lit et confronte les deux schemas dans les deux sens : chaque colonne locale
/// doit avoir une destination serveur, et chaque colonne serveur doit etre soit
/// alimentee par le local, soit declaree ici comme volontairement sans
/// equivalent. Recopier ces tables dans le controle creerait deux verites que
/// rien ne relierait — exactement le defaut que ce controle existe pour fermer.
///
/// Les deux schemas ne se ressemblent pas
/// --------------------------------------
/// Trois differences, toutes volontaires :
///
///   - **les noms de tables** : `templates` s'appelle `meal_templates` cote
///     serveur, `pesees` s'appelle `weight_entries`, `mesures` s'appelle
///     `body_measurements` ;
///   - **les noms de colonnes** : `poids_kg` devient `weight_kg`, `payload_json`
///     devient `payload`, `mesure_le` devient `measured_at` ;
///   - **l'identifiant** : le serveur genere son propre `uuid` et range celui du
///     telephone dans `client_id`. C'est ce dernier qui sert a reconnaitre une
///     ligne d'un appareil a l'autre — un `uuid` genere par le serveur ne
///     pourrait pas etre connu de l'appareil qui a cree la ligne hors ligne.
///
/// Le serveur ajoute aussi des colonnes que le local n'alimente pas : son
/// `id`, le `user_id` qui porte la propriete, et les `total_*` de `meals`, qui
/// denormalisent le calcul pour accelerer le tableau de bord.
///
/// Et une colonne va dans l'autre sens
/// -----------------------------------
/// `meals.photo_path` existe des deux cotes, mais sa valeur n'est pas
/// transportable : c'est un chemin **propre a l'appareil**. Elle est donc
/// declaree dans [colonnesLocalesSeules] — la troisieme famille, apres les
/// colonnes renommees et les colonnes serveur seules. Sans cette declaration,
/// le transport ecraserait la photo locale d'un autre appareil sans la moindre
/// erreur.
///
/// Ce que ce fichier n'est pas
/// ---------------------------
/// Il ne **convertit** rien : les dates locales sont des entiers en
/// millisecondes, le serveur les porte en `timestamptz`. Cette conversion est
/// le travail du transport, pas de la declaration.
library;

/// Table locale -> table serveur.
///
/// `settings` n'y figure pas : ses cles se repartissent entre le profil serveur
/// et les preferences de cet appareil-ci. Voir `SETTINGS_DECOMPOSE` dans
/// `tools/check_migration_serveur.py`, qui tient cette repartition.
const Map<String, String> tablesDistantes = {
  'meals': 'meals',
  'meal_items': 'meal_items',
  'templates': 'meal_templates',
  'favorites': 'favorites',
  'portions': 'portions',
  'pesees': 'weight_entries',
  'mesures': 'body_measurements',
};

/// `table.colonne` locale -> colonne serveur.
const Map<String, String> renommagesDistants = {
  // L'identifiant du telephone. Le serveur a le sien, qu'il genere.
  'meals.id': 'client_id',
  'meal_items.id': 'client_id',
  'templates.id': 'client_id',
  'favorites.id': 'client_id',
  'pesees.id': 'client_id',
  'mesures.id': 'client_id',
  // `portion` porte l'identifiant de la taille (« small », « medium »). Il est
  // renomme parce que, voisin de `portion_label` et `portion_grams`, il se
  // lirait comme l'objet portion entiere.
  'meal_items.portion': 'portion_size',
  // Les listes et charges utiles locales sont du JSON texte ; le serveur a une
  // colonne `jsonb` du meme contenu.
  'templates.items_json': 'items',
  'favorites.payload_json': 'payload',
  // Suivi du poids : noms anglais cote serveur, comme le reste de `0001`.
  'pesees.mesure_le': 'measured_at',
  'pesees.poids_kg': 'weight_kg',
  'mesures.mesure_le': 'measured_at',
  'mesures.type': 'kind',
  'mesures.valeur_cm': 'value_cm',
};

/// Colonnes serveur sans equivalent local, declarees **une a une**.
///
/// Les nommer evite qu'une nouvelle sorte s'installe sans qu'on la voie : le
/// controle refuse une colonne serveur qui n'est ni alimentee par le local, ni
/// declaree ici.
const Map<String, Set<String>> colonnesServeurSeules = {
  'meals': {
    'id',
    'user_id',
    'total_kcal',
    'total_carbs_g',
    'total_sugars_g',
    'total_protein_g',
    'total_fat_g',
    'total_fiber_g',
    'total_salt_g',
  },
  // Le local n'horodate pas les lignes d'un repas : seul le repas l'est, et
  // `saveMeal` reecrit ses aliments en bloc.
  'meal_items': {'id', 'user_id', 'created_at', 'updated_at'},
  'meal_templates': {'id', 'user_id'},
  'favorites': {'id', 'user_id'},
  'portions': {'user_id'},
  'weight_entries': {'id', 'user_id'},
  'body_measurements': {'id', 'user_id'},
};

/// Tables qui n'existent que cote serveur.
///
/// Le compte et le quota d'appels n'ont pas d'equivalent local : ils
/// n'appartiennent pas a un appareil.
const Set<String> tablesEntierementDistantes = {'profiles', 'api_usage'};

/// Colonnes que le serveur porte en `timestamptz` et le local en entier.
///
/// Nommees **en vocabulaire local** : le transport parcourt le contenu dans cet
/// vocabulaire, et renomme apres conversion.
///
/// Ce n'est pas une commodite, c'est ce qui evite une boucle silencieuse. Sans
/// conversion, la meme date serait `1700000000000` d'un cote et
/// `« 2023-11-14T22:13:20.000Z »` de l'autre : les empreintes differeraient
/// toujours, l'arbitrage trancherait toujours dans le meme sens, et chaque
/// passage reecrirait la meme ligne sans jamais converger.
const Map<String, Set<String>> colonnesDatesDistantes = {
  'meals': {'eaten_at', 'created_at'},
  'templates': {'created_at'},
  'favorites': {'created_at'},
  'pesees': {'mesure_le', 'created_at'},
  'mesures': {'mesure_le', 'created_at'},
};

/// Colonnes que le serveur porte en `boolean` et le local en entier.
///
/// Meme piege, meme consequence : `true` et `1` ne font pas la meme empreinte.
const Map<String, Set<String>> colonnesBooleennesDistantes = {
  'meals': {'is_estimate'},
  'meal_items': {'is_estimate'},
};

/// Colonnes dont la **valeur** ne quitte pas cet appareil.
///
/// Nommees en vocabulaire **local**. Elles ont bien une colonne serveur — le
/// controle d'accord entre les deux schemas reste donc satisfait — mais leur
/// contenu n'est pas transportable.
///
/// Le cas qui a motive cette declaration : `meals.photo_path`. La valeur est un
/// **chemin absolu propre a l'appareil** — `<documents>/meal_photos/<id>.jpg`,
/// compose par `services/image_service.dart` a partir du dossier de documents
/// du telephone. Le transporter ecraserait la photo locale d'un autre appareil
/// **sans erreur** : le chemin arriverait, il serait valide, et l'image
/// manquerait. La photo serait perdue pour l'appareil qui l'avait prise.
///
/// Ce n'est pas la meme chose qu'une colonne oubliee. Une colonne oubliee est
/// un defaut ; celle-ci est une decision, et elle est nommee ici. C'est ce qui
/// autorise le contenu a etre **deliberement aveugle** a `photo_path` sans que
/// cette cecite se confonde avec un oubli — meme discipline que la liste close
/// des bancs.
///
/// La colonne serveur `meals.photo_path` garde un sens : le jour ou les photos
/// seront deposees sur un stockage distant, elle portera le chemin de l'objet
/// distant. Deux valeurs differentes sous un meme nom — c'est exactement
/// pourquoi ce n'est pas au transport de les confondre.
const Map<String, Set<String>> colonnesLocalesSeules = {
  'meals': {'photo_path'},
};

/// Les colonnes qui restent sur l'appareil, pour une table donnee.
///
/// Rend un ensemble vide plutot que `null` : l'appelant n'a pas a connaitre la
/// difference entre « aucune » et « pas declaree ».
Set<String> colonnesLocalesSeulesDe(String tableLocale) =>
    colonnesLocalesSeules[tableLocale] ?? const <String>{};

/// Le nom serveur d'une colonne locale.
///
/// Rend la colonne telle quelle quand elle n'est pas renommee — ce qui est le
/// cas le plus frequent.
String colonneDistante(String tableLocale, String colonneLocale) =>
    renommagesDistants['$tableLocale.$colonneLocale'] ?? colonneLocale;

/// La colonne serveur qui porte la cle d'une ligne locale.
///
/// C'est elle qui reconnait une ligne d'un appareil a l'autre : `client_id`
/// partout, sauf `portions`, dont la cle locale est deja le nom de l'aliment.
String colonneCleDistante(String tableLocale, String colonneCleLocale) =>
    colonneDistante(tableLocale, colonneCleLocale);

/// Le nom **local** d'une colonne serveur — l'inverse de [colonneDistante].
///
/// Sert au sens descendant : une ligne lue sur le serveur revient en
/// vocabulaire local, pour que le reste de l'application n'ait jamais a
/// connaitre les noms du serveur.
///
/// Le renommage est cherche **dans la table** : `measured_at` est le nom
/// serveur de `mesure_le` aussi bien dans `pesees` que dans `mesures`, et une
/// recherche qui ignorerait la table rendrait la colonne de l'une pour l'autre.
String colonneLocale(String tableLocale, String colonneDistante) {
  for (final entree in renommagesDistants.entries) {
    if (entree.value != colonneDistante) continue;
    final parties = entree.key.split('.');
    if (parties.length == 2 && parties.first == tableLocale) {
      return parties.last;
    }
  }
  return colonneDistante;
}
