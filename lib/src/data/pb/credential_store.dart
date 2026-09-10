import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SavedCredentials {
  const SavedCredentials(this.email, this.password);
  final String email;
  final String password;
}

/// Optional "remember me" storage for the sign-in form.
///
/// Uses the keychain / keystore on iOS and Android. On desktop, where secure
/// storage is unreliable, it falls back to `shared_preferences` — the saved
/// password is then only lightly obscured (base64), readable by anything with
/// access to the user's account. The checkbox is off by default and the values
/// are cleared on an unchecked sign-in.
class CredentialStore {
  static const _key = 'pb_saved_credentials';

  static bool get _mobile =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);
  static const _secure = FlutterSecureStorage();

  static Future<void> _writeRaw(String value) async {
    if (_mobile) {
      try {
        await _secure.write(key: _key, value: value);
        return;
      } catch (_) {/* fall through */}
    }
    (await SharedPreferences.getInstance()).setString(_key, value);
  }

  static Future<String?> _readRaw() async {
    if (_mobile) {
      try {
        final v = await _secure.read(key: _key);
        if (v != null) return v;
      } catch (_) {}
    }
    return (await SharedPreferences.getInstance()).getString(_key);
  }

  static Future<void> _deleteRaw() async {
    try {
      await _secure.delete(key: _key);
    } catch (_) {}
    (await SharedPreferences.getInstance()).remove(_key);
  }

  static Future<void> save(String email, String password) => _writeRaw(
        jsonEncode({
          'email': email,
          'password': base64Encode(utf8.encode(password)),
        }),
      );

  static Future<SavedCredentials?> load() async {
    final raw = await _readRaw();
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return SavedCredentials(
        m['email'] as String? ?? '',
        utf8.decode(base64Decode(m['password'] as String? ?? '')),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() => _deleteRaw();
}
