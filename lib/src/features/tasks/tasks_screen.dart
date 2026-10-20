import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/format.dart';
import '../../common/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/providers.dart';
import '../tenant/tenant_switcher.dart';

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksListProvider);

    return Scaffold(
      body: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.checklist_outlined, message: 'No tasks')
            : SyncRefresh(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final t = list[i];
                    return ListTile(
                      leading: Checkbox(
                        value: t.completed,
                        onChanged: (v) => ref
                            .read(taskRepoProvider)
                            .update(t.id, {'completed': v ?? false}),
                      ),
                      title: Text(
                        t.label,
                        style: t.completed
                            ? const TextStyle(
                                decoration: TextDecoration.lineThrough)
                            : null,
                      ),
                      subtitle: Text([
                        t.status,
                        if (t.due != null) 'Due ${formatDate(t.due)}',
                      ].whereType<String>().join(' · ')),
                      trailing: t.isLocalOnly
                          ? const Icon(Icons.cloud_upload_outlined, size: 16)
                          : null,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => TaskEditScreen(existing: t),
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
            MaterialPageRoute(builder: (_) => const TaskEditScreen()),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New task'),
      ),
    );
  }
}

class TaskEditScreen extends ConsumerStatefulWidget {
  const TaskEditScreen({super.key, this.existing});
  final Task? existing;

  @override
  ConsumerState<TaskEditScreen> createState() => _TaskEditScreenState();
}

/// Task statuses offered in the editor. `tasks.status` is free text on the
/// server, so this list lives here; "Done" is kept in step with `completed`.
const taskStatuses = ['Open', 'In progress', 'Waiting', 'Done'];
const _done = 'Done';

class _TaskEditScreenState extends ConsumerState<TaskEditScreen> {
  late final _name = TextEditingController(text: widget.existing?.shortname);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late bool _completed = widget.existing?.completed ?? false;
  late String _status = widget.existing?.status ?? (_completed ? _done : 'Open');
  late DateTime? _due = widget.existing?.due;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = ref.read(currentUserIdProvider);
    final fields = <String, dynamic>{
      'shortname': _name.text.trim(),
      'notes': _notes.text.trim(),
      'status': _status,
      'due': _due?.toUtc().toIso8601String(),
      'completed': _completed,
    };
    final repo = ref.read(taskRepoProvider);
    if (widget.existing == null) {
      if (user != null) fields['created_by'] = user;
      await repo.create(fields);
    } else {
      await repo.update(widget.existing!.id, fields);
    }
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New task' : 'Edit task'),
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await ref.read(taskRepoProvider).delete(widget.existing!.id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tf(_name, 'Task'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: DropdownButtonFormField<String>(
              // Rebuild when the Completed switch changes the status.
              key: ValueKey(_status),
              initialValue: _status,
              decoration: const InputDecoration(
                  labelText: 'Status', border: OutlineInputBorder()),
              items: [
                for (final s in taskStatuses)
                  DropdownMenuItem(value: s, child: Text(s)),
                // Keep an older free-text status selectable rather than lose it.
                if (!taskStatuses.contains(_status))
                  DropdownMenuItem(value: _status, child: Text(_status)),
              ],
              onChanged: (v) => setState(() {
                _status = v ?? _status;
                _completed = _status == _done;
              }),
            ),
          ),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(color: Theme.of(context).dividerColor),
            ),
            title: const Text('Due'),
            subtitle: Text(formatDate(_due) ?? 'Not set'),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _due ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _due = picked);
            },
          ),
          SwitchListTile(
            title: const Text('Completed'),
            value: _completed,
            onChanged: (v) => setState(() {
              _completed = v;
              if (v) {
                _status = _done;
              } else if (_status == _done) {
                _status = 'Open';
              }
            }),
          ),
          _tf(_notes, 'Notes', maxLines: 5),
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
