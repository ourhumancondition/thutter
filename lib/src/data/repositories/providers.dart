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
      activeTenantId: Config.tenantScoped.contains(collection)
          ? () => ref.read(activeTenantProvider).value?.id
          : null,
    );

/// Id of the signed-in user, or null.
final currentUserIdProvider = Provider<String?>(
    (ref) => ref.watch(authControllerProvider).user?.id);

final tenantRepoProvider =
    Provider((ref) => _repo(ref, Config.cTenants, Tenant.new));
final membershipRepoProvider =
    Provider((ref) => _repo(ref, Config.cMemberships, Membership.new));
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

// ------------------------------------------------------------------ tenant ---

const _activeTenantKey = 'active_tenant_id';

/// The signed-in user's active memberships, one per tenant they belong to.
final myMembershipsProvider = StreamProvider<List<Membership>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  return ref.watch(membershipRepoProvider).watchAll().map((all) =>
      all.where((m) => m.isActive && m.userId == uid).toList());
});

/// Businesses the signed-in user can switch between. The server only returns
/// tenants the user belongs to; this also narrows to their memberships (or the
/// `users.tenants` cache before memberships have synced).
final myTenantsProvider = StreamProvider<List<Tenant>>((ref) {
  final user = ref.watch(authControllerProvider).user;
  final memberships = ref.watch(myMembershipsProvider).value ?? const [];
  final allowed = {
    ...?user?.tenantIds,
    for (final m in memberships)
      if (m.tenantId != null) m.tenantId!,
  };
  return ref.watch(tenantRepoProvider).watchAll().map((all) {
    final list = all
        .where((t) => !t.isArchived && (allowed.isEmpty || allowed.contains(t.id)))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  });
});

class ActiveTenant extends AsyncNotifier<Tenant?> {
  @override
  Future<Tenant?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_activeTenantKey);
    // Watch the AsyncValue (not `.future`) to avoid re-subscription churn.
    final tenants = ref.watch(myTenantsProvider).value ?? const [];
    if (tenants.isEmpty) return null;
    return tenants.firstWhere(
      (t) => t.id == saved,
      orElse: () => tenants.first,
    );
  }

  Future<void> select(Tenant tenant) async {
    final previous = state.value?.id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeTenantKey, tenant.id);
    state = AsyncData(tenant);
    if (previous != null && previous != tenant.id) {
      ref.read(confirmAfterSwitchProvider.notifier).set(true);
    }
  }
}

/// True right after the user switches business, until they confirm the
/// business on their first new record — a guard against adding to the wrong
/// one out of habit.
class ConfirmAfterSwitch extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final confirmAfterSwitchProvider =
    NotifierProvider<ConfirmAfterSwitch, bool>(ConfirmAfterSwitch.new);

final activeTenantProvider =
    AsyncNotifierProvider<ActiveTenant, Tenant?>(ActiveTenant.new);

/// The signed-in user's membership (and so role) in the active tenant.
final activeMembershipProvider = Provider<Membership?>((ref) {
  final tenant = ref.watch(activeTenantProvider).value;
  final memberships = ref.watch(myMembershipsProvider).value ?? const [];
  if (tenant == null) return null;
  for (final m in memberships) {
    if (m.tenantId == tenant.id) return m;
  }
  return null;
});

/// Rows of a tenant-scoped collection that belong to the active tenant.
/// Nothing shows until a tenant is chosen — every row has one.
Stream<List<T>> _forActiveTenant<T extends PbRecord>(
  Ref ref,
  CollectionRepository<T> repo,
) {
  final tenantId = ref.watch(activeTenantProvider).value?.id;
  return repo
      .watchAll()
      .map((list) => list.where((r) => r.tenantId == tenantId).toList());
}

// ------------------------------------------------------------------ lists ---

int _cmpDateDesc(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return b.compareTo(a);
}

final contactsListProvider = StreamProvider<List<Contact>>((ref) {
  return _forActiveTenant(ref, ref.watch(contactRepoProvider)).map((list) {
    final visible = list.where((c) => !c.archived).toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return visible;
  });
});

final companiesListProvider = StreamProvider<List<Company>>((ref) {
  return _forActiveTenant(ref, ref.watch(companyRepoProvider)).map((list) {
    final visible = [...list]
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return visible;
  });
});

final leadsListProvider = StreamProvider<List<Lead>>((ref) {
  return _forActiveTenant(ref, ref.watch(leadRepoProvider)).map((list) {
    final sorted = [...list]..sort((a, b) => _cmpDateDesc(a.followUp, b.followUp));
    return sorted;
  });
});

final tasksListProvider = StreamProvider<List<Task>>((ref) {
  return _forActiveTenant(ref, ref.watch(taskRepoProvider)).map((list) {
    final visible = [...list]
      ..sort((a, b) {
        if (a.completed != b.completed) return a.completed ? 1 : -1;
        return _cmpDateDesc(b.due, a.due) * -1;
      });
    return visible;
  });
});

final employeesListProvider = StreamProvider<List<Employee>>((ref) {
  return _forActiveTenant(ref, ref.watch(employeeRepoProvider)).map((list) {
    final visible = [...list]
      ..sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    return visible;
  });
});

final timelogsListProvider = StreamProvider<List<Timelog>>((ref) {
  return _forActiveTenant(ref, ref.watch(timelogRepoProvider)).map((list) {
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
  return _forActiveTenant(ref, ref.watch(propertyRepoProvider)).map((list) {
    final sorted = [...list]
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return sorted;
  });
});

final workOrdersListProvider = StreamProvider<List<WorkOrder>>((ref) {
  return _forActiveTenant(ref, ref.watch(workOrderRepoProvider)).map((list) {
    final sorted = [...list]..sort((a, b) => _cmpDateDesc(a.startDate, b.startDate));
    return sorted;
  });
});

final equipmentListProvider = StreamProvider<List<Equipment>>((ref) {
  return _forActiveTenant(ref, ref.watch(equipmentRepoProvider)).map((list) {
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
