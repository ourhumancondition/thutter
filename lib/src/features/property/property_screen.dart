import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/duty.dart';
import '../../common/format.dart';
import '../../common/record_picker.dart';
import '../../common/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/providers.dart';
import '../../data/status/employee_status.dart';
import '../tenant/tenant_switcher.dart';

const _propertyTypes = [
  'Residence', 'Condo', 'Commercial', 'Industrial', 'Public',
];

class PropertyScreen extends ConsumerWidget {
  const PropertyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final properties = ref.watch(propertiesListProvider);
    final contacts = ref.watch(contactsByIdProvider).value ?? const {};

    return Scaffold(
      body: properties.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.home_work_outlined, message: 'No properties')
            : SyncRefresh(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final p = list[i];
                    final owner = p.contactIds.isEmpty
                        ? null
                        : contacts[p.contactIds.first]?.label;
                    final onSite = ref.watch(employeesOnSiteProvider(p.id));
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: onSite.isEmpty
                            ? null
                            : Colors.green.withValues(alpha: 0.15),
                        child: Icon(Icons.home_work,
                            color: onSite.isEmpty ? null : Colors.green),
                      ),
                      title: Text(p.label),
                      subtitle: Text([
                        if (onSite.isNotEmpty) '${onSite.length} on site',
                        p.type,
                        owner,
                        p.addressString,
                      ].whereType<String>().join(' · ')),
                      trailing: p.isLocalOnly
                          ? const Icon(Icons.cloud_upload_outlined, size: 16)
                          : null,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PropertyDetailScreen(id: p.id),
                      )),
                    );
                  },
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => confirmTenantThen(
          context,
          ref,
          () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PropertyEditScreen()),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New property'),
      ),
    );
  }
}

class PropertyDetailScreen extends ConsumerWidget {
  const PropertyDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(propertiesByIdProvider).value?[id];
    final contacts = ref.watch(contactsByIdProvider).value ?? const {};
    final employees = ref.watch(employeesByIdProvider).value ?? const {};
    final onNow = ref.watch(employeesOnSiteProvider(id));
    final logs = ref.watch(timelogsBySiteProvider(id)).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(p?.label ?? 'Property'),
        actions: [
          if (p != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PropertyEditScreen(existing: p),
              )),
            ),
        ],
      ),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (onNow.isNotEmpty) ...[
                  Card(
                    color: Colors.green.withValues(alpha: 0.12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('On site now',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          for (final e in onNow)
                            Text('• ${employees[e]?.label ?? e}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                DetailRow('Type', p.type, icon: Icons.category_outlined),
                DetailRow(
                    'Contact',
                    p.contactIds
                        .map((c) => contacts[c]?.label)
                        .whereType<String>()
                        .join(', '),
                    icon: Icons.person_outline),
                DetailRow('Address', p.addressString,
                    icon: Icons.location_on_outlined),
                if ((p.notes ?? '').isNotEmpty) ...[
                  const Divider(height: 32),
                  Text('Notes', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(plainText(p.notes)),
                ],
                const Divider(height: 32),
                Text('Site activity',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                if (logs.isEmpty) const Text('No time logs for this site'),
                for (final t in logs.take(50))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
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

class PropertyEditScreen extends ConsumerStatefulWidget {
  const PropertyEditScreen({super.key, this.existing});
  final Property? existing;

  @override
  ConsumerState<PropertyEditScreen> createState() => _PropertyEditScreenState();
}

class _PropertyEditScreenState extends ConsumerState<PropertyEditScreen> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _number = TextEditingController(text: widget.existing?.number);
  late final _street = TextEditingController(text: widget.existing?.street);
  late final _unit = TextEditingController(text: widget.existing?.unit);
  late final _city = TextEditingController(text: widget.existing?.city);
  late final _province = TextEditingController(text: widget.existing?.province);
  late final _postal = TextEditingController(text: widget.existing?.postal);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late String? _type = widget.existing?.type;
  late String? _contactId =
      widget.existing?.contactIds.isNotEmpty == true
          ? widget.existing!.contactIds.first
          : null;

  @override
  void dispose() {
    for (final c in [
      _name, _number, _street, _unit, _city, _province, _postal, _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final addr = [
      [_number.text, _street.text].where((s) => s.trim().isNotEmpty).join(' '),
      _city.text,
      _province.text,
      _postal.text,
    ].where((s) => s.trim().isNotEmpty).join(', ');

    final fields = <String, dynamic>{
      'name': _name.text.trim(),
      'number': _number.text.trim(),
      'street': _street.text.trim(),
      'unit': _unit.text.trim(),
      'city': _city.text.trim(),
      'province': _province.text.trim(),
      'postal': _postal.text.trim(),
      'notes': _notes.text.trim(),
      'type': _type,
      'address_string': addr,
      if (_contactId != null) 'contact': [_contactId],
    };
    final repo = ref.read(propertyRepoProvider);
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
        title: Text(widget.existing == null ? 'New property' : 'Edit property'),
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await ref
                    .read(propertyRepoProvider)
                    .delete(widget.existing!.id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tf(_name, 'Name / nickname'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(
                labelText: 'Type', border: OutlineInputBorder()),
            items: [
              for (final t in _propertyTypes)
                DropdownMenuItem(value: t, child: Text(t)),
            ],
            onChanged: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: 12),
          ContactPickerField(
            label: 'Primary contact',
            value: _contactId,
            onChanged: (v) => setState(() => _contactId = v),
          ),
          const SizedBox(height: 12),
          Row(children: [
            SizedBox(width: 90, child: _tf(_number, 'No.')),
            const SizedBox(width: 12),
            Expanded(child: _tf(_street, 'Street')),
          ]),
          _tf(_unit, 'Unit'),
          Row(children: [
            Expanded(child: _tf(_city, 'City')),
            const SizedBox(width: 12),
            Expanded(child: _tf(_province, 'Province')),
            const SizedBox(width: 12),
            Expanded(child: _tf(_postal, 'Postal')),
          ]),
          _tf(_notes, 'Notes', maxLines: 4),
        ],
      ),
    );
  }

  Widget _tf(TextEditingController c, String label, {int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
          controller: c,
          maxLines: maxLines,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
        ),
      );
}
