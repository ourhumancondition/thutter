import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

import '../../core/config.dart';
import '../db/database.dart';
import '../pb/pb_files.dart';

enum SyncPhase { idle, running, offline, error }

/// Why the last sync failed, so the UI can say something useful.
enum SyncProblem {
  none,

  /// No network, or the server didn't answer (DNS, timeout, server down).
  unreachable,

  /// The server rejected the saved sign-in.
  signedOut,

  /// The server refused a change or a download (validation or permissions).
  rejected,

  /// Anything else.
  unknown,
}

class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.lastRun,
    this.lastSuccess,
    this.lastError,
    this.errorDetail,
    this.problem = SyncProblem.none,
    this.pendingPush = 0,
  });

  final SyncPhase phase;
  final DateTime? lastRun;

  /// When a sync last finished without an error.
  final DateTime? lastSuccess;

  /// Plain-language description of the last failure.
  final String? lastError;

  /// Technical detail of the last failure (status code, server message).
  final String? errorDetail;
  final SyncProblem problem;
  final int pendingPush;

  bool get hasError => phase == SyncPhase.error;

  /// Error fields are cleared unless passed again.
  SyncStatus copyWith({
    SyncPhase? phase,
    DateTime? lastRun,
    DateTime? lastSuccess,
    String? lastError,
    String? errorDetail,
    SyncProblem problem = SyncProblem.none,
    int? pendingPush,
  }) =>
      SyncStatus(
        phase: phase ?? this.phase,
        lastRun: lastRun ?? this.lastRun,
        lastSuccess: lastSuccess ?? this.lastSuccess,
        lastError: lastError,
        errorDetail: errorDetail,
        problem: problem,
        pendingPush: pendingPush ?? this.pendingPush,
      );
}

/// Friendly names for collections whose PocketBase names are odd.
String _label(String collection) => switch (collection) {
      'contactss' => 'contacts',
      'property' => 'properties',
      'workorders' => 'work orders',
      'timelogs' => 'time logs',
      _ => collection,
    };

/// Fields PocketBase manages itself — never sent back in a create/update body.
const _systemFields = {
  'id',
  'created',
  'updated',
  'collectionId',
  'collectionName',
  'expand',
  kPendingFiles,
};

/// Longest any single server call may take. Without a limit, one request that
/// never answers leaves the cycle "running" forever, and since extra calls
/// no-op while a cycle is in flight, sync stops for good.
const _requestTimeout = Duration(seconds: 60);

/// Push-then-pull, last-write-wins sync between the local [AppDatabase] and
/// PocketBase. Generic across every collection in [Config.syncedCollections].
class SyncService {
  SyncService(this._db, this._pb);

  final AppDatabase _db;
  final PocketBase _pb;

  final _statusController = StreamController<SyncStatus>.broadcast();
  SyncStatus _status = const SyncStatus();

  Stream<SyncStatus> get status => _statusController.stream;
  SyncStatus get current => _status;

  bool _running = false;

  void _emit(SyncStatus s) {
    _status = s;
    _statusController.add(s);
  }

  Future<void> refreshPendingCount() async {
    final dirty = await _db.dirtyRecords();
    _emit(_status.copyWith(
      pendingPush: dirty.length,
      lastError: _status.lastError,
      errorDetail: _status.errorDetail,
      problem: _status.problem,
    ));
  }

  /// What the current cycle is doing, for error messages.
  String _step = 'syncing';

  /// Runs one full sync cycle. Safe to call concurrently — extra calls no-op
  /// while a cycle is in flight.
  Future<void> syncAll({bool online = true}) async {
    if (_running) return;
    _running = true;
    // Keep showing the previous error while retrying, so it doesn't flicker
    // away and back.
    _emit(_status.copyWith(
      phase: online ? SyncPhase.running : SyncPhase.offline,
      lastError: _status.lastError,
      errorDetail: _status.errorDetail,
      problem: _status.problem,
    ));
    try {
      if (online && _pb.authStore.isValid) {
        await _pushAll();
        for (final c in Config.syncedCollections) {
          _step = 'downloading ${_label(c)}';
          await pullCollection(c);
          if (c == Config.cMemberships) await _resetIfTenantsChanged();
        }
      }
      await refreshPendingCount();
      _emit(_status.copyWith(
        phase: online ? SyncPhase.idle : SyncPhase.offline,
        lastRun: DateTime.now(),
        lastSuccess: online ? DateTime.now() : null,
      ));
    } catch (e) {
      final (problem, message, detail) = describeError(e, _step);
      _emit(_status.copyWith(
        phase: SyncPhase.error,
        lastError: message,
        errorDetail: detail,
        problem: problem,
        lastRun: DateTime.now(),
      ));
    } finally {
      _running = false;
    }
  }

  /// Turns a sync exception into (kind, plain-language message, detail).
  static (SyncProblem, String, String) describeError(Object e, String step) {
    if (e is TimeoutException || e is SocketException || e is http.ClientException) {
      return (
        SyncProblem.unreachable,
        "Can't reach the Thyme server (while $step). Check your internet "
            'connection. Your changes are saved on this device.',
        e.toString(),
      );
    }
    if (e is ClientException) {
      final code = e.statusCode;
      final serverMsg = e.response['message']?.toString();
      final fields = e.response['data'];
      final detail = [
        'HTTP $code',
        if (serverMsg != null && serverMsg.isNotEmpty) serverMsg,
        if (fields is Map && fields.isNotEmpty) jsonEncode(fields),
        if (code == 0 && e.originalError != null) '${e.originalError}',
      ].join(' — ');
      if (code == 0 || code == 502 || code == 503 || code == 504) {
        return (
          SyncProblem.unreachable,
          "Can't reach the Thyme server (while $step). Check your internet "
              'connection. Your changes are saved on this device.',
          detail,
        );
      }
      if (code == 401) {
        return (
          SyncProblem.signedOut,
          'The server no longer accepts your sign-in. Sign out and sign in '
              'again to keep syncing.',
          detail,
        );
      }
      if (code == 400 || code == 403 || code == 404) {
        return (
          SyncProblem.rejected,
          'The server refused a request while $step'
              '${serverMsg == null ? '' : ': $serverMsg'}',
          detail,
        );
      }
      return (
        SyncProblem.unknown,
        'The Thyme server had a problem while $step (error $code).',
        detail,
      );
    }
    return (SyncProblem.unknown, 'Sync failed while $step.', e.toString());
  }

  // ------------------------------------------------------------------ push ---

  Future<void> _pushAll() async {
    final dirty = await _db.dirtyRecords();
    for (final row in dirty) {
      final json = jsonDecode(row.data) as Map<String, dynamic>;
      final body = {
        for (final e in json.entries)
          if (!_systemFields.contains(e.key)) e.key: e.value,
      };
      _step = 'uploading a change to ${_label(row.collection)}';
      final files = await _multipart(json[kPendingFiles]);
      try {
        if (row.deleted) {
          if (!row.id.startsWith('local_')) {
            await _pb
                .collection(row.collection)
                .delete(row.id)
                .timeout(_requestTimeout);
          }
          await _db.hardDelete(row.collection, row.id);
        } else if (row.id.startsWith('local_')) {
          final created = await _pb
              .collection(row.collection)
              .create(body: body, files: files)
              .timeout(_requestTimeout);
          await _db.replaceId(row.collection, row.id, created.toJson());
        } else {
          final updated = await _pb
              .collection(row.collection)
              .update(row.id, body: body, files: files)
              .timeout(_requestTimeout);
          await _db.markSynced(
              row.collection, row.id, updated.toJson()['updated'] as String?);
        }
      } on ClientException catch (e) {
        // 404 on update/delete → the record is gone server-side; drop locally.
        if (e.statusCode == 404) {
          await _db.hardDelete(row.collection, row.id);
        } else {
          rethrow;
        }
      }
    }
  }

  Future<List<http.MultipartFile>> _multipart(Object? pending) async {
    if (pending is! Map) return const [];
    final out = <http.MultipartFile>[];
    for (final entry in pending.entries) {
      final path = entry.value?.toString();
      if (path == null || path.isEmpty || !File(path).existsSync()) continue;
      out.add(await http.MultipartFile.fromPath(entry.key.toString(), path));
    }
    return out;
  }

  // ------------------------------------------------------------------ pull ---

  /// `sync_meta` key holding the tenant ids the local data was pulled for.
  static const _tenantsKey = '_tenants';

  /// Pull cursors only fetch rows changed since the last sync, so data from a
  /// tenant the user just joined would never arrive. Run right after
  /// memberships are pulled: when the user's set of tenants differs from last
  /// time, drop rows from tenants they left and re-pull everything else.
  Future<void> _resetIfTenantsChanged() async {
    final uid = _pb.authStore.record?.id;
    if (uid == null) return;
    final tenants = <String>{};
    for (final row in await _db.getCollection(Config.cMemberships)) {
      final m = jsonDecode(row.data) as Map<String, dynamic>;
      final status = m['status']?.toString() ?? '';
      if (m['user'] == uid && (status.isEmpty || status == 'active')) {
        tenants.add(m['tenant'].toString());
      }
    }
    final key = (tenants.toList()..sort()).join(',');
    if (await _db.lastSynced(_tenantsKey) == key) return;

    await _db.pruneOutsideTenants(
        {...Config.tenantScoped, Config.cMemberships}, tenants);
    await _db.clearCursors(keep: {Config.cMemberships});
    await _db.setLastSynced(_tenantsKey, key);
    // Tenants were pulled just before memberships; fetch them again in full so
    // a newly joined tenant's (older) record arrives too.
    await pullCollection(Config.cTenants);
  }

  /// PocketBase stores timestamps as `YYYY-MM-DD HH:MM:SS.sssZ` (space, not `T`)
  /// and compares filter values lexically, so the cursor must match that shape.
  static String _pbStamp(DateTime dt) =>
      dt.toUtc().toIso8601String().replaceFirst('T', ' ');

  /// Pull one collection's changes since the stored cursor into the local db.
  Future<void> pullCollection(String collection) async {
    final since = await _db.lastSynced(collection);
    final filter = since == null || since.isEmpty ? '' : 'updated > "$since"';
    final cycleStart = DateTime.now().toUtc();

    final items = await _pb
        .collection(collection)
        .getFullList(filter: filter, sort: 'updated', batch: 200)
        .timeout(_requestTimeout);

    for (final record in items) {
      final json = record.toJson();
      final local = await _db.getRecord(collection, json['id'] as String);
      if (local != null && local.dirty) {
        // Local edit pending. Last-write-wins by `updated`.
        final serverUpdated =
            DateTime.tryParse((json['updated'] as String?) ?? '');
        final localUpdated = DateTime.tryParse(local.updated ?? '');
        final serverWins = serverUpdated != null &&
            (localUpdated == null || serverUpdated.isAfter(localUpdated));
        if (!serverWins) continue;
      }
      await _db.upsertFromServer(collection, json);
    }

    await _db.setLastSynced(collection, _pbStamp(cycleStart));
  }
}
