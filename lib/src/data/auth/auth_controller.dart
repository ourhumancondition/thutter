import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../core/config.dart';
import '../db/database.dart';
import '../models/models.dart';
import '../pb/credential_store.dart';
import '../pb/pocketbase_client.dart';
import '../providers.dart';

class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.error,
    this.busy = false,
  });

  final AuthStatus status;
  final AppUser? user;
  final String? error;
  final bool busy;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  @override
  bool operator ==(Object other) =>
      other is AuthState &&
      other.status == status &&
      other.user?.id == user?.id &&
      other.error == error &&
      other.busy == busy;

  @override
  int get hashCode => Object.hash(status, user?.id, error, busy);

  AuthState copyWith({
    AuthStatus? status,
    AppUser? user,
    String? error,
    bool? busy,
  }) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        error: error,
        busy: busy ?? this.busy,
      );
}

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Owns the session. First login must be online; afterwards the cached token
/// keeps the user signed in offline. A token is only discarded when the server
/// actively rejects it.
class AuthController extends Notifier<AuthState> {
  late final PocketBaseClient _client = ref.read(pocketBaseClientProvider);
  PocketBase get _pb => _client.pb;
  AppDatabase get _db => ref.read(databaseProvider);

  @override
  AuthState build() {
    // Deferred: a Notifier must not mutate `state` during build().
    Future.microtask(_bootstrap);
    return const AuthState(status: AuthStatus.unknown);
  }

  Future<void> _bootstrap() async {
    if (!_client.isAuthenticated) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }
    // We have a cached token → treat the user as signed in immediately.
    final cached = _client.authRecord;
    if (cached != null) {
      await _db.upsertFromServer(Config.cUsers, cached);
      state = AuthState(status: AuthStatus.authenticated, user: AppUser(cached));
    } else {
      state = const AuthState(status: AuthStatus.authenticated);
    }
    unawaited(_refreshInBackground());
  }

  Future<void> _refreshInBackground() async {
    try {
      final auth = await _pb.collection(Config.cUsers).authRefresh();
      final json = auth.record.toJson();
      await _db.upsertFromServer(Config.cUsers, json);
      state = state.copyWith(
          status: AuthStatus.authenticated, user: AppUser(json));
    } on ClientException catch (e) {
      // Only a real auth rejection logs the user out; network errors are ignored.
      if (e.statusCode == 401 || e.statusCode == 403) {
        await signOut();
      }
    } catch (_) {
      // offline / transient — keep the cached session
    }
  }

  Future<void> signIn(
    String identity,
    String password, {
    bool remember = false,
  }) async {
    state = state.copyWith(busy: true, error: null);
    try {
      final auth = await _pb
          .collection(Config.cUsers)
          .authWithPassword(identity.trim(), password);
      // Fresh sign-in starts from a clean slate — no stale rows and, in debug
      // builds, no demo records that would otherwise be pushed to the server.
      await _db.wipe();
      if (remember) {
        await CredentialStore.save(identity.trim(), password);
      } else {
        await CredentialStore.clear();
      }
      final json = auth.record.toJson();
      await _db.upsertFromServer(Config.cUsers, json);
      state = AuthState(
        status: AuthStatus.authenticated,
        user: AppUser(json),
        busy: false,
      );
      unawaited(ref.read(syncServiceProvider).syncAll());
    } on ClientException catch (e) {
      state = state.copyWith(
        busy: false,
        error: _messageFor(e),
      );
    } catch (e) {
      state = state.copyWith(
        busy: false,
        error: 'Could not reach the server. Check your connection and try again.',
      );
    }
  }

  /// Debug helper: skip the network and drop straight into the app with a
  /// synthetic user. Clears any real token first so demo data never touches
  /// the server.
  Future<void> enterDemoMode() async {
    await _client.clear();
    final json = <String, dynamic>{
      'id': 'local_user_demo',
      'email': 'demo@thyme.local',
      'display_name': 'Demo User',
      'first_name': 'Demo',
      'last_name': 'User',
      'tenants': ['local_tenant_demo'],
      'created': DateTime.now().toUtc().toIso8601String(),
      'updated': DateTime.now().toUtc().toIso8601String(),
      'collectionName': Config.cUsers,
    };
    await _db.upsertLocal(Config.cUsers, json);
    state = AuthState(status: AuthStatus.authenticated, user: AppUser(json));
  }

  Future<void> signOut() async {
    await _client.clear();
    await CredentialStore.clear();
    await _db.wipe();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  String _messageFor(ClientException e) {
    if (e.statusCode == 400) return 'Incorrect email or password.';
    if (e.statusCode == 0) {
      return 'Could not reach the server. Check your connection.';
    }
    return e.response['message']?.toString() ?? 'Sign in failed (${e.statusCode}).';
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
