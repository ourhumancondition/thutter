import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// One row per PocketBase record, across every collection.
///
/// See docs/ARCHITECTURE.md for why this is a single generic table rather than
/// one Drift table per collection.
class Records extends Table {
  /// PocketBase collection name.
  TextColumn get collection => text()();

  /// PocketBase record id, or `local_<uuid>` for a record created offline that
  /// has not been pushed yet.
  TextColumn get id => text()();

  /// Full record as JSON (every PocketBase field, including id/created/updated).
  TextColumn get data => text()();

  /// Copy of `data.updated` — kept as a column for cheap cursor + sort queries.
  TextColumn get updated => text().nullable()();

  /// 1 = local changes not yet pushed to the server.
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  /// 1 = deleted locally, deletion not yet pushed.
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// Last time this row was reconciled with the server.
  TextColumn get syncedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {collection, id};
}

/// Per-collection pull cursor.
class SyncMeta extends Table {
  TextColumn get collection => text()();
  TextColumn get lastSynced => text().nullable()();

  @override
  Set<Column> get primaryKey => {collection};
}

@DriftDatabase(tables: [Records, SyncMeta])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _open() => driftDatabase(name: 'thutter');

  // ---------------------------------------------------------------- reads ----

  /// Live list of non-deleted records in [collection].
  Stream<List<Record>> watchCollection(String collection) {
    return (select(records)
          ..where((r) => r.collection.equals(collection) & r.deleted.equals(false)))
        .watch();
  }

  Future<List<Record>> getCollection(String collection) {
    return (select(records)
          ..where((r) => r.collection.equals(collection) & r.deleted.equals(false)))
        .get();
  }

  Future<Record?> getRecord(String collection, String id) {
    return (select(records)
          ..where((r) => r.collection.equals(collection) & r.id.equals(id)))
        .getSingleOrNull();
  }

  Stream<Record?> watchRecord(String collection, String id) {
    return (select(records)
          ..where((r) => r.collection.equals(collection) & r.id.equals(id)))
        .watchSingleOrNull();
  }

  Future<List<Record>> dirtyRecords() {
    return (select(records)..where((r) => r.dirty.equals(true))).get();
  }

  // --------------------------------------------------------------- writes ----

  /// Insert/replace a record that came *from the server* (clears dirty/deleted).
  Future<void> upsertFromServer(String collection, Map<String, dynamic> json) {
    return into(records).insertOnConflictUpdate(
      RecordsCompanion.insert(
        collection: collection,
        id: json['id'] as String,
        data: jsonEncode(json),
        updated: Value(json['updated'] as String?),
        dirty: const Value(false),
        deleted: const Value(false),
        syncedAt: Value(DateTime.now().toUtc().toIso8601String()),
      ),
    );
  }

  /// Insert/replace a record from a *local* edit (marks it dirty).
  Future<void> upsertLocal(String collection, Map<String, dynamic> json) {
    return into(records).insertOnConflictUpdate(
      RecordsCompanion.insert(
        collection: collection,
        id: json['id'] as String,
        data: jsonEncode(json),
        updated: Value(json['updated'] as String?),
        dirty: const Value(true),
        deleted: const Value(false),
        syncedAt: const Value.absent(),
      ),
    );
  }

  Future<void> markDeletedLocal(String collection, String id) {
    return (update(records)
          ..where((r) => r.collection.equals(collection) & r.id.equals(id)))
        .write(const RecordsCompanion(dirty: Value(true), deleted: Value(true)));
  }

  Future<void> markSynced(String collection, String id, String? updated) {
    return (update(records)
          ..where((r) => r.collection.equals(collection) & r.id.equals(id)))
        .write(RecordsCompanion(
      dirty: const Value(false),
      updated: Value(updated),
      syncedAt: Value(DateTime.now().toUtc().toIso8601String()),
    ));
  }

  Future<void> hardDelete(String collection, String id) {
    return (delete(records)
          ..where((r) => r.collection.equals(collection) & r.id.equals(id)))
        .go();
  }

  /// Swap a `local_<uuid>` id for the real server id after a create.
  Future<void> replaceId(
      String collection, String localId, Map<String, dynamic> serverJson) async {
    await transaction(() async {
      await hardDelete(collection, localId);
      await upsertFromServer(collection, serverJson);
    });
  }

  Future<String?> lastSynced(String collection) async {
    final row = await (select(syncMeta)
          ..where((s) => s.collection.equals(collection)))
        .getSingleOrNull();
    return row?.lastSynced;
  }

  Future<void> setLastSynced(String collection, String iso) {
    return into(syncMeta).insertOnConflictUpdate(
      SyncMetaCompanion.insert(collection: collection, lastSynced: Value(iso)),
    );
  }

  Future<void> wipe() async {
    await delete(records).go();
    await delete(syncMeta).go();
  }
}
