import 'package:uuid/uuid.dart';

import 'food.dart';
import 'nutrition_values.dart';

const _uuid = Uuid();

/// Portion proposee a l'utilisateur, en complement du poids en grammes.
enum PortionSize {
  small('Petite', 0.7),
  medium('Moyenne', 1.0),
  large('Grande', 1.4);

  const PortionSize(this.label, this.factor);

  final String label;

  /// Coefficient applique au poids estime.
  final double factor;

  static PortionSize fromId(String? id) => PortionSize.values.firstWhere(
    (portion) => portion.name == id,
    orElse: () => PortionSize.medium,
  );
}

/// Comment le repas a ete constitue. Sert aux statistiques et a l'affichage.
enum MealSource {
  photo('Photo'),
  search('Recherche'),
  barcode('Code-barres'),
  label('Etiquette'),
  manual('Manuel'),
  template('Repas enregistre');

  const MealSource(this.displayLabel);

  /// Libelle affiche a l'utilisateur.
  ///
  /// Nomme `displayLabel` et non `label` : la constante `label` de cette
  /// enumeration designe une lecture d'etiquette, et un champ d'instance ne peut
  /// pas porter le nom d'une constante du meme type.
  final String displayLabel;

  static MealSource fromId(String? id) => MealSource.values.firstWhere(
    (source) => source.name == id,
    orElse: () => MealSource.manual,
  );
}

/// Un aliment dans un repas, avec sa quantite.
///
/// Les valeurs sont stockees pour 100 g ; le total est toujours recalcule.
class MealItem {
  MealItem({
    String? id,
    required this.food,
    required this.quantityG,
    this.confidence,
    this.portionSize,
    this.isEstimate = false,
    this.sortOrder = 0,
  }) : id = id ?? _uuid.v4();

  final String id;
  final Food food;

  /// Quantite consommee en grammes.
  double quantityG;

  /// Confiance de la detection automatique, entre 0 et 1. Nulle si saisie a la main.
  final double? confidence;

  /// Portion choisie par l'utilisateur, si elle a ete utilisee.
  final PortionSize? portionSize;

  /// Vrai lorsque la quantite provient d'une estimation visuelle.
  final bool isEstimate;

  final int sortOrder;

  /// Valeurs effectivement consommees pour cette quantite.
  NutritionValues get total => food.per100g.forGrams(quantityG);

  MealItem copyWith({
    Food? food,
    double? quantityG,
    double? confidence,
    PortionSize? portionSize,
    bool? isEstimate,
    int? sortOrder,
  }) {
    return MealItem(
      id: id,
      food: food ?? this.food,
      quantityG: quantityG ?? this.quantityG,
      confidence: confidence ?? this.confidence,
      portionSize: portionSize ?? this.portionSize,
      isEstimate: isEstimate ?? this.isEstimate,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'food': food.toJson(),
    'quantityG': quantityG,
    'confidence': confidence,
    'portionSize': portionSize?.name,
    'isEstimate': isEstimate,
    'sortOrder': sortOrder,
  };

  factory MealItem.fromJson(Map<String, dynamic> json) => MealItem(
    id: json['id'] as String?,
    food: Food.fromJson((json['food'] as Map).cast<String, dynamic>()),
    quantityG: (json['quantityG'] as num).toDouble(),
    confidence: (json['confidence'] as num?)?.toDouble(),
    portionSize: json['portionSize'] == null
        ? null
        : PortionSize.fromId(json['portionSize'] as String?),
    isEstimate: (json['isEstimate'] as bool?) ?? false,
    sortOrder: (json['sortOrder'] as int?) ?? 0,
  );
}

/// Un repas : un ensemble d'aliments a un instant donne.
class Meal {
  Meal({
    String? id,
    required this.eatenAt,
    this.name = 'Repas',
    List<MealItem>? items,
    this.source = MealSource.manual,
    this.notes,
    this.photoPath,
    this.isEstimate = true,
  }) : id = id ?? _uuid.v4(),
       items = items ?? <MealItem>[];

  final String id;

  /// Date et heure de consommation.
  DateTime eatenAt;

  String name;

  final List<MealItem> items;

  final MealSource source;

  String? notes;

  /// Chemin local de la photo, si elle a ete conservee.
  String? photoPath;

  /// Vrai lorsque les quantites proviennent d'une estimation.
  final bool isEstimate;

  /// Total du repas, recalcule a chaque appel : jamais stocke en doublon.
  NutritionValues get totals =>
      NutritionValues.sum(items.map((item) => item.total));

  double get totalGrams => items.fold(0, (sum, item) => sum + item.quantityG);

  bool get isEmpty => items.isEmpty;

  /// Confiance globale : moyenne ponderee par le poids des aliments detectes.
  /// Les aliments saisis a la main (confiance nulle) sont exclus du calcul.
  double? get overallConfidence {
    var weighted = 0.0;
    var weight = 0.0;
    for (final item in items) {
      final confidence = item.confidence;
      if (confidence == null) continue;
      weighted += confidence * item.quantityG;
      weight += item.quantityG;
    }
    if (weight <= 0) return null;
    return weighted / weight;
  }

  /// Vrai si au moins un aliment a une confiance faible : l'application invite
  /// alors l'utilisateur a verifier les quantites avant d'enregistrer.
  bool get needsReview {
    final confidence = overallConfidence;
    return confidence != null && confidence < 0.65;
  }

  Meal copyWith({
    DateTime? eatenAt,
    String? name,
    List<MealItem>? items,
    String? notes,
    String? photoPath,
  }) {
    return Meal(
      id: id,
      eatenAt: eatenAt ?? this.eatenAt,
      name: name ?? this.name,
      items: items ?? this.items,
      source: source,
      notes: notes ?? this.notes,
      photoPath: photoPath ?? this.photoPath,
      isEstimate: isEstimate,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'eatenAt': eatenAt.toIso8601String(),
    'name': name,
    'items': items.map((item) => item.toJson()).toList(),
    'source': source.name,
    'notes': notes,
    'photoPath': photoPath,
    'isEstimate': isEstimate,
  };

  factory Meal.fromJson(Map<String, dynamic> json) => Meal(
    id: json['id'] as String?,
    eatenAt: DateTime.parse(json['eatenAt'] as String),
    name: (json['name'] as String?) ?? 'Repas',
    items: ((json['items'] as List?) ?? const [])
        .map((item) => MealItem.fromJson((item as Map).cast<String, dynamic>()))
        .toList(),
    source: MealSource.fromId(json['source'] as String?),
    notes: json['notes'] as String?,
    photoPath: json['photoPath'] as String?,
    isEstimate: (json['isEstimate'] as bool?) ?? true,
  );
}

/// Totaux agreges sur une periode, pour le tableau de bord.
class NutritionSummary {
  const NutritionSummary({required this.totals, required this.mealCount});

  static const NutritionSummary empty = NutritionSummary(
    totals: NutritionValues.zero,
    mealCount: 0,
  );

  final NutritionValues totals;
  final int mealCount;
}
