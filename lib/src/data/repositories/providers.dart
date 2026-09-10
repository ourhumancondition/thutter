import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config.dart';
import '../auth/auth_controller.dart';
import '../models/models.dart';
import '../providers.dart';
import 'collection_repository.dart';

CollectionRepository<T> _repo<T extends PbRecord>(
  Ref ref,
  String collection,
  T Function(Map<String, dynamic>) fromJson,
) =>
    CollectionRepository<T>(
      collection: collection,
      fromJson: fromJson,
      db: ref.watch(databaseProvider),
    );

/// Id of the signed-in user, or null.
final currentUserIdProvider = Provider<String?>(
    (ref) => ref.watch(authControllerProvider).user?.id);

final workspaceRepoProvider = Provider(
    (ref) => _repo(ref, Config.cWorkspace, Workspace.new));
final userRepoProvider =
    Provider((ref) => _repo(ref, Config.cUsers, AppUser.new));
final contactRepoProvider =
    Provider((ref) => _repo(ref, Config.cContacts, Contact.new));
final companyRepoProvider =
    Provider((ref) => _repo(ref, Config.cCompanies, Company.new));
final leadRepoProvider =
    Provider((ref) => _repo(ref, Config.cLeads, Lead.new));
final taskRepoProvider =
    Provider((ref) => _repo(ref, Config.cTasks, Task.new));
final employeeRepoProvider =
    Provider((ref) => _repo(ref, Config.cEmployees, Employee.new));
final timelogRepoProvider =
    Provider((ref) => _repo(ref, Config.cTimelogs, Timelog.new));
final propertyRepoProvider =
    Provider((ref) => _repo(ref, Config.cProperty, Property.new));
final workOrderRepoProvider =
    Provider((ref) => _repo(ref, Config.cWorkorders, WorkOrder.new));
final equipmentRepoProvider =
    Provider((ref) => _repo(ref, Config.cEquipment, Equipment.new));

// --------------------------------------------------------------- workspace ---

const _activeWorkspaceKey = 'active_workspace_id';

/// Workspaces owned by the signed-in user.
final myWorkspacesProvider = StreamProvider<List<Workspace>>((ref) {
  final uid = ref.watch(authControllerProvider).user?.id;
  return ref.watch(workspaceRepoProvider).watchAll().map((all) {
    final list = all
        .where((w) => !w.isDeleted && (uid == null || w.ownerId == uid))
        .toList()
      ..sort((a, b) => a.tenantName.toLowerCase().compareTo(b.tenantName.toLowerCase()));
    return list;
  });
});

class ActiveWorkspace extends AsyncNotifier<Workspace?> {
  @override
  Future<Workspace?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_activeWorkspaceKey);
    // Watch the AsyncValue (not `.future`) to avoid re-subscription churn.
    final workspaces = ref.watch(myWorkspacesProvider).value ?? const [];
    if (workspaces.isEmpty) return null;
    return workspaces.firstWhere(
      (w) => w.id == saved,
      orElse: () => workspaces.first,
    );
  }

  Future<void> select(Workspace workspace) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeWorkspaceKey, workspace.id);
    state = AsyncData(workspace);
  }
}

final activeWorkspaceProvider =
    AsyncNotifierProvider<ActiveWorkspace, Workspace?>(ActiveWorkspace.new);

// ------------------------------------------------------------------ lists ---

int _cmpDateDesc(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return b.compareTo(a);
}

final contactsListProvider = StreamProvider<List<Contact>>((ref) {
  return ref.watch(contactRepoProvider).watchAll().map((list) {
    final visible = list.where((c) => !c.archived).toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return visible;
  });
});

final companiesListProvider = StreamProvider<List<Company>>((ref) {
  final ws = ref.watch(activeWorkspaceProvider).value;
  return ref.watch(companyRepoProvider).watchAll().map((list) {
    final visible = list
        .where((c) => ws == null || c.workspaceId == null || c.workspaceId == ws.id)
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return visible;
  });
});

final leadsListProvider = StreamProvider<List<Lead>>((ref) {
  return ref.watch(leadRepoProvider).watchAll().map((list) {
    final sorted = [...list]..sort((a, b) => _cmpDateDesc(a.followUp, b.followUp));
    return sorted;
  });
});

final tasksListProvider = StreamProvider<List<Task>>((ref) {
  final ws = ref.watch(activeWorkspaceProvider).value;
  return ref.watch(taskRepoProvider).watchAll().map((list) {
    final visible = list
        .where((t) => ws == null || t.workspaceId == null || t.workspaceId == ws.id)
        .toList()
      ..sort((a, b) {
        if (a.completed != b.completed) return a.completed ? 1 : -1;
        return _cmpDateDesc(b.due, a.due) * -1;
      });
    return visible;
  });
});

final employeesListProvider = StreamProvider<List<Employee>>((ref) {
  final ws = ref.watch(activeWorkspaceProvider).value;
  return ref.watch(employeeRepoProvider).watchAll().map((list) {
    final visible = list
        .where((e) => ws == null || e.workspaceId == null || e.workspaceId == ws.id)
        .toList()
      ..sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    return visible;
  });
});

final timelogsListProvider = StreamProvider<List<Timelog>>((ref) {
  return ref.watch(timelogRepoProvider).watchAll().map((list) {
    final sorted = [...list]..sort((a, b) => _cmpDateDesc(a.timestamp, b.timestamp));
    return sorted;
  });
});

/// Lookup maps for resolving relation ids to labels in the UI.
final contactsByIdProvider = StreamProvider<Map<String, Contact>>((ref) {
  return ref
      .watch(contactRepoProvider)
      .watchAll()
      .map((list) => {for (final c in list) c.id: c});
});

final companiesByIdProvider = StreamProvider<Map<String, Company>>((ref) {
  return ref
      .watch(companyRepoProvider)
      .watchAll()
      .map((list) => {for (final c in list) c.id: c});
});

final employeesByIdProvider = StreamProvider<Map<String, Employee>>((ref) {
  return ref
      .watch(employeeRepoProvider)
      .watchAll()
      .map((list) => {for (final e in list) e.id: e});
});

final propertiesByIdProvider = StreamProvider<Map<String, Property>>((ref) {
  return ref
      .watch(propertyRepoProvider)
      .watchAll()
      .map((list) => {for (final p in list) p.id: p});
});

final propertiesListProvider = StreamProvider<List<Property>>((ref) {
  return ref.watch(propertyRepoProvider).watchAll().map((list) {
    final sorted = [...list]
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return sorted;
  });
});

final workOrdersListProvider = StreamProvider<List<WorkOrder>>((ref) {
  return ref.watch(workOrderRepoProvider).watchAll().map((list) {
    final sorted = [...list]..sort((a, b) => _cmpDateDesc(a.startDate, b.startDate));
    return sorted;
  });
});

final equipmentListProvider = StreamProvider<List<Equipment>>((ref) {
  return ref.watch(equipmentRepoProvider).watchAll().map((list) {
    final sorted = [...list]
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return sorted;
  });
});

final equipmentByIdProvider = StreamProvider<Map<String, Equipment>>((ref) {
  return ref
      .watch(equipmentRepoProvider)
      .watchAll()
      .map((list) => {for (final e in list) e.id: e});
});
