import 'dart:convert';

import '../db/database.dart';

/// Base wrapper around a PocketBase record's JSON map, with typed accessors
/// that tolerate the loose typing in the Thyme database.
class PbRecord {
  PbRecord(this.data);

  factory PbRecord.fromRow(Record row) =>
      PbRecord(jsonDecode(row.data) as Map<String, dynamic>);

  final Map<String, dynamic> data;

  String get id => data['id'] as String? ?? '';
  bool get isLocalOnly => id.startsWith('local_');

  DateTime? get createdAt => _date(data['created']);
  DateTime? get updatedAt => _date(data['updated']);

  String? str(String key) {
    final v = data[key];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  bool flag(String key) {
    final v = data[key];
    return v == true || v == 1 || v == '1' || v == 'true';
  }

  num? num_(String key) {
    final v = data[key];
    if (v == null || v == '') return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  DateTime? date(String key) => _date(data[key]);

  /// A relation field: always returned as a list of ids (PocketBase stores
  /// single relations as a string and multi relations as a list).
  List<String> relList(String key) {
    final v = data[key];
    if (v == null || v == '') return const [];
    if (v is List) {
      return v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return [v.toString()];
  }

  String? rel(String key) {
    final list = relList(key);
    return list.isEmpty ? null : list.first;
  }

  static DateTime? _date(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  Map<String, dynamic> toJson() => data;
}
