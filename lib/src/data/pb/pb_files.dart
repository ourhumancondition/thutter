import '../../core/config.dart';

/// Builds a public read URL for a PocketBase file field.
///
/// Returns null when there is nothing to show yet — an empty filename, or a
/// record that only exists locally (`local_<uuid>`), which has no server file.
String? pbFileUrl(
  String collection,
  String recordId,
  String? filename, {
  int? thumb,
}) {
  if (filename == null || filename.isEmpty) return null;
  if (recordId.startsWith('local_')) return null;
  final base = Config.pocketBaseUrl;
  final q = thumb == null ? '' : '?thumb=${thumb}x$thumb';
  return '$base/api/files/$collection/$recordId/$filename$q';
}

/// Key under which a not-yet-uploaded local file path is stashed in a record's
/// JSON: `{ "_pendingFiles": { "<field>": "/abs/path/to/file" } }`.
const kPendingFiles = '_pendingFiles';
