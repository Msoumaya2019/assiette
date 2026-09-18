# Sources des données et attributions

Ce fichier est embarqué dans l'application (`assets/legal/`) et repris dans les
fiches App Store et Google Play.

## Composition nutritionnelle des aliments

**Table Ciqual 2020** — Agence nationale de sécurité sanitaire de l'alimentation,
de l'environnement et du travail (ANSES).

- Source : https://ciqual.anses.fr/
- Licence : Licence Ouverte / Open Licence 2.0 (Etalab)
- Réutilisation libre, y compris commerciale, sous réserve de mention de la
  source et de la date de dernière mise à jour.
- Les données sont embarquées dans l'application (`assets/nutrition/ciqual.json`),
  générées par `tools/build_ciqual.py` à partir du fichier XML officiel
  `XML_2020_07_07.zip`.

## Produits alimentaires emballés

**Open Food Facts** — base de données collaborative et ouverte.

- Source : https://world.openfoodfacts.org/
- Base de données : Open Database License (ODbL)
- Contenus individuels : Database Contents License (DbCL)
- Images produits : Creative Commons Attribution ShareAlike (CC BY-SA)
- Consultée via l'API `https://world.openfoodfacts.org/api/v3.6/product/{code}.json`
  et le moteur de recherche `https://search.openfoodfacts.org/search`.
- Les données ne sont **pas** redistribuées : elles sont lues à la demande, à
  l'unité, au moment où l'utilisateur scanne un code-barres ou recherche un
  produit.

## Analyse d'image

Le modèle multimodal utilisé pour identifier les aliments et estimer les poids
est **`deepseek-flash`** (DeepSeek-V4.1-Flash), via une API compatible OpenAI.

- Documentation : https://api-docs.deepseek.com/guides/vision
- Le modèle ne fournit **que** des noms d'aliments et des poids estimés.
  Aucune valeur nutritionnelle ne provient de lui : celles-ci sont toujours
  calculées à partir de Ciqual ou d'Open Food Facts.

## Avertissement

Les quantités déduites d'une photographie sont des **estimations**. Elles
dépendent de l'angle de prise de vue, de l'éclairage et de l'absence d'échelle
visible. L'application ne prétend pas mesurer un poids réel.

L'application n'est pas un dispositif médical et ne fournit aucun diagnostic,
aucune recommandation thérapeutique ni aucune posologie.
