import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/widgets.dart';
import '../../data/auth/auth_controller.dart';
import '../../data/dev/demo_seed.dart';
import '../../data/net/connection_check.dart';
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
              if (await _confirmSignOut(context, ref)) {
                ref.read(authControllerProvider.notifier).signOut();
              }
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

    final body = Column(
      children: [
        const SyncBanner(),
        Expanded(
          child: IndexedStack(
            index: _index,
            children: [for (final s in _sections) s.body],
          ),
        ),
      ],
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

/// Signing out wipes the local database, so ask first — and say so plainly
/// when there are changes that haven't reached the server yet, or when
/// there's no internet to sign back in with.
Future<bool> _confirmSignOut(BuildContext context, WidgetRef ref) async {
  // Start the connection check now so the answer is ready as the dialog opens.
  unawaited(ref.read(connectionProvider.notifier).check());
  await ref.read(syncServiceProvider).refreshPendingCount();
  if (!context.mounted) return false;
  final pending = ref.read(syncServiceProvider).current.pendingPush;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      // The red "no entry" road sign: you're not leaving that easily.
      icon: Icon(Icons.do_not_disturb_on,
          color: Colors.red.shade600, size: 48),
      title: const Text('Trying to escape work?', textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            pending > 0
                ? 'Hold on — $pending change(s) haven\'t made it to the server '
                    'yet. Escape now and they\'re gone for good.\n\n'
                    '[Getting back in requires an internet connection.]'
                : 'The crew will manage without you ...probably.\n\n'
                    '[Getting back in requires an internet connection.]',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const _ConnectionNotice(),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Back to work'),
        ),
        TextButton(
          style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.pop(context, true),
          child: Text(pending > 0 ? 'Escape anyway' : 'Escape!'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Live result of the connection check, for the sign-out dialog.
class _ConnectionNotice extends ConsumerWidget {
  const _ConnectionNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    final (Widget icon, String text, Color? color) = switch (conn.state) {
      NetState.unknown || NetState.checking => (
          const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          'Checking your internet connection…',
          null,
        ),
      NetState.online => (
          Icon(Icons.wifi, size: 18, color: Colors.green.shade600),
          'Internet connection available — you can get back in any time.',
          Colors.green.shade600,
        ),
      NetState.serverDown => (
          Icon(Icons.warning_amber_rounded,
              size: 18, color: Colors.orange.shade700),
          "Warning: the Thyme server isn't responding — you won't be able to "
              'get back in until it is.',
          Colors.orange.shade700,
        ),
      _ => (
          Icon(Icons.wifi_off, size: 18, color: Colors.orange.shade700),
          "Warning: no internet connection — if you escape now, you can't get "
              'back in until you\'re online again.',
          Colors.orange.shade700,
        ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 8),
        Flexible(
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
