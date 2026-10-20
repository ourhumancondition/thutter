import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../auth/auth_controller.dart';
import '../net/connection_check.dart';
import '../providers.dart';
import 'sync_service.dart';

/// Decides *when* to sync: on sign-in, when connectivity returns, on a timer
/// while foregrounded, and on app resume. Keep this alive for the whole app
/// (the root widget watches it).
final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final coordinator = SyncCoordinator(ref);
  ref.onDispose(coordinator.dispose);
  coordinator.start();
  return coordinator;
});

class SyncCoordinator with WidgetsBindingObserver {
  SyncCoordinator(this._ref);

  final Ref _ref;
  Timer? _timer;

  /// Re-checks the connection while it's down, so the "no internet" signal
  /// clears (and sync resumes) on its own once the connection comes back.
  Timer? _recheck;
  static const _recheckEvery = Duration(seconds: 30);
  bool _wasOnline = false;

  void start() {
    WidgetsBinding.instance.addObserver(this);

    _ref.listen(authControllerProvider, (prev, next) {
      if (prev?.isAuthenticated != true && next.isAuthenticated) {
        _sync();
      }
    });

    _ref.listen(onlineProvider, (prev, next) {
      final online = next.value ?? false;
      if (online && !_wasOnline) _sync();
      // Wi-Fi switched off/on — find out what that means for real.
      if (prev != null && online != _wasOnline) {
        _ref.read(connectionProvider.notifier).check();
      }
      _wasOnline = online;
    }, fireImmediately: true);

    _timer = Timer.periodic(Config.syncInterval, (_) => _sync());
  }

  Future<void> _sync({int attempt = 0}) async {
    final auth = _ref.read(authControllerProvider);
    if (!auth.isAuthenticated) return;
    final online = _ref.read(onlineProvider).value ?? false;
    final service = _ref.read(syncServiceProvider);
    await service.syncAll(online: online);

    final connection = _ref.read(connectionProvider.notifier);
    if (service.current.phase == SyncPhase.idle) {
      connection.markOnline();
    } else if (!online ||
        service.current.problem == SyncProblem.unreachable) {
      // Couldn't reach the server — find out whether it's our internet or
      // their server, so the UI can say which.
      final result = await connection.check();
      if (!result.isOnline) {
        _startRecheck();
        return; // retrying now would only fail the same way
      }
    }

    // A transient error while online — back off and retry a couple of times
    // rather than waiting for the next scheduled tick.
    if (online &&
        attempt < 3 &&
        service.current.phase == SyncPhase.error) {
      await Future<void>.delayed(Duration(seconds: 10 * (attempt + 1)));
      await _sync(attempt: attempt + 1);
    }
  }

  void _startRecheck() {
    _recheck ??= Timer.periodic(_recheckEvery, (_) async {
      final result = await _ref.read(connectionProvider.notifier).check();
      if (result.isOnline) {
        _recheck?.cancel();
        _recheck = null;
        await _sync();
      }
    });
  }

  /// Manual trigger for pull-to-refresh.
  Future<void> syncNow() => _sync();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  void dispose() {
    _timer?.cancel();
    _recheck?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
