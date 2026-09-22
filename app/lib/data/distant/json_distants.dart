/// Conversion entre le `jsonb` du serveur et le texte local.
///
/// Le troisieme piege de type, apres les dates et les booleens
/// -----------------------------------------------------------
/// `templates.items` et `favorites.payload` sont des `jsonb` cote serveur, et
/// des colonnes `TEXT` cote local, ou l'application range du JSON deja
/// serialise. Sans conversion, les deux cotes ne decrivent jamais la meme
/// chose : le serveur rend une liste ou un objet, le local attend une chaine.
/// L'ecriture insererait une liste dans une colonne texte, et les empreintes
/// differeraient toujours — meme consequence que pour les deux autres pieges :
/// l'arbitrage trancherait toujours dans le meme sens, et la synchronisation ne
/// convergerait jamais.
///
/// Pourquoi la conversion est **toujours** une serialisation
/// --------------------------------------------------------
/// La tentation est de rendre un texte tel quel, en se disant qu'il est deja du
/// JSON. C'est faux pour un `jsonb` **scalaire** : un `jsonb` qui contient la
/// chaine `hello` revient en Dart comme la chaine `hello`, sans guillemets, et
/// la rendre telle quelle perdrait l'information. Le local, lui, porte
/// `"hello"` — avec les guillemets, parce que c'est ce que `jsonEncode` ecrit.
///
/// `texteDepuisJson` serialise donc **toujours**, et l'aller-retour redevient
/// symetrique :
///
///     local '"hello"'  ->  jsonDecode  ->  'hello'  ->  serveur
///     serveur 'hello'  ->  jsonEncode  ->  '"hello"'  ->  local
///
/// Ce qu'un `jsonb` ne conserve pas
/// --------------------------------
/// L'ordre des cles et les espaces. Un texte local `{"b":2,"a":1}` revient du
/// serveur en `{"a":1,"b":2}` : les deux textes diffèrent, donc les empreintes
/// aussi. Le premier passage ecrit la forme du serveur en local, et le suivant
/// trouve les deux cotes d'accord. **Deux passages, jamais une divergence** —
/// c'est la propriete qui compte, et elle est eprouvee.
library;

import 'dart:convert';

/// Le texte local depuis ce que PostgREST rend pour un `jsonb`.
///
/// Serialise toujours, y compris pour une chaine : voir l'en-tete.
String? texteDepuisJson(Object? valeur) =>
    valeur == null ? null : jsonEncode(valeur);

/// Ce qu'il faut envoyer a un `jsonb`, depuis le texte local.
///
/// Un texte illisible **leve** — `jsonDecode` rend un `FormatException`. C'est
/// voulu : une valeur par defaut inventee ferait disparaitre le contenu d'un
/// modele de repas ou d'un favori sans que rien ne le signale, et une donnee
/// perdue en silence vaut moins qu'une synchronisation refusee.
///
/// Une valeur deja decodee passe telle quelle : la fonction ne defait pas ce
/// qu'un autre a fait, ce qui la rend sure a appeler deux fois.
Object? jsonDepuisTexte(Object? valeur) {
  if (valeur == null) return null;
  if (valeur is String) return jsonDecode(valeur);
  return valeur;
}
