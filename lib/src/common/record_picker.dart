import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/models.dart';
import '../data/repositories/providers.dart';
import 'format.dart';

/// One choice in a [RecordPickerField]: a title plus a line of context so
/// similar records can be told apart. Search matches both.
class PickerOption {
  const PickerOption(this.id, this.title, {this.subtitle, this.icon});

  final String id;
  final String title;
  final String? subtitle;
  final IconData? icon;

  bool matches(String query) {
    final haystack = '$title ${subtitle ?? ''}'.toLowerCase();
    return query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .every(haystack.contains);
  }
}

/// A form field that picks one record from a searchable list. Looks like the
/// other outlined fields; tapping opens a dialog with a search box.
class RecordPickerField extends StatelessWidget {
  const RecordPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon,
  });

  final String label;
  final String? value;
  final List<PickerOption> options;
  final ValueChanged<String?> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final selected = options.where((o) => o.id == value).firstOrNull;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final picked = await showDialog<_Pick>(
          context: context,
          builder: (_) => _PickerDialog(
              label: label, options: options, selectedId: value),
        );
        if (picked != null) onChanged(picked.id);
      },
      child: InputDecorator(
        isEmpty: selected == null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: icon == null ? null : Icon(icon),
          suffixIcon: selected == null
              ? const Icon(Icons.search)
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.clear),
                  onPressed: () => onChanged(null),
                ),
        ),
        child: selected == null
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(selected.title, overflow: TextOverflow.ellipsis),
                  if (selected.subtitle != null)
                    Text(
                      selected.subtitle!,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
      ),
    );
  }
}

/// Result wrapper so "picked nothing" (dialog dismissed) differs from
/// "picked None".
class _Pick {
  const _Pick(this.id);
  final String? id;
}

class _PickerDialog extends StatefulWidget {
  const _PickerDialog({
    required this.label,
    required this.options,
    required this.selectedId,
  });

  final String label;
  final List<PickerOption> options;
  final String? selectedId;

  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final results =
        widget.options.where((o) => o.matches(_query)).toList(growable: false);
    return AlertDialog(
      title: Text('Choose ${widget.label.toLowerCase()}'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
              onSubmitted: (_) {
                if (results.length == 1) {
                  Navigator.pop(context, _Pick(results.single.id));
                }
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Text('Nothing matches "$_query"',
                          style: TextStyle(
                              color: Theme.of(context).hintColor)),
                    )
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, i) {
                        final o = results[i];
                        final isSelected = o.id == widget.selectedId;
                        return ListTile(
                          leading: o.icon == null ? null : Icon(o.icon),
                          title: Text(o.title),
                          subtitle:
                              o.subtitle == null ? null : Text(o.subtitle!),
                          trailing:
                              isSelected ? const Icon(Icons.check) : null,
                          selected: isSelected,
                          onTap: () => Navigator.pop(context, _Pick(o.id)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.selectedId != null)
          TextButton(
            onPressed: () => Navigator.pop(context, const _Pick(null)),
            child: const Text('Clear'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

String? _join(Iterable<String?> parts) =>
    parts.whereType<String>().where((s) => s.isNotEmpty).join(' · ').nullIfEmpty;

// ------------------------------------------------- ready-made record pickers --

/// Contact picker; context = title, company, email or phone.
class ContactPickerField extends ConsumerWidget {
  const ContactPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsListProvider).value ?? const [];
    final companies = ref.watch(companiesByIdProvider).value ?? const {};
    return RecordPickerField(
      label: label,
      value: value,
      icon: Icons.person_outline,
      onChanged: onChanged,
      options: [
        for (final c in contacts)
          PickerOption(
            c.id,
            c.label,
            subtitle: _join([
              c.title,
              companies[c.companyId]?.label,
              c.email ?? formatPhone(c.mobile ?? c.phone),
            ]),
          ),
      ],
    );
  }
}

/// Property / site picker; title = name with its address after a comma,
/// context = type and the property's contacts.
class PropertyPickerField extends ConsumerWidget {
  const PropertyPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final properties = ref.watch(propertiesListProvider).value ?? const [];
    final contacts = ref.watch(contactsByIdProvider).value ?? const {};
    return RecordPickerField(
      label: label,
      value: value,
      icon: Icons.home_work_outlined,
      onChanged: onChanged,
      options: [
        for (final p in properties)
          PickerOption(
            p.id,
            p.labelWithAddress,
            subtitle: _join([
              p.type,
              ...p.contactIds.map((id) => contacts[id]?.label),
            ]),
          ),
      ],
    );
  }
}

/// Employee picker; context = job type, subcontractor, inactive.
class EmployeePickerField extends ConsumerWidget {
  const EmployeePickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees = ref.watch(employeesListProvider).value ?? const [];
    return RecordPickerField(
      label: label,
      value: value,
      icon: Icons.badge_outlined,
      onChanged: onChanged,
      options: [
        for (final e in employees)
          PickerOption(
            e.id,
            e.label,
            subtitle: _join([
              e.jobType,
              if (e.isSubcontractor) 'Subcontractor',
              if (!e.isActive) 'Inactive',
            ]),
          ),
      ],
    );
  }
}

/// Equipment / vehicle picker; context = shortcode, where it is, out of
/// service.
class EquipmentPickerField extends ConsumerWidget {
  const EquipmentPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final equipment = ref.watch(equipmentListProvider).value ?? const [];
    final properties = ref.watch(propertiesByIdProvider).value ?? const {};
    return RecordPickerField(
      label: label,
      value: value,
      icon: Icons.agriculture_outlined,
      onChanged: onChanged,
      options: [
        for (final e in equipment)
          PickerOption(
            e.id,
            e.label,
            subtitle: _join([
              e.shortcode,
              properties[e.locationId]?.label,
              if (!e.operable) 'Out of service',
            ]),
          ),
      ],
    );
  }
}
