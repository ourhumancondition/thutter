import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/duty.dart';
import '../../common/format.dart';
import '../../common/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/providers.dart';
import '../../data/status/employee_status.dart';
import '../timelogs/timesheet_screen.dart';

class EmployeesScreen extends ConsumerWidget {
  const EmployeesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees = ref.watch(employeesListProvider);
    final statuses = ref.watch(employeeStatusProvider).value ?? const {};
    final properties = ref.watch(propertiesByIdProvider).value ?? const {};

    return Scaffold(
      body: employees.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.badge_outlined, message: 'No employees')
            : SyncRefresh(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final e = list[i];
                    final s = statuses[e.id];
                    final working = s?.state.isWorking ?? false;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: working
                            ? dutyColor(context, s!.state).withValues(alpha: 0.15)
                            : e.isActive
                                ? null
                                : Colors.grey.shade400,
                        child: Icon(
                          working ? dutyIcon(s!.state) : Icons.person,
                          color: working ? dutyColor(context, s!.state) : null,
                          size: 20,
                        ),
                      ),
                      title: Text(e.label),
                      subtitle: Text([
                        if (s != null)
                          s.state == DutyState.onSite && s.siteId != null
                              ? '${s.state.label} · ${properties[s.siteId]?.label ?? 'site'}'
                              : s.state.label,
                        e.jobType,
                        if (e.isSubcontractor) 'Subcontractor',
                        if (!e.isActive) 'Inactive',
                      ].whereType<String>().join(' · ')),
                      trailing: e.isLocalOnly
                          ? const Icon(Icons.cloud_upload_outlined, size: 16)
                          : IconButton(
                              icon: const Icon(Icons.schedule_outlined),
                              tooltip: 'Timesheet',
                              onPressed: () =>
                                  Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) =>
                                    TimesheetScreen(employeeId: e.id),
                              )),
                            ),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => EmployeeDetailScreen(id: e.id),
                      )),
                    );
                  },
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EmployeeEditScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New employee'),
      ),
    );
  }
}

class EmployeeDetailScreen extends ConsumerWidget {
  const EmployeeDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<Employee?>(
      stream: ref.watch(employeeRepoProvider).watch(id),
      builder: (context, snap) {
        final e = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(e?.label ?? 'Employee'),
            actions: [
              if (e != null)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => EmployeeEditScreen(existing: e),
                  )),
                ),
            ],
          ),
          body: e == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    DetailRow('Name', e.label, icon: Icons.person_outline),
                    DetailRow('Email', e.email, icon: Icons.email_outlined),
                    DetailRow('Job type', e.jobType, icon: Icons.work_outline),
                    DetailRow('Active', e.isActive ? 'Yes' : 'No'),
                    DetailRow('Subcontractor', e.isSubcontractor ? 'Yes' : null),
                    DetailRow('Rate', e.rate?.toString(),
                        icon: Icons.attach_money_outlined),
                    DetailRow('Hired', formatDate(e.hiredDate),
                        icon: Icons.event_outlined),
                    DetailRow('Birthday', formatDate(e.birthday)),
                    const Divider(height: 32),
                    Text('Driver', style: Theme.of(context).textTheme.titleSmall),
                    DetailRow('Can drive', e.canDrive ? 'Yes' : 'No'),
                    DetailRow('Licence', e.licenseType == null
                        ? null
                        : '${e.licenseType} · ${e.licenseNo ?? ''}'.trim()),
                    DetailRow('Licence expiry', formatDate(e.licenseExpiry)),
                    const Divider(height: 32),
                    Text('Certifications',
                        style: Theme.of(context).textTheme.titleSmall),
                    DetailRow('Health & safety', formatDate(e.healthSafety)),
                    DetailRow('First aid', formatDate(e.firstAid)),
                    const Divider(height: 32),
                    Text(
                      e.isLocalOnly
                          ? 'Not yet synced to the server'
                          : 'Updated ${formatDateTime(e.updatedAt) ?? '—'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class EmployeeEditScreen extends ConsumerStatefulWidget {
  const EmployeeEditScreen({super.key, this.existing});
  final Employee? existing;

  @override
  ConsumerState<EmployeeEditScreen> createState() => _EmployeeEditScreenState();
}

class _EmployeeEditScreenState extends ConsumerState<EmployeeEditScreen> {
  late final _first = TextEditingController(text: widget.existing?.firstname);
  late final _last = TextEditingController(text: widget.existing?.lastname);
  late final _email = TextEditingController(text: widget.existing?.email);
  late final _jobType = TextEditingController(text: widget.existing?.jobType);
  late final _rate =
      TextEditingController(text: widget.existing?.rate?.toString());
  late bool _active = widget.existing?.isActive ?? true;
  late bool _sub = widget.existing?.isSubcontractor ?? false;
  late bool _drive = widget.existing?.canDrive ?? false;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    _jobType.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final first = _first.text.trim();
    final last = _last.text.trim();
    final fields = <String, dynamic>{
      'firstname': first,
      'lastname': last,
      'fullname': [first, last].where((s) => s.isNotEmpty).join(' '),
      'email': _email.text.trim(),
      'jobType': _jobType.text.trim(),
      'rate': num.tryParse(_rate.text.trim()),
      'isActive': _active,
      'isSubcontractor': _sub,
      'drive': _drive,
    };
    final repo = ref.read(employeeRepoProvider);
    if (widget.existing == null) {
      await repo.create(fields);
    } else {
      await repo.update(widget.existing!.id, fields);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New employee' : 'Edit employee'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(child: _tf(_first, 'First name')),
            const SizedBox(width: 12),
            Expanded(child: _tf(_last, 'Last name')),
          ]),
          _tf(_email, 'Email', type: TextInputType.emailAddress),
          _tf(_jobType, 'Job type'),
          _tf(_rate, 'Rate', type: TextInputType.number),
          SwitchListTile(
            title: const Text('Active'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          SwitchListTile(
            title: const Text('Subcontractor'),
            value: _sub,
            onChanged: (v) => setState(() => _sub = v),
          ),
          SwitchListTile(
            title: const Text('Can drive'),
            value: _drive,
            onChanged: (v) => setState(() => _drive = v),
          ),
        ],
      ),
    );
  }

  Widget _tf(TextEditingController c, String label, {TextInputType? type}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
          controller: c,
          keyboardType: type,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
        ),
      );
}
