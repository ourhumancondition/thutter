import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../common/duty.dart';
import '../../common/format.dart';
import '../../data/models/models.dart';
import '../../data/repositories/providers.dart';
import '../../data/status/employee_status.dart';

final _dayHeader = DateFormat('EEEE, MMM d');
final _time = DateFormat('h:mm a');

String _dur(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

class TimesheetScreen extends ConsumerWidget {
  const TimesheetScreen({super.key, required this.employeeId});
  final String employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee = ref.watch(employeesByIdProvider).value?[employeeId];
    final events =
        ref.watch(timelogsByEmployeeProvider(employeeId)).value ?? const [];
    final status = ref.watch(employeeStatusProvider).value?[employeeId];
    final properties = ref.watch(propertiesByIdProvider).value ?? const {};
    final equipment = ref.watch(equipmentByIdProvider).value ?? const {};

    final byDay = groupBy<Timelog, DateTime>(
      events.where((e) => e.timestamp != null),
      (e) => DateUtils.dateOnly(e.timestamp!.toLocal()),
    );
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(title: Text(employee?.label ?? 'Timesheet')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (status != null)
            Card(
              child: ListTile(
                leading: Icon(dutyIcon(status.state),
                    color: dutyColor(context, status.state)),
                title: Text(status.state.label),
                subtitle: Text([
                  if (status.siteId != null)
                    properties[status.siteId]?.label ?? 'a site',
                  if (status.vehicleId != null &&
                      status.state != DutyState.onSite)
                    equipment[status.vehicleId]?.label ?? 'a vehicle',
                  'since ${formatDateTime(status.since)}',
                ].join(' · ')),
              ),
            ),
          const SizedBox(height: 8),
          if (days.isEmpty) const Text('No time entries'),
          for (final day in days)
            _DaySection(
              day: day,
              events: byDay[day]!,
              properties: properties,
              equipment: equipment,
            ),
        ],
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.day,
    required this.events,
    required this.properties,
    required this.equipment,
  });

  final DateTime day;
  final List<Timelog> events;
  final Map<String, Property> properties;
  final Map<String, Equipment> equipment;

  @override
  Widget build(BuildContext context) {
    final segments = segmentsFrom(events);
    final worked = segments
        .where((s) => s.counts)
        .fold(Duration.zero, (a, s) => a + s.duration);
    final onSite = segments
        .where((s) => s.kind == DutyState.onSite)
        .fold(Duration.zero, (a, s) => a + s.duration);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_dayHeader.format(day),
                  style: Theme.of(context).textTheme.titleSmall),
              Text('${_dur(worked)} worked · ${_dur(onSite)} on site',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        for (final seg in segments)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(dutyIcon(seg.kind), size: 20),
            title: Text([
              seg.change ?? 'Entry',
              if (seg.siteId != null) '· ${properties[seg.siteId]?.label ?? 'site'}',
              if (seg.vehicleId != null)
                '· ${equipment[seg.vehicleId]?.label ?? 'vehicle'}',
            ].join(' ')),
            subtitle: Text(
              '${_time.format(seg.start.toLocal())}'
              '${seg.end != null ? ' – ${_time.format(seg.end!.toLocal())}' : ' – now'}',
            ),
            trailing: seg.counts || seg.kind == DutyState.onBreak
                ? Text(_dur(seg.duration))
                : null,
          ),
      ],
    );
  }
}
