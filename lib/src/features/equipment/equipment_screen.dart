import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/format.dart';
import '../../common/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/providers.dart';
import '../../data/status/employee_status.dart';

const _brands = [
  'Bobcat', 'CAT', 'Chevrolet', 'Dodge', 'Ford', 'GMC', 'Komatsu', 'Kubota',
];
const _colors = [
  'Black', 'Blue', 'Grey', 'Orange', 'Purple', 'Red', 'White', 'Yellow',
];

class EquipmentScreen extends ConsumerWidget {
  const EquipmentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final equipment = ref.watch(equipmentListProvider);
    final properties = ref.watch(propertiesByIdProvider).value ?? const {};

    return Scaffold(
      body: equipment.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.agriculture_outlined, message: 'No equipment')
            : SyncRefresh(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final e = list[i];
                    final inUse = ref.watch(employeesInVehicleProvider(e.id));
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: inUse.isNotEmpty
                            ? Colors.blue.withValues(alpha: 0.15)
                            : e.operable
                                ? null
                                : Colors.grey.shade400,
                        child: Icon(Icons.agriculture,
                            color: inUse.isNotEmpty ? Colors.blue : null),
                      ),
                      title: Text(e.label),
                      subtitle: Text([
                        if (inUse.isNotEmpty) 'In use',
                        e.shortcode,
                        properties[e.locationId]?.label,
                        if (!e.operable) 'Out of service',
                      ].whereType<String>().join(' · ')),
                      trailing: e.isLocalOnly
                          ? const Icon(Icons.cloud_upload_outlined, size: 16)
                          : null,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => EquipmentDetailScreen(id: e.id),
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
            MaterialPageRoute(builder: (_) => const EquipmentEditScreen()),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New equipment'),
      ),
    );
  }
}

class EquipmentDetailScreen extends ConsumerWidget {
  const EquipmentDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(equipmentByIdProvider).value?[id];
    final properties = ref.watch(propertiesByIdProvider).value ?? const {};
    final employees = ref.watch(employeesByIdProvider).value ?? const {};
    final inUse = ref.watch(employeesInVehicleProvider(id));

    return Scaffold(
      appBar: AppBar(
        title: Text(e?.label ?? 'Equipment'),
        actions: [
          if (e != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EquipmentEditScreen(existing: e),
              )),
            ),
        ],
      ),
      body: e == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (inUse.isNotEmpty) ...[
                  Card(
                    color: Colors.blue.withValues(alpha: 0.12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('In use by',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          for (final id in inUse)
                            Text('• ${employees[id]?.label ?? id}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                DetailRow('Make', [e.brand, e.model].whereType<String>().join(' '),
                    icon: Icons.info_outline),
                DetailRow('Short code', e.shortcode, icon: Icons.tag),
                DetailRow('Serial', e.serialno, icon: Icons.numbers),
                DetailRow('Colour', e.color),
                DetailRow('Location', properties[e.locationId]?.label,
                    icon: Icons.place_outlined),
                DetailRow('Odometer / hours', e.odometer?.toString()),
                DetailRow('Operable', e.operable ? 'Yes' : 'No'),
                DetailRow('Annual safety', formatDate(e.annualSafety)),
                DetailRow('Registration', formatDate(e.registration)),
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
  }
}

class EquipmentEditScreen extends ConsumerStatefulWidget {
  const EquipmentEditScreen({super.key, this.existing});
  final Equipment? existing;

  @override
  ConsumerState<EquipmentEditScreen> createState() =>
      _EquipmentEditScreenState();
}

class _EquipmentEditScreenState extends ConsumerState<EquipmentEditScreen> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _model = TextEditingController(text: widget.existing?.model);
  late final _shortcode =
      TextEditingController(text: widget.existing?.shortcode);
  late final _serial = TextEditingController(text: widget.existing?.serialno);
  late final _odometer =
      TextEditingController(text: widget.existing?.odometer?.toString());
  late String? _brand = widget.existing?.brand;
  late String? _color = widget.existing?.color;
  late String? _locationId = widget.existing?.locationId;
  late bool _operable = widget.existing?.operable ?? true;
  late bool _requiresSafety = widget.existing?.requiresSafety ?? false;

  @override
  void dispose() {
    for (final c in [_name, _model, _shortcode, _serial, _odometer]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final fields = <String, dynamic>{
      'name': _name.text.trim(),
      'model': _model.text.trim(),
      'shortcode': _shortcode.text.trim(),
      'serialno': _serial.text.trim(),
      'odometer': num.tryParse(_odometer.text.trim()),
      'brand': _brand,
      'color': _color,
      if (_locationId != null) 'location': _locationId,
      'operable': _operable,
      'requires_safety': _requiresSafety,
    };
    final repo = ref.read(equipmentRepoProvider);
    if (widget.existing == null) {
      await repo.create(fields);
    } else {
      await repo.update(widget.existing!.id, fields);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final properties = ref.watch(propertiesListProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.existing == null ? 'New equipment' : 'Edit equipment'),
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await ref
                    .read(equipmentRepoProvider)
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
          Row(children: [
            Expanded(child: _tf(_model, 'Model')),
            const SizedBox(width: 12),
            Expanded(child: _tf(_shortcode, 'Short code')),
          ]),
          _tf(_serial, 'Serial number'),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _brand,
                decoration: const InputDecoration(
                    labelText: 'Brand', border: OutlineInputBorder()),
                items: [
                  for (final b in _brands)
                    DropdownMenuItem(value: b, child: Text(b)),
                ],
                onChanged: (v) => setState(() => _brand = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _color,
                decoration: const InputDecoration(
                    labelText: 'Colour', border: OutlineInputBorder()),
                items: [
                  for (final c in _colors)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => _color = v),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _locationId,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Location', border: OutlineInputBorder()),
            items: [
              for (final p in properties)
                DropdownMenuItem(value: p.id, child: Text(p.label)),
            ],
            onChanged: (v) => setState(() => _locationId = v),
          ),
          const SizedBox(height: 6),
          _tf(_odometer, 'Odometer / hours', type: TextInputType.number),
          SwitchListTile(
            title: const Text('Operable'),
            value: _operable,
            onChanged: (v) => setState(() => _operable = v),
          ),
          SwitchListTile(
            title: const Text('Requires safety inspection'),
            value: _requiresSafety,
            onChanged: (v) => setState(() => _requiresSafety = v),
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
