import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/format.dart';
import '../../common/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/providers.dart';

const _leadStatuses = [
  'New', 'Chase', 'Follow up', 'Requires Visit', 'On Hold', 'Disqualified', 'Closed',
];

Color _statusColor(String? s) => switch (s) {
      'New' => Colors.blue,
      'Chase' || 'Follow up' => Colors.orange,
      'Requires Visit' => Colors.purple,
      'On Hold' => Colors.grey,
      'Disqualified' => Colors.red,
      'Closed' => Colors.green,
      _ => Colors.blueGrey,
    };

class LeadsScreen extends ConsumerWidget {
  const LeadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(leadsListProvider);
    final contacts = ref.watch(contactsByIdProvider).value ?? const {};

    return Scaffold(
      body: leads.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.trending_up_outlined, message: 'No leads')
            : SyncRefresh(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final l = list[i];
                    return ListTile(
                      title: Text(l.label),
                      subtitle: Text([
                        contacts[l.contactId]?.label,
                        if (l.followUp != null)
                          'Follow up ${formatDate(l.followUp)}',
                      ].whereType<String>().join(' · ')),
                      trailing: Chip(
                        label: Text(l.status ?? '—'),
                        backgroundColor:
                            _statusColor(l.status).withValues(alpha: 0.15),
                        side: BorderSide.none,
                        visualDensity: VisualDensity.compact,
                      ),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => LeadEditScreen(existing: l),
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
            MaterialPageRoute(builder: (_) => const LeadEditScreen()),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New lead'),
      ),
    );
  }
}

class LeadEditScreen extends ConsumerStatefulWidget {
  const LeadEditScreen({super.key, this.existing});
  final Lead? existing;

  @override
  ConsumerState<LeadEditScreen> createState() => _LeadEditScreenState();
}

class _LeadEditScreenState extends ConsumerState<LeadEditScreen> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late String? _status = widget.existing?.status ?? 'New';
  late String? _contactId = widget.existing?.contactId;
  late DateTime? _followUp = widget.existing?.followUp;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_contactId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A lead needs a contact')),
      );
      return;
    }
    final fields = <String, dynamic>{
      'lead': _title.text.trim(),
      'notes': _notes.text.trim(),
      'status': _status,
      'contact': _contactId,
      'followup': _followUp?.toUtc().toIso8601String(),
    };
    final repo = ref.read(leadRepoProvider);
    if (widget.existing == null) {
      await repo.create(fields);
    } else {
      await repo.update(widget.existing!.id, fields);
    }
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsListProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New lead' : 'Edit lead'),
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await ref.read(leadRepoProvider).delete(widget.existing!.id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: TextField(
              controller: _title,
              decoration: const InputDecoration(
                  labelText: 'What is the lead?',
                  border: OutlineInputBorder()),
            ),
          ),
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
            initialValue: _status,
            decoration: const InputDecoration(
                labelText: 'Status', border: OutlineInputBorder()),
            items: [
              for (final s in _leadStatuses)
                DropdownMenuItem(value: s, child: Text(s)),
            ],
            onChanged: (v) => setState(() => _status = v),
          ),
          const SizedBox(height: 12),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(color: Theme.of(context).dividerColor),
            ),
            title: const Text('Follow up'),
            subtitle: Text(formatDate(_followUp) ?? 'Not set'),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _followUp ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _followUp = picked);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 5,
            decoration: const InputDecoration(
                labelText: 'Notes', border: OutlineInputBorder()),
          ),
        ],
      ),
    );
  }
}
