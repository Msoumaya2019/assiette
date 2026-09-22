import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/session.dart';

/// Stockage des secrets locaux.
///
/// La cle d'analyse et la session du compte sont conservees dans le trousseau du
/// systeme : Keychain sur iOS, Keystore sur Android. Elles ne sont jamais
/// ecrites dans le binaire, ni dans les preferences partagees, ni dans la base
/// de donnees.
///
/// Ce qui n'est **pas** ici, et pourquoi
/// -------------------------------------
/// L'adresse du projet et la cle publique n'y sont pas : elles viennent de la
/// configuration de compilation (`AppConfig.supabaseUrl`,
/// `AppConfig.supabaseAnonKey`), et la cle publique est publique par
/// conception. Les ranger dans un trousseau leur donnerait l'apparence d'un
/// secret, et ferait croire que leur fuite serait grave — alors que la
/// protection repose sur les politiques RLS, pas sur leur confidentialite.
class SecureStore {
  SecureStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  static const String _providerKeyKey = 'provider_api_key';
  static const String _sessionKey = 'session';

  // --- la cle d'analyse --------------------------------------------------

  Future<bool> hasProviderKey() async {
    final value = await _storage.read(key: _providerKeyKey);
    return value != null && value.trim().isNotEmpty;
  }

  Future<String?> readProviderKey() async {
    final value = await _storage.read(key: _providerKeyKey);
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  Future<void> writeProviderKey(String key) =>
      _storage.write(key: _providerKeyKey, value: key.trim());

  Future<void> deleteProviderKey() => _storage.delete(key: _providerKeyKey);

  // --- la session --------------------------------------------------------

  /// La session rangee, ou `null` s'il n'y en a pas d'exploitable.
  ///
  /// Un contenu illisible se lit comme une **absence**, jamais comme une
  /// erreur : ce qui est range la peut avoir ete ecrit par une version
  /// precedente, et faire tomber l'application au demarrage serait le pire
  /// moment pour decouvrir une incompatibilite de format.
  ///
  /// Il n'y a **pas** de controle d'ecriture vide avant le decodage, et c'est
  /// voulu : `jsonDecode` refuse deja le vide et les espaces, donc une
  /// valeur blanche suivrait exactement le meme chemin avec ou sans ce
  /// controle. Aucun test ne pourrait distinguer les deux, et une regle
  /// qu'aucune mesure ne separe est un passif — elle coute une branche a
  /// relire. Le `catch` couvre tout ce qui n'est pas lisible, d'un seul geste.
  Future<Session?> lireSession() async {
    final brut = await _storage.read(key: _sessionKey);
    if (brut == null) return null;
    try {
      return Session.depuisJson(jsonDecode(brut));
    } on FormatException {
      return null;
    }
  }

  /// Range la session, en une seule ecriture.
  ///
  /// Le jeton de rafraichissement est la raison d'etre de ce stockage : c'est
  /// lui qui permet de rouvrir une session **sans mot de passe** au lancement
  /// suivant. Le jeton d'acces, lui, ne vit qu'une heure — le ranger aussi
  /// evite un aller-retour a chaque demarrage, et il ne quitte pas le trousseau.
  Future<void> ecrireSession(Session session) =>
      _storage.write(key: _sessionKey, value: jsonEncode(session.versJson()));

  Future<void> effacerSession() => _storage.delete(key: _sessionKey);

  /// Efface tous les secrets. Utilise par la suppression de compte.
  Future<void> wipe() => _storage.deleteAll();
}
