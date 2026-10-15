import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Passwords and private links go in the OS keychain:
/// Mac Keychain, Windows Credential Manager, Linux Secret Service.
class SecretStore {
  // On macOS the default "data protection" keychain needs a paid Apple
  // signing certificate. The regular login keychain works on unsigned builds.
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  Future<String?> read(String key) => _storage.read(key: key);
  Future<void> delete(String key) => _storage.delete(key: key);
}
