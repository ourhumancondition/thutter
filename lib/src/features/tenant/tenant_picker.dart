import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/providers.dart';

Future<void> showTenantPicker(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (_) => const _TenantSheet(),
  );
}

String _roleLabel(String? role) => switch (role) {
      'owner' => 'Owner',
      'admin' => 'Admin',
      'manager' => 'Manager',
      'staff' => 'Staff',
      _ => 'Member',
    };

class _TenantSheet extends ConsumerWidget {
  const _TenantSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenants = ref.watch(myTenantsProvider);
    final active = ref.watch(activeTenantProvider).value;
    final memberships = ref.watch(myMembershipsProvider).value ?? const [];
    final roleByTenant = {for (final m in memberships) m.tenantId: m.role};

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text('Business'),
            subtitle: Text('Everything you see and add belongs to this business'),
          ),
          tenants.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('$e'),
            ),
            data: (list) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'No businesses yet. They appear after the first sync.'),
                  )
                : RadioGroup<String>(
                    groupValue: active?.id,
                    onChanged: (id) {
                      final t = list.firstWhere((t) => t.id == id);
                      ref.read(activeTenantProvider.notifier).select(t);
                      Navigator.pop(context);
                    },
                    child: Column(
                      children: [
                        for (final t in list)
                          RadioListTile<String>(
                            value: t.id,
                            title: Text(t.name),
                            subtitle: Text(_roleLabel(roleByTenant[t.id])),
                          ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
