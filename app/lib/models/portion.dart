import '../core/formatters.dart';

/// Une portion nommee : l'unite que l'utilisateur a reellement en tete.
///
/// « 1 gateau », « 2 parts », « 3 cuilleres ». L'application ne stocke jamais
/// un total par portion : elle stocke le poids d'**une** unite et la quantite
/// consommee en grammes. Le nombre d'unites est **deduit** de ces deux valeurs,
/// jamais saisi puis conserve a part — sinon deux verites coexisteraient, et
/// corriger le poids laisserait le nombre faux sans que rien ne le signale.
class Portion {
  const Portion({required this.label, required this.grams});

  /// Nom de l'unite, au singulier : « gateau », « part », « bol ».
  final String label;

  /// Poids d'une unite, en grammes. Toujours strictement positif.
  final double grams;

  bool get estValide => label.trim().isNotEmpty && grams > 0;

  /// Nom de l'unite au singulier, sans espaces parasites.
  String get nomSingulier => label.trim();

  /// Nom de l'unite au pluriel, pour les libelles d'interface.
  ///
  /// Passe par la meme regle que [libelle] : « Nombre de gateaux », mais
  /// « Nombre de jus » — un pluriel forme a la main donnerait « juss ».
  String get nomPluriel => _pluriel(label.trim());

  /// Nombre d'unites correspondant a un poids, ou `null` si la portion n'a
  /// aucun sens (poids d'unite nul ou negatif).
  double? unitesPour(double grammes) {
    if (grams <= 0) return null;
    return grammes / grams;
  }

  /// Poids correspondant a un nombre d'unites.
  double grammesPour(double unites) => unites * grams;

  /// « 1 gateau », « 2 gateaux », « 1,5 part ».
  ///
  /// Le pluriel suit la regle francaise : on reste au singulier en dessous de
  /// deux, donc « 1,5 part » et non « 1,5 parts ».
  String libelle(double unites) =>
      '${Format.number(unites)} ${_accorde(unites)}';

  /// « 1 gateau · 65 g », pour les endroits ou le poids doit rester visible.
  String libelleAvecPoids(double unites) =>
      '${libelle(unites)} · ${Format.grams(grammesPour(unites))}';

  /// « 1 gateau (65 g) », sans preposition : l'appelant compose sa phrase.
  ///
  /// Toujours au singulier : cette etiquette sert a annoncer **l'unite de
  /// reference** d'une fiche aliment (« pour 1 pot (125 g) »), pas une quantite
  /// consommee.
  String get etiquetteUnite => '${libelle(1)} (${Format.grams(grams)})';

  /// L'unite accordee en nombre : « gateau » ou « gateaux ».
  String _accorde(double unites) =>
      unites < 2 ? label.trim() : _pluriel(label.trim());

  /// Ajoute la marque du pluriel, sauf si le mot la porte deja.
  ///
  /// Trois regles seulement, mais ce sont les trois qui se voient :
  ///   - « gateau » -> « gateaux », « noyau » -> « noyaux » : la regle des mots
  ///     en -eau et -au, et la plus visible quand elle manque ;
  ///   - « jus », « riz », « mais » restent invariables ;
  ///   - tout le reste prend un « s ».
  ///
  /// Le francais a d'autres irregularites — « cheval » donne « chevaux » — mais
  /// elles ne concernent pas les unites qu'on trouve dans une assiette, et une
  /// table d'exceptions couterait plus qu'elle ne rapporte.
  static String _pluriel(String mot) {
    if (mot.isEmpty) return mot;
    final bas = mot.toLowerCase();
    final dernier = bas[bas.length - 1];
    if (dernier == 's' || dernier == 'x' || dernier == 'z') return mot;
    if (bas.endsWith('eau') || bas.endsWith('au')) return '${mot}x';
    return '${mot}s';
  }

  /// Ramene un nom d'unite au singulier.
  ///
  /// Sert a lire une etiquette de portion : « 2 biscuits » designe l'unite
  /// « biscuit », et « 2 gateaux » designe « gateau ».
  static String _singulier(String mot) {
    if (mot.length < 3) return mot;
    final bas = mot.toLowerCase();
    if (bas.endsWith('aux')) return mot.substring(0, mot.length - 1);
    if (bas[bas.length - 1] != 's') return mot;
    final avantDernier = bas[bas.length - 2];
    if (avantDernier == 's' || avantDernier == 'i' || avantDernier == 'u') {
      // « mais », « jus » : le « s » fait partie du mot.
      return mot;
    }
    return mot.substring(0, mot.length - 1);
  }

  Map<String, dynamic> toJson() => {'label': label, 'grams': grams};

  /// Relit une portion stockee. Retourne `null` si elle est inexploitable :
  /// une portion sans nom ou de poids nul ne doit pas etre proposee.
  static Portion? depuisJson(Object? json) {
    if (json is! Map) return null;
    final label = json['label'];
    final grams = (json['grams'] as num?)?.toDouble();
    if (label is! String || grams == null) return null;
    final portion = Portion(label: label, grams: grams);
    return portion.estValide ? portion : null;
  }

  /// Deduit une portion d'une etiquette de portion, quand elle est exploitable.
  ///
  /// « 2 biscuits (25 g) » donne une portion de **12,5 g** nommee « biscuit » :
  /// les grammes annonces valent pour deux unites, et les confondre avec une
  /// seule doublerait la portion proposee. C'est le piege principal de ces
  /// etiquettes, et il est silencieux — d'ou ce calcul plutot qu'une lecture
  /// directe.
  ///
  /// Quand l'etiquette ne suit pas cette forme (« une part », « 125 g »), on ne
  /// devine rien : mieux vaut ne pas proposer de portion que d'en proposer une
  /// fausse.
  static Portion? depuisEtiquette(String? etiquette, double? grammes) {
    if (etiquette == null || grammes == null || grammes <= 0) return null;

    final texte = etiquette.trim();
    final correspondance = RegExp(
      r'^(\d+(?:[.,]\d+)?)\s+([^\d(]{2,24})',
    ).firstMatch(texte);
    if (correspondance == null) return null;

    final nombre = double.tryParse(
      correspondance.group(1)!.replaceAll(',', '.'),
    );
    final mot = correspondance.group(2)!.trim();
    if (nombre == null || nombre <= 0 || mot.isEmpty) return null;

    // L'unite est ramenee au singulier : l'etiquette dit « 2 biscuits », la
    // portion se nomme « biscuit ».
    final unite = nombre >= 2 ? _singulier(mot) : mot;
    final parUnite = grammes / nombre;
    final portion = Portion(label: unite, grams: parUnite);
    return portion.estValide ? portion : null;
  }

  /// Cle identifiant l'aliment auquel une portion se rattache.
  ///
  /// La reference de source prime : un code-barres ou un code Ciqual designe un
  /// produit precis, alors qu'un nom peut etre ecrit de deux facons. Le nom
  /// normalise ne sert que de repli, pour les aliments saisis a la main.
  static String clePour({
    required String source,
    String? sourceRef,
    required String nom,
  }) {
    final reference = sourceRef?.trim();
    if (reference != null && reference.isNotEmpty) {
      return '$source:$reference';
    }
    return 'nom:${nom.trim().toLowerCase()}';
  }

  @override
  bool operator ==(Object other) =>
      other is Portion && other.label == label && other.grams == grams;

  @override
  int get hashCode => Object.hash(label, grams);

  @override
  String toString() => 'Portion($label, $grams g)';
}

/// Unite de reference sur laquelle porte un apercu de valeurs.
///
/// « pour 1 pot (125 g) » quand une portion est connue, « pour 100 g » sinon.
///
/// Sans portion, le repere reste les 100 g : c'est l'unite de reference de
/// toutes les tables, et le masquer laisserait croire que le chiffre affiche
/// vaut pour la portion annoncee a cote. Un nombre sans son unite est pire
/// qu'un nombre avec l'ancienne.
String referenceDePortion(Portion? portion) =>
    portion == null ? 'pour 100 g' : 'pour ${portion.etiquetteUnite}';
