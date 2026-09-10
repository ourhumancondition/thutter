import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

import '../../core/config.dart';
import '../db/database.dart';
import '../pb/pb_files.dart';

enum SyncPhase { idle, running, offline, error }

class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.lastRun,
    this.lastError,
    this.pendingPush = 0,
  });

  final SyncPhase phase;
  final DateTime? lastRun;
  final String? lastError;
  final int pendingPush;

  SyncStatus copyWith({
    SyncPhase? phase,
    DateTime? lastRun,
    String? lastError,
    int? pendingPush,
  }) =>
      SyncStatus(
        phase: phase ?? this.phase,
        lastRun: lastRun ?? this.lastRun,
        lastError: lastError,
        pendingPush: pendingPush ?? this.pendingPush,
      );
}

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
    _emit(_status.copyWith(pendingPush: dirty.length));
  }

  /// Runs one full sync cycle. Safe to call concurrently — extra calls no-op
  /// while a cycle is in flight.
  Future<void> syncAll({bool online = true}) async {
    if (_running) return;
    _running = true;
    _emit(_status.copyWith(
      phase: online ? SyncPhase.running : SyncPhase.offline,
      lastError: null,
    ));
    try {
      if (online && _pb.authStore.isValid) {
        await _pushAll();
        for (final c in Config.syncedCollections) {
          await pullCollection(c);
        }
      }
      await refreshPendingCount();
      _emit(_status.copyWith(
        phase: online ? SyncPhase.idle : SyncPhase.offline,
        lastRun: DateTime.now(),
        lastError: null,
      ));
    } catch (e) {
      _emit(_status.copyWith(
        phase: SyncPhase.error,
        lastError: e.toString(),
        lastRun: DateTime.now(),
      ));
    } finally {
      _running = false;
    }
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
      final files = await _multipart(json[kPendingFiles]);
      try {
        if (row.deleted) {
          if (!row.id.startsWith('local_')) {
            await _pb.collection(row.collection).delete(row.id);
          }
          await _db.hardDelete(row.collection, row.id);
        } else if (row.id.startsWith('local_')) {
          final created = await _pb
              .collection(row.collection)
              .create(body: body, files: files);
          await _db.replaceId(row.collection, row.id, created.toJson());
        } else {
          final updated = await _pb
              .collection(row.collection)
              .update(row.id, body: body, files: files);
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

  /// PocketBase stores timestamps as `YYYY-MM-DD HH:MM:SS.sssZ` (space, not `T`)
  /// and compares filter values lexically, so the cursor must match that shape.
  static String _pbStamp(DateTime dt) =>
      dt.toUtc().toIso8601String().replaceFirst('T', ' ');

  /// Pull one collection's changes since the stored cursor into the local db.
  Future<void> pullCollection(String collection) async {
    final since = await _db.lastSynced(collection);
    final filter = since == null || since.isEmpty ? '' : 'updated > "$since"';
    final cycleStart = DateTime.now().toUtc();

    final items = await _pb.collection(collection).getFullList(
          filter: filter,
          sort: 'updated',
          batch: 200,
        );

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
