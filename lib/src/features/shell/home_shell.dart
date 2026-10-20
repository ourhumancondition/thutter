import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/widgets.dart';
import '../../data/auth/auth_controller.dart';
import '../../data/dev/demo_seed.dart';
import '../../data/providers.dart';
import '../../data/repositories/providers.dart';
import '../companies/companies_screen.dart';
import '../contacts/contacts_screen.dart';
import '../employees/employees_screen.dart';
import '../equipment/equipment_screen.dart';
import '../leads/leads_screen.dart';
import '../property/property_screen.dart';
import '../tasks/tasks_screen.dart';
import '../timelogs/timelogs_screen.dart';
import '../workorders/workorders_screen.dart';
import '../tenant/tenant_picker.dart';

class _Section {
  const _Section(this.label, this.icon, this.body);
  final String label;
  final IconData icon;
  final Widget body;
}

const _sections = [
  _Section('Contacts', Icons.contacts_outlined, ContactsScreen()),
  _Section('Companies', Icons.business_outlined, CompaniesScreen()),
  _Section('Properties', Icons.home_work_outlined, PropertyScreen()),
  _Section('Leads', Icons.trending_up_outlined, LeadsScreen()),
  _Section('Work orders', Icons.engineering_outlined, WorkOrdersScreen()),
  _Section('Tasks', Icons.checklist_outlined, TasksScreen()),
  _Section('Employees', Icons.badge_outlined, EmployeesScreen()),
  _Section('Equipment', Icons.agriculture_outlined, EquipmentScreen()),
  _Section('Time logs', Icons.schedule_outlined, TimelogsScreen()),
];

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  // Debug: `--dart-define=TAB=8` opens a specific section on launch.
  int _index =
      const int.fromEnvironment('TAB').clamp(0, _sections.length - 1);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final tenant = ref.watch(activeTenantProvider).value;
    final user = ref.watch(authControllerProvider).user;

    final appBar = AppBar(
      title: Text(_sections[_index].label),
      actions: [
        const SyncStatusChip(),
        PopupMenuButton<String>(
          icon: const Icon(Icons.account_circle_outlined),
          onSelected: (v) async {
            if (v == 'tenant') {
              showTenantPicker(context);
            } else if (v == 'signout') {
              ref.read(authControllerProvider.notifier).signOut();
            } else if (v == 'demo') {
              await loadDemoData(ref.read(databaseProvider));
              await ref.read(syncServiceProvider).refreshPendingCount();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              enabled: false,
              child: Text(user?.label ?? 'Signed in'),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'tenant',
              child: ListTile(
                leading: const Icon(Icons.business_outlined),
                title: Text(tenant?.name ?? 'Choose business'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'signout',
              child: ListTile(
                leading: Icon(Icons.logout),
                title: Text('Sign out'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (kDebugMode)
              const PopupMenuItem(
                value: 'demo',
                child: ListTile(
                  leading: Icon(Icons.science_outlined),
                  title: Text('Load demo data'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
          ],
        ),
      ],
    );

    final body = IndexedStack(
      index: _index,
      children: [for (final s in _sections) s.body],
    );

    void select(int i) {
      setState(() => _index = i);
      if (!wide) Navigator.maybePop(context); // close the drawer
    }

    final navChildren = [
      for (var i = 0; i < _sections.length; i++)
        NavigationDrawerDestination(
          icon: Icon(_sections[i].icon),
          label: Text(_sections[i].label),
        ),
    ];

    if (wide) {
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            SingleChildScrollView(
              child: IntrinsicHeight(
                child: NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: select,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final s in _sections)
                      NavigationRailDestination(
                        icon: Icon(s.icon),
                        label: Text(s.label),
                      ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      drawer: NavigationDrawer(
        selectedIndex: _index,
        onDestinationSelected: select,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 16, 16, 8),
            child: Text('Thyme'),
          ),
          ...navChildren,
        ],
      ),
      body: body,
    );
  }
}
