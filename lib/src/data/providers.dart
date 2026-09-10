import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/database.dart';
import 'pb/pocketbase_client.dart';
import 'sync/sync_service.dart';

/// Local Drift database. Lives for the whole app.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// PocketBase client. Created asynchronously in `main()` (it reads the keychain),
/// then injected here via a [ProviderScope] override.
final pocketBaseClientProvider = Provider<PocketBaseClient>((ref) {
  throw StateError('pocketBaseClientProvider must be overridden in main()');
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    ref.watch(databaseProvider),
    ref.watch(pocketBaseClientProvider).pb,
  );
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final service = ref.watch(syncServiceProvider);
  return service.status;
});

/// Emits `true` when the device appears to have a network connection.
final onlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool has(List<ConnectivityResult> r) =>
      r.any((e) => e != ConnectivityResult.none);
  yield has(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(has);
});
