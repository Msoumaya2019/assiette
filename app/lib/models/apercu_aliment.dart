import 'food.dart';
import 'nutrition_values.dart';
import 'portion.dart';

/// L'unite de reference de toutes les tables, nommee une seule fois.
///
/// Deux copies de cette chaine finiraient par diverger, et c'est precisement ce
/// que ce fichier existe pour empecher.
const String reference100g = 'pour 100 g';

/// Ce qu'un ecran recoit pour chiffrer un aliment : les valeurs, l'unite sur
/// laquelle elles portent, et — quand les deux bases different — les memes
/// valeurs ramenees a 100 g.
typedef Apercu = ({
  NutritionValues valeurs,
  String reference,
  NutritionValues? comparable,
});

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
///
/// [comparable] porte les memes valeurs ramenees a 100 g, et vaut `null` quand
/// l'apercu **est** deja la valeur des 100 g — l'ecrire deux fois serait du
/// bruit.
///
/// Il existe pour une raison precise : une **liste** sert a comparer, et deux
/// produits dont l'un est chiffre pour un pot et l'autre pour 100 g ne se
/// comparent pas sans un calcul mental. Le chiffre comparable est donc rendu
/// avec les autres ; l'ecran n'a plus qu'a l'ecrire, et ne peut pas le
/// recalculer de travers puisqu'il ne le calcule pas.
///
/// La portion reste la valeur mise en avant, et c'est un choix assume : c'est
/// ce que l'utilisateur mange, et ce qu'il a demande (« pas toujours 100 g »).
/// Le chiffre comparable vient **a cote**, jamais a la place.
Apercu apercuDePortion(Food food, Portion? portion) {
  if (portion == null || !portion.estValide) {
    return (valeurs: food.per100g, reference: reference100g, comparable: null);
  }
  return (
    valeurs: food.per100g.forGrams(portion.grams),
    reference: 'pour ${portion.etiquetteUnite}',
    comparable: food.per100g,
  );
}
