import 'nutrition_values.dart';

/// Un aliment identifie par l'analyse d'image, avant correspondance avec une
/// base nutritionnelle.
///
/// Le modele ne fournit JAMAIS de valeurs nutritionnelles : uniquement un nom
/// et un poids estime. Les valeurs sont ensuite tirees de Ciqual ou d'Open Food
/// Facts. Cela evite qu'un modele invente des chiffres.
class DetectedFood {
  const DetectedFood({
    required this.name,
    required this.estimatedWeightG,
    required this.confidence,
    this.matchedFoodId,
    this.matchedName,
    this.per100g,
  });

  /// Nom generique propose par le modele, en francais.
  final String name;

  /// Poids estime en grammes.
  final double estimatedWeightG;

  /// Confiance du modele, entre 0 et 1.
  final double confidence;

  /// Identifiant de l'aliment retenu dans la base de reference, une fois la
  /// correspondance effectuee.
  final String? matchedFoodId;

  /// Nom de l'aliment retenu dans la base, qui peut differer du nom detecte.
  final String? matchedName;

  /// Valeurs pour 100 g issues de la base de reference.
  final NutritionValues? per100g;

  /// Vrai lorsque l'aliment a ete rapproche d'une entree d'une base fiable.
  bool get isMatched => per100g != null;

  /// Vrai si la confiance est faible : l'interface doit alors le signaler.
  bool get isUncertain => confidence < 0.65;

  DetectedFood copyWith({
    String? name,
    double? estimatedWeightG,
    double? confidence,
    String? matchedFoodId,
    String? matchedName,
    NutritionValues? per100g,
  }) {
    return DetectedFood(
      name: name ?? this.name,
      estimatedWeightG: estimatedWeightG ?? this.estimatedWeightG,
      confidence: confidence ?? this.confidence,
      matchedFoodId: matchedFoodId ?? this.matchedFoodId,
      matchedName: matchedName ?? this.matchedName,
      per100g: per100g ?? this.per100g,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'estimatedWeightG': estimatedWeightG,
        'confidence': confidence,
        'matchedFoodId': matchedFoodId,
        'matchedName': matchedName,
        'per100g': per100g?.toJson(),
      };

  factory DetectedFood.fromJson(Map<String, dynamic> json) => DetectedFood(
        name: (json['name'] as String?) ?? 'Aliment',
        estimatedWeightG: ((json['estimatedWeightG'] as num?) ?? 0).toDouble(),
        confidence: ((json['confidence'] as num?) ?? 0.5).toDouble(),
        matchedFoodId: json['matchedFoodId'] as String?,
        matchedName: json['matchedName'] as String?,
        per100g: json['per100g'] == null
            ? null
            : NutritionValues.fromJson((json['per100g'] as Map).cast<String, dynamic>()),
      );
}

/// Resultat complet d'une analyse de repas par photo.
class MealAnalysisResult {
  const MealAnalysisResult({
    required this.foods,
    required this.overallConfidence,
    this.notes,
    this.promptVersion,
  });

  static const MealAnalysisResult empty = MealAnalysisResult(foods: [], overallConfidence: 0);

  final List<DetectedFood> foods;
  final double overallConfidence;

  /// Explication courte fournie par le modele.
  final String? notes;

  /// Version du prompt utilisee, pour diagnostiquer un changement de qualite.
  final String? promptVersion;

  bool get isEmpty => foods.isEmpty;

  /// Vrai si l'ensemble de l'analyse merite une verification de l'utilisateur.
  bool get isLowConfidence => overallConfidence < 0.65;

  Map<String, dynamic> toJson() => {
        'foods': foods.map((food) => food.toJson()).toList(),
        'overallConfidence': overallConfidence,
        'notes': notes,
        'promptVersion': promptVersion,
      };

  factory MealAnalysisResult.fromJson(Map<String, dynamic> json) => MealAnalysisResult(
        foods: ((json['foods'] as List?) ?? const [])
            .map((item) => DetectedFood.fromJson((item as Map).cast<String, dynamic>()))
            .toList(),
        overallConfidence: ((json['overallConfidence'] as num?) ?? 0).toDouble(),
        notes: json['notes'] as String?,
        promptVersion: json['promptVersion'] as String?,
      );
}

/// Valeurs extraites d'une photo d'etiquette nutritionnelle.
class LabelExtraction {
  const LabelExtraction({
    required this.per100g,
    required this.confidence,
    this.productName,
    this.brand,
    this.packageQuantity,
    this.basis = '100g',
    this.notes,
    this.saturatedFat,
  });

  final NutritionValues per100g;
  final double confidence;
  final String? productName;
  final String? brand;
  final String? packageQuantity;

  /// Base des valeurs : « 100g » ou « 100ml ».
  final String basis;

  final String? notes;

  /// Les acides gras satures ne font pas partie de [NutritionValues] construit
  /// par defaut : on les conserve ici pour ne pas les perdre.
  final double? saturatedFat;

  bool get isLowConfidence => confidence < 0.6;

  /// Nom propose pour l'aliment cree a partir de l'etiquette.
  String get suggestedName {
    final parts = <String>[
      if (productName != null && productName!.isNotEmpty) productName!,
      if (brand != null && brand!.isNotEmpty) brand!,
    ];
    return parts.isEmpty ? 'Produit etiquete' : parts.join(' — ');
  }

  Map<String, dynamic> toJson() => {
        'per100g': per100g.toJson(),
        'confidence': confidence,
        'productName': productName,
        'brand': brand,
        'packageQuantity': packageQuantity,
        'basis': basis,
        'notes': notes,
        'saturatedFat': saturatedFat,
      };

  factory LabelExtraction.fromJson(Map<String, dynamic> json) {
    final base = (json['per100g'] as Map?)?.cast<String, dynamic>() ?? const {};
    return LabelExtraction(
      per100g: NutritionValues.fromJson(base),
      confidence: ((json['confidence'] as num?) ?? 0.5).toDouble(),
      productName: json['productName'] as String?,
      brand: json['brand'] as String?,
      packageQuantity: json['packageQuantity'] as String?,
      basis: (json['basis'] as String?) ?? '100g',
      notes: json['notes'] as String?,
      saturatedFat: (json['saturatedFat'] as num?)?.toDouble(),
    );
  }
}
