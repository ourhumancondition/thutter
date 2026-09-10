import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../core/config.dart';
import 'token_store.dart';

/// Wraps a [PocketBase] instance and persists its auth store so the session
/// survives restarts and works offline.
class PocketBaseClient {
  PocketBaseClient._(this.pb);

  @visibleForTesting
  PocketBaseClient.forTest(this.pb);

  final PocketBase pb;

  static Future<PocketBaseClient> create() async {
    final tokens = TokenStore.create();
    final store = AsyncAuthStore(
      save: tokens.write,
      initial: await tokens.read(),
      clear: tokens.delete,
    );
    final pb = PocketBase(Config.pocketBaseUrl, authStore: store);
    return PocketBaseClient._(pb);
  }

  bool get isAuthenticated => pb.authStore.isValid;

  /// The signed-in user's record json, if any.
  Map<String, dynamic>? get authRecord => pb.authStore.record?.toJson();

  Future<void> clear() async => pb.authStore.clear();
}
