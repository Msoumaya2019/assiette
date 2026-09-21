import 'food.dart';
import 'nutrition_values.dart';
import 'portion.dart';

/// Un apercu de valeurs, **et** l'unite sur laquelle il porte.
///
/// Les deux sont produits ensemble, par la meme fonction, parce qu'ils se sont
/// deja contredits : l'ecran produit annoncait « 12 g de glucides pour 1 pot
/// (125 g) » alors que 12 etait la valeur des 100 g — le pot en contient 15.
/// Le nombre etait juste, son etiquette fausse, et rien ne le signalait.
///
/// Un nombre avec la mauvaise unite est pire qu'un nombre avec l'ancienne : il
/// se lit comme une information. C'est pourquoi il n'existe plus de fonction
/// qui rende l'etiquette seule — l'obtenir oblige desormais a obtenir les
/// valeurs qui vont avec, et les deux ne peuvent plus diverger.
///
/// Sans portion exploitable, le repere reste les 100 g : c'est l'unite de
/// reference de toutes les tables, et le masquer laisserait croire que le
/// chiffre affiche vaut pour une portion qui n'existe pas. Une portion de poids
/// nul ou negatif est traitee comme absente : [NutritionValues.forGrams] rend
/// alors zero, et l'ecran afficherait « 0 g de glucides pour 0 g ».
({NutritionValues valeurs, String reference}) apercuDePortion(
  Food food,
  Portion? portion,
) {
  if (portion == null || !portion.estValide) {
    return (valeurs: food.per100g, reference: 'pour 100 g');
  }
  return (
    valeurs: food.per100g.forGrams(portion.grams),
    reference: 'pour ${portion.etiquetteUnite}',
  );
}
