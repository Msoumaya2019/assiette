# Politique de confidentialité — Assiette

**Dernière mise à jour : 18 septembre 2026**

Ce document décrit, sans zone d'ombre, quelles données l'application **Assiette**
traite, où elles vont, combien de temps elles sont conservées et comment les
effacer. Il est rédigé pour correspondre au comportement réel du code publié,
et non à une intention.

## 1. Qui est responsable

L'application est éditée par le développeur d'Assiette, joignable à l'adresse
indiquée dans la fiche du magasin d'applications. Aucune donnée n'est vendue,
louée ni transmise à un tiers à des fins publicitaires.

## 2. Ce qui reste sur votre téléphone

L'application fonctionne **par défaut sans compte et sans inscription**. Tout ce
qui suit est stocké uniquement dans l'espace privé de l'application, sur votre
appareil :

| Donnée | Emplacement | Pourquoi |
| --- | --- | --- |
| Repas enregistrés (aliments, poids, valeurs nutritionnelles) | Base SQLite locale | Historique, tableau de bord, favoris |
| Photos de repas que vous choisissez de conserver | Dossier privé de l'application | Retrouver un repas dans l'historique |
| Objectifs personnels, réglages, thème | Base locale et stockage sécurisé du système | Fonctionnement de l'application |

Ces données ne quittent jamais l'appareil. Personne d'autre que vous ne peut y
accéder. Les désinstaller revient à les effacer : l'application ne conserve
aucune copie distante.

## 3. Ce qui quitte votre téléphone

Trois cas seulement, et jamais sans une action de votre part.

### 3.1 L'analyse d'une photo de repas

Lorsque vous demandez l'analyse d'un repas ou d'une étiquette nutritionnelle,
**la photo que vous venez de prendre est transmise** à un service d'analyse
hébergé sur l'infrastructure Supabase, qui la fait analyser par un modèle de
vision (DeepSeek). Sont transmis :

- l'image, encodée en base64, après compression par l'application ;
- éventuellement une seconde image, si vous choisissez l'estimation précise ;
- éventuellement la taille de portion que vous avez indiquée, et le texte libre
  que vous avez saisi pour aider l'analyse.

Ne sont transmis **ni votre nom, ni votre adresse électronique, ni aucun
identifiant de compte, ni la position géographique, ni la liste de vos autres
repas**. Aucune image n'est conservée par le service d'analyse : elle est
traitée puis oubliée, et seul le résultat (noms d'aliments et poids estimés)
revient à l'application.

### 3.2 La recherche d'un produit ou d'un aliment

- **Code-barres et recherche de produits** : le code-barres ou les mots-clés
  sont envoyés à [Open Food Facts](https://world.openfoodfacts.org), base
  collaborative libre. Aucune donnée personnelle n'accompagne la requête, mais
  votre adresse IP est techniquement visible de ce service, comme pour toute
  visite de site web.
- **Aliments génériques** : la table Ciqual de l'ANSES est **embarquée dans
  l'application**. Ces recherches ne passent par aucun réseau.

### 3.3 La mesure d'usage du service d'analyse

Le service d'analyse compte les requêtes **par adresse IP** sur une courte
fenêtre glissante, dans le seul but d'empêcher l'épuisement du quota et les
abus. Ce compteur est tenu en mémoire, n'est pas écrit sur disque et n'est
associé à aucun profil.

## 4. Ce que l'application ne fait pas

- Aucune publicité, aucun traçage publicitaire, aucun identifiant de
  publicité.
- Aucune revente ni partage de données avec des courtiers en données.
- Aucun accès à vos contacts, à votre agenda, à vos fichiers, à votre
  microphone ou à votre position.
- Aucune donnée de santé, aucun diagnostic, aucun traitement, aucune posologie.
  Les valeurs affichées sont des **estimations nutritionnelles** et ne
  remplacent pas l'avis d'un professionnel de santé.
- Aucun envoi de données en arrière-plan : rien ne part sans que vous ayez
  touché un bouton.

## 5. Permissions demandées, et pourquoi

| Permission | Usage exact |
| --- | --- |
| Appareil photo | Prendre la photo du repas ou de l'étiquette. Refus possible : vous pouvez choisir une photo existante. |
| Galerie (lecture d'une image choisie) | Sélectionner une photo déjà présente. Le système ne remet à l'application que l'image que vous désignez. |
| Internet | Analyse d'une photo, recherche de produits, envoi facultatif vers votre sauvegarde. |
| Notifications | Rappel facultatif, désactivé par défaut, programmé **localement** sur votre appareil. |

L'application n'écrit jamais dans votre galerie et n'accède à aucune autre
photo que celle que vous désignez.

## 6. Durée de conservation

- **Sur votre appareil** : aussi longtemps que vous gardez les données.
  Supprimer un repas l'efface immédiatement ; désinstaller l'application efface
  tout.
- **Côté analyse** : la photo n'est pas conservée. Seul un compteur de débit
  anonyme subsiste quelques minutes en mémoire.

## 7. Vos droits

Conformément au RGPD, vous disposez d'un droit d'accès, de rectification,
d'effacement, de limitation et d'opposition. L'application les exerce
directement, sans démarche :

- **Accès et rectification** : chaque repas est consultable et modifiable depuis
  l'historique.
- **Effacement** : chaque repas peut être supprimé un par un ; les réglages
  proposent une remise à zéro complète qui efface la base locale et les photos.
- **Portabilité** : vos données restant sur votre appareil, elles vous
  appartiennent déjà.

Aucun profilage n'étant réalisé et aucune donnée n'étant conservée côté serveur,
il n'existe pas de registre distant à interroger.

## 8. Enfants

L'application n'est pas destinée aux enfants de moins de 13 ans et ne collecte
sciemment aucune donnée les concernant.

## 9. Sécurité

- Les clés d'accès au service d'analyse **ne sont pas contenues dans
  l'application**. Elles résident côté serveur, dans un coffre de secrets ; une
  application décompilée ne les révèle donc pas.
- Les échanges se font en HTTPS.
- Les entrées envoyées au service d'analyse sont validées et bornées côté
  serveur (taille d'image, longueur des textes, nombre d'aliments).
- Les données locales sensibles sont confiées au stockage sécurisé du système
  (Keychain sur iOS, Keystore sur Android).

## 10. Évolution de cette politique

Toute modification substantielle sera publiée à cette adresse et signalée dans
les notes de version de l'application. La date en tête de document indique la
dernière révision.

## 11. Contact

Pour toute question relative à ces traitements, écrivez à l'adresse de contact
figurant dans la fiche du magasin d'applications.
