import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stockage des secrets locaux.
///
/// La cle d'analyse est conservee dans le trousseau du systeme : Keychain sur
/// iOS, Keystore sur Android. Elle n'est jamais ecrite dans le binaire, ni dans
/// les preferences partagees, ni dans la base de donnees.
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

  /// Efface tous les secrets. Utilise par la suppression de compte.
  Future<void> wipe() => _storage.deleteAll();
}
