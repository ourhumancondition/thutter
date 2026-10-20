import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../common/duty.dart';
import '../../common/format.dart';
import '../../common/widgets.dart';
import '../../data/repositories/providers.dart';
import '../../data/status/employee_status.dart';
import 'timesheet_screen.dart';

const _changes = [
  'Start Day', 'Site In', 'Site Out', 'Start Break', 'Shop', 'Travel', 'End Day',
];

class TimelogsScreen extends ConsumerWidget {
  const TimelogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: Column(
          children: [
            const Material(
              child: TabBar(tabs: [
                Tab(text: 'People'),
                Tab(text: 'Sites'),
                Tab(text: 'Log'),
              ]),
            ),
            const Expanded(
              child: TabBarView(children: [
                _PeopleTab(),
                _SitesTab(),
                _RawLogTab(),
              ]),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: null,
          onPressed: () => confirmTenantThen(
            context,
            ref,
            () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TimelogEditScreen()),
            ),
          ),
          icon: const Icon(Icons.more_time),
          label: const Text('Log time'),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ people ---

class _PeopleTab extends ConsumerWidget {
  const _PeopleTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees = ref.watch(employeesListProvider).value ?? const [];
    final statuses = ref.watch(employeeStatusProvider).value ?? const {};
    final properties = ref.watch(propertiesByIdProvider).value ?? const {};
    final equipment = ref.watch(equipmentByIdProvider).value ?? const {};

    if (employees.isEmpty) {
      return const EmptyState(
          icon: Icons.people_outline, message: 'No employees');
    }

    // Working employees first, then by name.
    final sorted = [...employees]..sort((a, b) {
        final sa = statuses[a.id]?.state.isWorking ?? false;
        final sb = statuses[b.id]?.state.isWorking ?? false;
        if (sa != sb) return sa ? -1 : 1;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });

    return SyncRefresh(
      child: ListView.builder(
        itemCount: sorted.length,
        itemBuilder: (context, i) {
          final e = sorted[i];
          final s = statuses[e.id];
          final state = s?.state ?? DutyState.offDuty;
          final where = <String>[
            if (s?.siteId != null) properties[s!.siteId]?.label ?? 'a site',
            if (s?.vehicleId != null && state != DutyState.onSite)
              equipment[s!.vehicleId]?.label ?? 'a vehicle',
          ].join(' · ');

          return ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  dutyColor(context, state).withValues(alpha: 0.15),
              child: Icon(dutyIcon(state),
                  color: dutyColor(context, state), size: 20),
            ),
            title: Text(e.label),
            subtitle: Text([
              state.label,
              if (where.isNotEmpty) where,
              if (s != null) 'since ${_since(s.since)}',
            ].join(' · ')),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TimesheetScreen(employeeId: e.id),
            )),
          );
        },
      ),
    );
  }
}

String _since(DateTime t) {
  final now = DateTime.now();
  final sameDay = now.year == t.year && now.month == t.month && now.day == t.day;
  return sameDay ? DateFormat('h:mm a').format(t) : DateFormat('MMM d, h:mm a').format(t);
}

// ------------------------------------------------------------------- sites ---

class _SitesTab extends ConsumerWidget {
  const _SitesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(timelogsListProvider).value ?? const [];
    final properties = ref.watch(propertiesByIdProvider).value ?? const {};
    final employees = ref.watch(employeesByIdProvider).value ?? const {};
    final statuses = ref.watch(employeeStatusProvider).value ?? const {};

    // Sites that have any time-log activity, most recent first.
    final siteActivity = <String, DateTime>{};
    for (final t in logs) {
      final sid = t.siteId;
      if (sid == null || t.timestamp == null) continue;
      final cur = siteActivity[sid];
      if (cur == null || t.timestamp!.isAfter(cur)) siteActivity[sid] = t.timestamp!;
    }
    final siteIds = siteActivity.keys.toList()
      ..sort((a, b) => siteActivity[b]!.compareTo(siteActivity[a]!));

    if (siteIds.isEmpty) {
      return const EmptyState(
          icon: Icons.location_off_outlined, message: 'No site activity yet');
    }

    return SyncRefresh(
      child: ListView.builder(
        itemCount: siteIds.length,
        itemBuilder: (context, i) {
          final sid = siteIds[i];
          final onSiteNow = [
            for (final s in statuses.values)
              if (s.state == DutyState.onSite && s.siteId == sid)
                employees[s.employeeId]?.label ?? 'someone',
          ];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: onSiteNow.isEmpty
                  ? null
                  : Colors.green.withValues(alpha: 0.15),
              child: Icon(Icons.location_on_outlined,
                  color: onSiteNow.isEmpty ? null : Colors.green),
            ),
            title: Text(properties[sid]?.label ?? 'Unknown site'),
            subtitle: Text(onSiteNow.isEmpty
                ? 'Last activity ${formatDateTime(siteActivity[sid])}'
                : 'On site now: ${onSiteNow.join(', ')}'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SiteLogScreen(siteId: sid),
            )),
          );
        },
      ),
    );
  }
}

// -------------------------------------------------------------------- raw ---

class _RawLogTab extends ConsumerWidget {
  const _RawLogTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(timelogsListProvider);
    final employees = ref.watch(employeesByIdProvider).value ?? const {};

    return logs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) => list.isEmpty
          ? const EmptyState(
              icon: Icons.schedule_outlined, message: 'No time logs')
          : SyncRefresh(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final t = list[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(dutyIcon(_change(t.change)), size: 20),
                    title: Text('${t.change ?? 'Entry'} — '
                        '${employees[t.employeeId]?.label ?? 'Unknown'}'),
                    subtitle: Text([
                      formatDateTime(t.timestamp),
                      if (t.billable) 'billable',
                    ].whereType<String>().join(' · ')),
                    trailing: t.isLocalOnly
                        ? const Icon(Icons.cloud_upload_outlined, size: 16)
                        : null,
                  );
                },
              ),
            ),
    );
  }

  DutyState _change(String? c) => switch (c) {
        'Site In' => DutyState.onSite,
        'Travel' => DutyState.travelling,
        'Shop' => DutyState.atShop,
        'Start Break' => DutyState.onBreak,
        'End Day' => DutyState.offDuty,
        _ => DutyState.onDuty,
      };
}

// --------------------------------------------------------------- site log ---

class SiteLogScreen extends ConsumerWidget {
  const SiteLogScreen({super.key, required this.siteId});
  final String siteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final property = ref.watch(propertiesByIdProvider).value?[siteId];
    final logs = ref.watch(timelogsBySiteProvider(siteId)).value ?? const [];
    final employees = ref.watch(employeesByIdProvider).value ?? const {};
    final onNow = ref.watch(employeesOnSiteProvider(siteId));

    return Scaffold(
      appBar: AppBar(title: Text(property?.label ?? 'Site activity')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (onNow.isNotEmpty) ...[
            Text('On site now',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final id in onNow)
              ListTile(
                dense: true,
                leading: const Icon(Icons.person_pin_circle, color: Colors.green),
                title: Text(employees[id]?.label ?? id),
              ),
            const Divider(height: 32),
          ],
          Text('Visits', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          if (logs.isEmpty) const Text('No recorded visits'),
          for (final t in logs)
            ListTile(
              dense: true,
              leading: Icon(dutyIcon(_state(t.change)), size: 20),
              title: Text(
                  '${employees[t.employeeId]?.label ?? 'Unknown'} — ${t.change}'),
              subtitle: Text(formatDateTime(t.timestamp) ?? ''),
            ),
        ],
      ),
    );
  }

  DutyState _state(String? c) =>
      c == 'Site In' ? DutyState.onSite : DutyState.onDuty;
}

// ------------------------------------------------------------------- edit ---

class TimelogEditScreen extends ConsumerStatefulWidget {
  const TimelogEditScreen({super.key});

  @override
  ConsumerState<TimelogEditScreen> createState() => _TimelogEditScreenState();
}

class _TimelogEditScreenState extends ConsumerState<TimelogEditScreen> {
  String? _employeeId;
  String _change = 'Site In';
  String? _siteId;
  String? _vehicleId;
  DateTime _when = DateTime.now();
  final _note = TextEditingController();
  bool _billable = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_employeeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose an employee')),
      );
      return;
    }
    await ref.read(timelogRepoProvider).create({
      'employee': _employeeId,
      'change': _change,
      'timestamp': _when.toUtc().toIso8601String(),
      if (_siteId != null) 'site': _siteId,
      if (_vehicleId != null) 'vehicle': _vehicleId,
      'note_in': _note.text.trim(),
      'billable': _billable,
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final employees = ref.watch(employeesListProvider).value ?? const [];
    final properties = ref.watch(propertiesListProvider).value ?? const [];
    final equipment = ref.watch(equipmentListProvider).value ?? const [];
    final needsSite = _change == 'Site In' || _change == 'Site Out';
    final needsVehicle = _change == 'Travel';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log time'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _employeeId,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Employee', border: OutlineInputBorder()),
            items: [
              for (final e in employees)
                DropdownMenuItem(value: e.id, child: Text(e.label)),
            ],
            onChanged: (v) => setState(() => _employeeId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _change,
            decoration: const InputDecoration(
                labelText: 'Change', border: OutlineInputBorder()),
            items: [
              for (final c in _changes)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() => _change = v ?? _change),
          ),
          if (needsSite) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _siteId,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Site', border: OutlineInputBorder()),
              items: [
                for (final p in properties)
                  DropdownMenuItem(value: p.id, child: Text(p.label)),
              ],
              onChanged: (v) => setState(() => _siteId = v),
            ),
          ],
          if (needsVehicle) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _vehicleId,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Vehicle', border: OutlineInputBorder()),
              items: [
                for (final e in equipment)
                  DropdownMenuItem(value: e.id, child: Text(e.label)),
              ],
              onChanged: (v) => setState(() => _vehicleId = v),
            ),
          ],
          const SizedBox(height: 12),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(color: Theme.of(context).dividerColor),
            ),
            title: const Text('When'),
            subtitle: Text(formatDateTime(_when) ?? ''),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _when,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (d == null || !context.mounted) return;
              final tod = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(_when),
              );
              setState(() => _when = DateTime(d.year, d.month, d.day,
                  tod?.hour ?? _when.hour, tod?.minute ?? _when.minute));
            },
          ),
          SwitchListTile(
            title: const Text('Billable'),
            value: _billable,
            onChanged: (v) => setState(() => _billable = v),
          ),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Note', border: OutlineInputBorder()),
          ),
        ],
      ),
    );
  }
}
