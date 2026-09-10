import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../repositories/providers.dart';

/// Where an employee is right now, derived from their most recent time-clock
/// event.
enum DutyState {
  offDuty,
  onDuty, // clocked in, location not specific
  atShop,
  travelling,
  onSite,
  onBreak,
}

extension DutyStateLabel on DutyState {
  String get label => switch (this) {
        DutyState.offDuty => 'Off duty',
        DutyState.onDuty => 'On duty',
        DutyState.atShop => 'At the shop',
        DutyState.travelling => 'Travelling',
        DutyState.onSite => 'On site',
        DutyState.onBreak => 'On break',
      };

  bool get isWorking => this != DutyState.offDuty;
}

class EmployeeStatus {
  const EmployeeStatus({
    required this.employeeId,
    required this.state,
    required this.since,
    this.siteId,
    this.vehicleId,
    this.jobId,
    this.lastChange,
    this.note,
  });

  final String employeeId;
  final DutyState state;
  final DateTime since;
  final String? siteId;
  final String? vehicleId;
  final String? jobId;
  final String? lastChange;
  final String? note;
}

DutyState dutyStateFor(String? change) => switch (change) {
      'Site In' => DutyState.onSite,
      'Site Out' => DutyState.onDuty,
      'Start Break' => DutyState.onBreak,
      'Shop' => DutyState.atShop,
      'Travel' => DutyState.travelling,
      'Start Day' => DutyState.onDuty,
      'End Day' => DutyState.offDuty,
      _ => DutyState.onDuty,
    };

/// One derived status per employee that has any time log, newest event wins.
final employeeStatusProvider =
    StreamProvider<Map<String, EmployeeStatus>>((ref) {
  return ref.watch(timelogRepoProvider).watchAll().map((logs) {
    final byEmployee = <String, List<Timelog>>{};
    for (final t in logs) {
      final e = t.employeeId;
      if (e == null || t.timestamp == null) continue;
      (byEmployee[e] ??= []).add(t);
    }

    final out = <String, EmployeeStatus>{};
    byEmployee.forEach((employeeId, events) {
      events.sort((a, b) => a.timestamp!.compareTo(b.timestamp!));
      final last = events.last;
      final state = dutyStateFor(last.change);

      // Carry forward the site / vehicle / job from the most recent event that
      // named one, but only within the current shift (since the last Start Day).
      String? siteId, vehicleId, jobId;
      for (final e in events.reversed) {
        siteId ??= e.siteId;
        vehicleId ??= e.vehicleId;
        jobId ??= e.jobId;
        if (e.change == 'Start Day') break;
      }
      // If they've left the site, don't claim they're still on one.
      if (state != DutyState.onSite) siteId = null;

      out[employeeId] = EmployeeStatus(
        employeeId: employeeId,
        state: state,
        since: last.timestamp!,
        siteId: siteId,
        vehicleId: state == DutyState.offDuty ? null : vehicleId,
        jobId: jobId,
        lastChange: last.change,
        note: last.noteIn ?? last.noteOut,
      );
    });
    return out;
  });
});

/// Employees currently on a given property.
final employeesOnSiteProvider =
    Provider.family<List<String>, String>((ref, siteId) {
  final statuses = ref.watch(employeeStatusProvider).value ?? const {};
  return [
    for (final s in statuses.values)
      if (s.state == DutyState.onSite && s.siteId == siteId) s.employeeId,
  ];
});

/// Employees currently associated with a given vehicle / piece of equipment.
final employeesInVehicleProvider =
    Provider.family<List<String>, String>((ref, equipmentId) {
  final statuses = ref.watch(employeeStatusProvider).value ?? const {};
  return [
    for (final s in statuses.values)
      if (s.state.isWorking && s.vehicleId == equipmentId) s.employeeId,
  ];
});

// --------------------------------------------------------------- timesheet ---

/// A stretch of time between two consecutive clock events for one employee.
class ShiftSegment {
  ShiftSegment({
    required this.start,
    required this.end,
    required this.change,
    this.siteId,
    this.vehicleId,
    this.jobId,
    this.note,
  });

  final DateTime start;
  final DateTime? end; // null = still ongoing
  final String? change;
  final String? siteId;
  final String? vehicleId;
  final String? jobId;
  final String? note;

  Duration get duration => (end ?? DateTime.now()).difference(start);
  bool get ongoing => end == null;

  DutyState get kind => dutyStateFor(change);
  bool get counts =>
      kind != DutyState.offDuty && kind != DutyState.onBreak;
}

/// Build ordered segments from an employee's events (any range).
List<ShiftSegment> segmentsFrom(List<Timelog> events) {
  final sorted = [...events]
      .where((e) => e.timestamp != null)
      .toList()
    ..sort((a, b) => a.timestamp!.compareTo(b.timestamp!));

  final out = <ShiftSegment>[];
  for (var i = 0; i < sorted.length; i++) {
    final e = sorted[i];
    if (e.change == 'End Day') continue; // terminates, no segment of its own
    final next = i + 1 < sorted.length ? sorted[i + 1] : null;
    out.add(ShiftSegment(
      start: e.timestamp!,
      end: next?.timestamp,
      change: e.change,
      siteId: e.siteId,
      vehicleId: e.vehicleId,
      jobId: e.jobId,
      note: e.noteIn ?? e.noteOut,
    ));
  }
  return out;
}

final timelogsByEmployeeProvider =
    StreamProvider.family<List<Timelog>, String>((ref, employeeId) {
  return ref.watch(timelogRepoProvider).watchAll().map((logs) {
    final list = logs.where((t) => t.employeeId == employeeId).toList()
      ..sort((a, b) {
        final at = a.timestamp, bt = b.timestamp;
        if (at == null || bt == null) return 0;
        return bt.compareTo(at);
      });
    return list;
  });
});

final timelogsBySiteProvider =
    StreamProvider.family<List<Timelog>, String>((ref, siteId) {
  return ref.watch(timelogRepoProvider).watchAll().map((logs) {
    final list = logs.where((t) => t.siteId == siteId).toList()
      ..sort((a, b) {
        final at = a.timestamp, bt = b.timestamp;
        if (at == null || bt == null) return 0;
        return bt.compareTo(at);
      });
    return list;
  });
});
