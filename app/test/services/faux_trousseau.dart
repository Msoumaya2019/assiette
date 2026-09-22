/// Un stockage en memoire, a la place du trousseau du systeme.
///
/// Le vrai trousseau — Keychain sur iOS, Keystore sur Android — ne s'ouvre pas
/// dans un test. `SecureStore` prend donc son stockage en parametre, et ce faux
/// prend sa place : c'est bien le chemin de code reel qui s'execute, avec la
/// lecture, l'ecriture, l'effacement et la relecture d'un contenu abime.
///
/// Il herite de la facade au lieu de l'implementer : c'est la facade que
/// `SecureStore` appelle, et c'est donc ses signatures qu'il faut respecter.
///
/// Trois fichiers de tests s'en servent — le trousseau, le compte, la section
/// Compte. Deux copies d'un faux finiraient par diverger, et la divergence se
/// lirait comme un test qui passe pour la mauvaise raison.
///
/// Ce qu'il **ne** peut pas etablir : que le vrai trousseau se comporte comme
/// lui. Cela demande un appareil, et cela reste a faire.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class FauxTrousseau extends FlutterSecureStorage {
  FauxTrousseau({this.effacementEchoue = false});

  /// Quand c'est vrai, `delete` leve.
  ///
  /// Un trousseau peut refuser de repondre, et c'est ce cas qu'il faut savoir
  /// traiter : une application ne doit pas se dire deconnectee alors que la
  /// session est encore rangee.
  final bool effacementEchoue;

  /// Ce que le trousseau porte, par cle.
  final Map<String, String> valeurs = {};

  /// Le nombre d'ecritures. Sert a verifier qu'une session part en **une** fois.
  int ecritures = 0;

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    ecritures++;
    if (value == null) {
      valeurs.remove(key);
    } else {
      valeurs[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => valeurs[key];

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (effacementEchoue) throw StateError('trousseau indisponible');
    valeurs.remove(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    valeurs.clear();
  }
}
