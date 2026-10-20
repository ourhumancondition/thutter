import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/format.dart';
import '../../common/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/providers.dart';

class WorkOrdersScreen extends ConsumerWidget {
  const WorkOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(workOrdersListProvider);
    final contacts = ref.watch(contactsByIdProvider).value ?? const {};
    final properties = ref.watch(propertiesByIdProvider).value ?? const {};

    return Scaffold(
      body: orders.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.engineering_outlined, message: 'No work orders')
            : SyncRefresh(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final w = list[i];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.engineering)),
                      title: Text(w.label),
                      subtitle: Text([
                        contacts[w.contactId]?.label,
                        properties[w.propertyId]?.label,
                        if (w.startDate != null) formatDate(w.startDate),
                      ].whereType<String>().join(' · ')),
                      trailing: w.isLocalOnly
                          ? const Icon(Icons.cloud_upload_outlined, size: 16)
                          : null,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => WorkOrderEditScreen(existing: w),
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
            MaterialPageRoute(builder: (_) => const WorkOrderEditScreen()),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New work order'),
      ),
    );
  }
}

class WorkOrderEditScreen extends ConsumerStatefulWidget {
  const WorkOrderEditScreen({super.key, this.existing});
  final WorkOrder? existing;

  @override
  ConsumerState<WorkOrderEditScreen> createState() =>
      _WorkOrderEditScreenState();
}

class _WorkOrderEditScreenState extends ConsumerState<WorkOrderEditScreen> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _description =
      TextEditingController(text: widget.existing?.description);
  late final _scope = TextEditingController(text: widget.existing?.scope);
  late String? _contactId = widget.existing?.contactId;
  late String? _propertyId = widget.existing?.propertyId;
  late DateTime? _start = widget.existing?.startDate;
  late DateTime? _end = widget.existing?.endDate;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _scope.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final fields = <String, dynamic>{
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'scope': _scope.text.trim(),
      if (_contactId != null) 'contact': _contactId,
      if (_propertyId != null) 'property': _propertyId,
      'start_date': _start?.toUtc().toIso8601String(),
      'end_date': _end?.toUtc().toIso8601String(),
    };
    final repo = ref.read(workOrderRepoProvider);
    if (widget.existing == null) {
      await repo.create(fields);
    } else {
      await repo.update(widget.existing!.id, fields);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsListProvider).value ?? const [];
    final properties = ref.watch(propertiesListProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.existing == null ? 'New work order' : 'Edit work order'),
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await ref
                    .read(workOrderRepoProvider)
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
          _tf(_name, 'Name'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _contactId,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Contact', border: OutlineInputBorder()),
            items: [
              for (final c in contacts)
                DropdownMenuItem(value: c.id, child: Text(c.label)),
            ],
            onChanged: (v) => setState(() => _contactId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _propertyId,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Property', border: OutlineInputBorder()),
            items: [
              for (final p in properties)
                DropdownMenuItem(value: p.id, child: Text(p.label)),
            ],
            onChanged: (v) => setState(() => _propertyId = v),
          ),
          const SizedBox(height: 12),
          _dateTile('Start', _start, (d) => setState(() => _start = d)),
          _dateTile('End', _end, (d) => setState(() => _end = d)),
          _tf(_description, 'Description', maxLines: 4),
          _tf(_scope, 'Scope of work', maxLines: 4),
        ],
      ),
    );
  }

  Widget _dateTile(String label, DateTime? value, ValueChanged<DateTime> onSet) =>
      ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        title: Text(label),
        subtitle: Text(formatDate(value) ?? 'Not set'),
        trailing: const Icon(Icons.calendar_today_outlined),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (picked != null) onSet(picked);
        },
      );

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
