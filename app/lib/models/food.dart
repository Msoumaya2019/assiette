import 'nutrition_values.dart';

/// Provenance d'une valeur nutritionnelle. Affichage obligatoire dans le detail
/// d'un aliment : l'utilisateur doit pouvoir distinguer une donnee de reference
/// d'une estimation.
enum FoodSource {
  /// Table Ciqual (ANSES), embarquee dans l'application.
  ciqual('Ciqual', 'Table de reference ANSES'),

  /// Open Food Facts, pour les produits industriels identifies par code-barres.
  openFoodFacts('Open Food Facts', 'Base collaborative de produits'),

  /// Valeurs lues sur une etiquette photographiee.
  label('Etiquette', 'Valeurs lues sur la photo de l\'etiquette'),

  /// Saisie manuelle de l'utilisateur.
  manual('Manuel', 'Valeurs saisies a la main'),

  /// Estimees par le modele d'analyse, sans correspondance dans une base.
  ai('Estimation IA', 'Estimation automatique, a verifier');

  const FoodSource(this.displayLabel, this.description);

  /// Libelle affiche a l'utilisateur.
  ///
  /// Nomme `displayLabel` et non `label` : la constante `label` de cette
  /// enumeration designe les valeurs lues sur une etiquette, et un champ
  /// d'instance ne peut pas porter le nom d'une constante du meme type.
  final String displayLabel;

  final String description;

  static FoodSource fromId(String? id) {
    return FoodSource.values.firstWhere(
      (source) => source.name == id,
      orElse: () => FoodSource.manual,
    );
  }
}

/// Un aliment utilisable dans un repas : un nom, des valeurs pour 100 g, et la
/// provenance de ces valeurs.
class Food {
  const Food({
    required this.name,
    required this.per100g,
    required this.source,
    this.sourceRef,
    this.brand,
    this.imageUrl,
    this.servingSizeG,
    this.servingLabel,
    this.category,
  });

  /// Nom affiche, en francais.
  final String name;

  /// Valeurs nutritionnelles pour 100 g (ou 100 ml pour les boissons).
  final NutritionValues per100g;

  final FoodSource source;

  /// Identifiant dans la base d'origine : code Ciqual ou code-barres produit.
  final String? sourceRef;

  /// Marque, pour les produits industriels.
  final String? brand;

  /// Image du produit, si la source en fournit une.
  final String? imageUrl;

  /// Poids d'une portion usuelle, quand la source le fournit.
  final double? servingSizeG;

  /// Libelle de la portion, par exemple « 1 pot (125 g) ».
  final String? servingLabel;

  /// Groupe d'aliments, principalement pour les donnees Ciqual.
  final String? category;

  Food copyWith({
    String? name,
    NutritionValues? per100g,
    FoodSource? source,
    String? sourceRef,
    String? brand,
    String? imageUrl,
    double? servingSizeG,
    String? servingLabel,
    String? category,
  }) {
    return Food(
      name: name ?? this.name,
      per100g: per100g ?? this.per100g,
      source: source ?? this.source,
      sourceRef: sourceRef ?? this.sourceRef,
      brand: brand ?? this.brand,
      imageUrl: imageUrl ?? this.imageUrl,
      servingSizeG: servingSizeG ?? this.servingSizeG,
      servingLabel: servingLabel ?? this.servingLabel,
      category: category ?? this.category,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'per100g': per100g.toJson(),
        'source': source.name,
        'sourceRef': sourceRef,
        'brand': brand,
        'imageUrl': imageUrl,
        'servingSizeG': servingSizeG,
        'servingLabel': servingLabel,
        'category': category,
      };

  factory Food.fromJson(Map<String, dynamic> json) => Food(
        name: (json['name'] as String?) ?? 'Aliment',
        per100g: NutritionValues.fromJson(
          (json['per100g'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        source: FoodSource.fromId(json['source'] as String?),
        sourceRef: json['sourceRef'] as String?,
        brand: json['brand'] as String?,
        imageUrl: json['imageUrl'] as String?,
        servingSizeG: (json['servingSizeG'] as num?)?.toDouble(),
        servingLabel: json['servingLabel'] as String?,
        category: json['category'] as String?,
      );

  /// Nom complet incluant la marque, pour l'affichage en liste.
  String get displayName => brand == null || brand!.isEmpty ? name : '$name — $brand';

  @override
  String toString() => 'Food($name, ${per100g.carbs} g glucides/100 g, ${source.displayLabel})';
}
