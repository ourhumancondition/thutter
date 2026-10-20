import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../models/models.dart';
import '../pb/pb_files.dart';

/// Generic local-first CRUD over one PocketBase collection, backed by the
/// generic `records` table. Screens use one of the typed instances created in
/// `providers.dart`.
class CollectionRepository<T extends PbRecord> {
  CollectionRepository({
    required this.collection,
    required this.fromJson,
    required AppDatabase db,
    this.activeTenantId,
  }) : _db = db;

  final String collection;
  final T Function(Map<String, dynamic>) fromJson;
  final AppDatabase _db;

  /// Set for tenant-scoped collections: returns the tenant new records belong
  /// to. PocketBase rejects a create without one, so a missing tenant fails
  /// here rather than silently on the next sync.
  final String? Function()? activeTenantId;

  static const _uuid = Uuid();

  T _map(Record row) => fromJson(jsonDecode(row.data) as Map<String, dynamic>);

  Stream<List<T>> watchAll() =>
      _db.watchCollection(collection).map((rows) => rows.map(_map).toList());

  Future<List<T>> getAll() async =>
      (await _db.getCollection(collection)).map(_map).toList();

  Stream<T?> watch(String id) =>
      _db.watchRecord(collection, id).map((r) => r == null ? null : _map(r));

  Future<T?> get(String id) async {
    final row = await _db.getRecord(collection, id);
    return row == null ? null : _map(row);
  }

  /// Create a record locally. It gets a temporary `local_<uuid>` id and is
  /// pushed on the next sync, which swaps in the real server id.
  Future<String> create(Map<String, dynamic> fields) async {
    final id = 'local_${_uuid.v4()}';
    final now = DateTime.now().toUtc().toIso8601String();
    String? tenant;
    if (activeTenantId != null && fields['tenant'] == null) {
      tenant = activeTenantId!();
      if (tenant == null) {
        throw StateError('Choose a business before adding to $collection.');
      }
    }
    final json = <String, dynamic>{
      ...fields,
      if (tenant != null) 'tenant': tenant,
      'id': id,
      'created': now,
      'updated': now,
      'collectionName': collection,
    };
    await _db.upsertLocal(collection, json);
    return id;
  }

  /// Merge [fields] into an existing record and mark it dirty.
  Future<void> update(String id, Map<String, dynamic> fields) async {
    final row = await _db.getRecord(collection, id);
    if (row == null) return;
    final json = jsonDecode(row.data) as Map<String, dynamic>;
    json.addAll(fields);
    json['updated'] = DateTime.now().toUtc().toIso8601String();
    await _db.upsertLocal(collection, json);
  }

  Future<void> delete(String id) => _db.markDeletedLocal(collection, id);

  /// Queue a local file to be uploaded into [field] on the next sync. The file
  /// shows immediately in the UI (via `PbImage`'s pending path) and is sent as
  /// multipart form data when the record is pushed.
  Future<void> attachFile(String id, String field, String path) async {
    final row = await _db.getRecord(collection, id);
    if (row == null) return;
    final json = jsonDecode(row.data) as Map<String, dynamic>;
    final pending = <String, dynamic>{
      ...?(json[kPendingFiles] as Map?)?.cast<String, dynamic>(),
      field: path,
    };
    json[kPendingFiles] = pending;
    json['updated'] = DateTime.now().toUtc().toIso8601String();
    await _db.upsertLocal(collection, json);
  }
}

