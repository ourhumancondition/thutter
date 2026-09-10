import 'package:intl/intl.dart';

final _date = DateFormat('MMM d, y');
final _dateTime = DateFormat('MMM d, y · h:mm a');

String? formatDate(DateTime? d) => d == null ? null : _date.format(d.toLocal());
String? formatDateTime(DateTime? d) =>
    d == null ? null : _dateTime.format(d.toLocal());

String? formatPhone(num? n) {
  if (n == null) return null;
  final digits = n.toInt().toString();
  if (digits.length == 10) {
    return '(${digits.substring(0, 3)}) ${digits.substring(3, 6)}-${digits.substring(6)}';
  }
  if (digits.length == 11 && digits.startsWith('1')) {
    return '+1 (${digits.substring(1, 4)}) ${digits.substring(4, 7)}-${digits.substring(7)}';
  }
  return digits;
}

String relativeTime(DateTime? d) {
  if (d == null) return 'never';
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
