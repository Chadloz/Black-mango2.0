import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../prefs.dart';

/// Logins live in Black Mango's own settings storage, so macOS never asks for
/// your Keychain password. Older logins are copied out of the Keychain once,
/// the first time they're needed, and the Keychain isn't touched after that.
class SecretStore {
  static const _keychain = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  static const _prefix = 'secret.';

  Future<void> write(String key, String value) => Prefs.setStr('$_prefix$key', value);

  Future<String?> read(String key) async {
    final v = Prefs.getStr('$_prefix$key');
    if (v != null) return v;
    if (Prefs.getBool('${_prefix}moved.$key')) return null;
    try {
      final old = await _keychain.read(key: key);
      await Prefs.setBool('${_prefix}moved.$key', true);
      if (old != null) {
        await Prefs.setStr('$_prefix$key', old);
        return old;
      }
    } catch (_) {}
    return null;
  }

  Future<void> delete(String key) => Prefs.setStr('$_prefix$key', null);
}
