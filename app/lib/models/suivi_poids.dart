/// Suivi du poids et des mensurations.
///
/// Ce suivi est **personnel** : l'application enregistre ce que l'utilisateur
/// saisit et le lui montre. Elle ne propose aucune cible, ne suggere aucune
/// valeur, ne calcule aucun indice et ne formule aucun conseil. C'est la meme
/// regle que pour les objectifs nutritionnels, et elle est deliberee : une
/// application qui suggere un poids cible fait de la prescription, ce qui n'est
/// ni son role ni sa competence.
library;

/// Une mesure corporelle suivie.
///
/// La liste est fermee : ajouter un type est une ligne de plus, et un type
/// inconnu relu depuis une base plus recente est **ignore** au lieu de faire
/// echouer la lecture. Une application plus ancienne continue donc de
/// fonctionner sur des donnees plus recentes.
enum TypeMesure {
  taille('Tour de taille', 'au nombril'),
  hanches('Tour de hanches', 'au plus large'),
  poitrine('Tour de poitrine', 'au plus large'),
  bras('Tour de bras', 'contracte'),
  cuisse('Tour de cuisse', 'au plus large'),
  cou('Tour de cou', 'sous la pomme d\'Adam');

  const TypeMesure(this.displayLabel, this.precision);

  /// Libelle affiche a l'utilisateur.
  final String displayLabel;

  /// Ou placer le metre, en une phrase courte.
  final String precision;

  /// Unite de toutes les mesures : le centimetre.
  static const String unite = 'cm';

  static TypeMesure? fromId(String? id) {
    for (final type in TypeMesure.values) {
      if (type.name == id) return type;
    }
    return null;
  }
}

/// Une mesure corporelle relevee a une date.
class Mesure {
  const Mesure({
    required this.id,
    required this.le,
    required this.type,
    required this.valeurCm,
  });

  final String id;
  final DateTime le;
  final TypeMesure type;

  /// Valeur en centimetres.
  final double valeurCm;

  Map<String, dynamic> toJson() => {
    'id': id,
    'le': le.toIso8601String(),
    'type': type.name,
    'valeurCm': valeurCm,
  };

  static Mesure? depuisJson(Map<String, dynamic> json) {
    final type = TypeMesure.fromId(json['type'] as String?);
    final valeur = (json['valeurCm'] as num?)?.toDouble();
    final le = DateTime.tryParse((json['le'] as String?) ?? '');
    if (type == null || valeur == null || le == null) return null;
    return Mesure(
      id: (json['id'] as String?) ?? 'mesure-${le.microsecondsSinceEpoch}',
      le: le,
      type: type,
      valeurCm: valeur,
    );
  }

  @override
  String toString() => 'Mesure(${type.name}, $valeurCm cm, $le)';
}

/// Une pesee.
class Pesee {
  const Pesee({
    required this.id,
    required this.le,
    required this.poidsKg,
    this.note,
  });

  final String id;
  final DateTime le;

  /// Poids en kilogrammes.
  final double poidsKg;

  /// Remarque libre : « a jeun », « apres sport ».
  final String? note;

  Map<String, dynamic> toJson() => {
    'id': id,
    'le': le.toIso8601String(),
    'poidsKg': poidsKg,
    'note': note,
  };

  static Pesee? depuisJson(Map<String, dynamic> json) {
    final poids = (json['poidsKg'] as num?)?.toDouble();
    final le = DateTime.tryParse((json['le'] as String?) ?? '');
    if (poids == null || le == null) return null;
    return Pesee(
      id: (json['id'] as String?) ?? 'pesee-${le.microsecondsSinceEpoch}',
      le: le,
      poidsKg: poids,
      note: json['note'] as String?,
    );
  }

  @override
  String toString() => 'Pesee($poidsKg kg, $le)';
}

/// Poids vise par l'utilisateur.
///
/// L'application ne propose **aucune** valeur par defaut et n'en suggere
/// jamais : ce nombre vient de l'utilisateur, ou d'un professionnel qui le
/// suit. Aucun indice de masse corporelle n'est calcule a partir de ce chiffre,
/// et aucun ecart n'est commente comme bon ou mauvais.
class ObjectifPoids {
  const ObjectifPoids({this.cibleKg});

  static const ObjectifPoids aucun = ObjectifPoids();

  final double? cibleKg;

  bool get estDefini => cibleKg != null;

  ObjectifPoids copyWith({double? cibleKg, bool effacer = false}) =>
      ObjectifPoids(cibleKg: effacer ? null : (cibleKg ?? this.cibleKg));

  Map<String, dynamic> toJson() => {'cibleKg': cibleKg};

  factory ObjectifPoids.fromJson(Map<String, dynamic> json) =>
      ObjectifPoids(cibleKg: (json['cibleKg'] as num?)?.toDouble());
}

/// Un point de la courbe.
class PointPoids {
  const PointPoids({required this.le, required this.kg});

  final DateTime le;
  final double kg;

  @override
  String toString() => 'PointPoids($kg kg, $le)';
}

DateTime _jour(DateTime date) => DateTime(date.year, date.month, date.day);

/// Suite de points formant une courbe de poids.
///
/// Les pesees d'une meme journee sont ramenees a **une seule**, la derniere :
/// se peser matin et soir ne doit pas dessiner un aller-retour vertical sur la
/// courbe. La liste complete reste consultable sous le graphique, donc rien
/// n'est perdu — c'est l'affichage qui se simplifie, pas la donnee.
class SeriePoids {
  const SeriePoids(this.points);

  static const SeriePoids vide = SeriePoids([]);

  /// Points tries du plus ancien au plus recent, un par journee.
  final List<PointPoids> points;

  /// Construit la serie, en ne gardant que les pesees posterieures a `depuis`.
  ///
  /// `Pesee` ne porte pas de pierre tombale : c'est la lecture en base
  /// (`AppDatabase.pesees`) qui ecarte les pesees supprimees. Cette fonction
  /// fait donc l'hypothese qu'on lui passe des pesees vivantes, et ne peut pas
  /// la verifier.
  factory SeriePoids.depuis(Iterable<Pesee> pesees, {DateTime? depuis}) {
    final retenues = <DateTime, PointPoids>{};

    for (final pesee in pesees) {
      if (depuis != null && pesee.le.isBefore(depuis)) continue;
      final jour = _jour(pesee.le);
      final precedent = retenues[jour];
      if (precedent == null || pesee.le.isAfter(precedent.le)) {
        retenues[jour] = PointPoids(le: pesee.le, kg: pesee.poidsKg);
      }
    }

    final points = retenues.values.toList()
      ..sort((a, b) => a.le.compareTo(b.le));
    return SeriePoids(points);
  }

  bool get estVide => points.isEmpty;

  int get longueur => points.length;

  PointPoids? get premier => points.isEmpty ? null : points.first;

  PointPoids? get dernier => points.isEmpty ? null : points.last;

  double? get premiereKg => premier?.kg;

  double? get derniereKg => dernier?.kg;

  /// Ecart entre la derniere et la premiere pesee de la serie.
  ///
  /// Negatif quand le poids a baisse. Aucun jugement n'est porte sur ce signe :
  /// l'application l'affiche, elle ne le qualifie pas.
  double? get variationKg {
    if (points.length < 2) return null;
    return points.last.kg - points.first.kg;
  }

  double? get minKg {
    if (points.isEmpty) return null;
    return points.map((point) => point.kg).reduce((a, b) => a < b ? a : b);
  }

  double? get maxKg {
    if (points.isEmpty) return null;
    return points.map((point) => point.kg).reduce((a, b) => a > b ? a : b);
  }

  /// Bornes de l'axe vertical, objectif compris.
  ///
  /// L'objectif est inclus dans le cadrage : une ligne de cible hors du cadre
  /// serait invisible, et l'utilisateur croirait qu'elle a disparu. Un kilo de
  /// marge est ajoute de chaque cote, et une serie plate recoit une marge
  /// minimale pour ne pas degenerer en axe de hauteur nulle.
  ({double min, double max}) bornes({double? objectifKg}) {
    final valeurs = <double>[
      ...points.map((point) => point.kg),
      if (objectifKg != null) objectifKg,
    ];
    if (valeurs.isEmpty) return (min: 0, max: 1);

    var min = valeurs.reduce((a, b) => a < b ? a : b);
    var max = valeurs.reduce((a, b) => a > b ? a : b);

    if (max - min < 1) {
      final centre = (min + max) / 2;
      min = centre - 0.5;
      max = centre + 0.5;
    }

    return (min: min - 1, max: max + 1);
  }

  @override
  String toString() => 'SeriePoids(${points.length} points)';
}

/// Tout le suivi en une seule lecture, pour que l'ecran n'ait qu'une source.
class SuiviPoids {
  const SuiviPoids({
    this.pesees = const [],
    this.mesures = const [],
    this.objectif = ObjectifPoids.aucun,
  });

  static const SuiviPoids vide = SuiviPoids();

  /// Pesees, de la plus recente a la plus ancienne.
  final List<Pesee> pesees;

  /// Mesures, de la plus recente a la plus ancienne.
  final List<Mesure> mesures;

  final ObjectifPoids objectif;

  bool get estVide => pesees.isEmpty && mesures.isEmpty;

  SeriePoids serie({DateTime? depuis}) =>
      SeriePoids.depuis(pesees, depuis: depuis);

  /// Mesures d'un type donne, de la plus recente a la plus ancienne.
  List<Mesure> mesuresDe(TypeMesure type) =>
      mesures.where((mesure) => mesure.type == type).toList();

  /// Derniere valeur connue pour chaque type renseigne.
  Map<TypeMesure, double> dernieresMesures() {
    final resultat = <TypeMesure, double>{};
    for (final mesure in mesures) {
      resultat.putIfAbsent(mesure.type, () => mesure.valeurCm);
    }
    return resultat;
  }

  SuiviPoids copyWith({
    List<Pesee>? pesees,
    List<Mesure>? mesures,
    ObjectifPoids? objectif,
  }) => SuiviPoids(
    pesees: pesees ?? this.pesees,
    mesures: mesures ?? this.mesures,
    objectif: objectif ?? this.objectif,
  );
}
