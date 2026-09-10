import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the PocketBase auth blob across launches.
///
/// `flutter_secure_storage` (the keychain / keystore) is the right home for a
/// session token on iOS and Android. On desktop it is unreliable — ad-hoc
/// signed macOS debug builds silently fail keychain writes — so there we fall
/// back to `shared_preferences`, which is adequate for a per-user desktop app.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();

  static TokenStore create() {
    final mobile = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
    return mobile ? _SecureTokenStore() : _PrefsTokenStore();
  }
}

class _SecureTokenStore implements TokenStore {
  static const _storage = FlutterSecureStorage();
  static const _key = 'pb_auth';

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String value) async {
    try {
      await _storage.write(key: _key, value: value);
    } catch (_) {/* best effort */}
  }

  @override
  Future<void> delete() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}

class _PrefsTokenStore implements TokenStore {
  static const _key = 'pb_auth';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String value) async =>
      (await SharedPreferences.getInstance()).setString(_key, value);

  @override
  Future<void> delete() async =>
      (await SharedPreferences.getInstance()).remove(_key);
}
