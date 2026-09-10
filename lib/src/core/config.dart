/// Static configuration for Thutter.
class Config {
  Config._();

  /// PocketBase server. Override at build time with:
  /// `flutter run --dart-define=PB_URL=https://...`
  static const pocketBaseUrl = String.fromEnvironment(
    'PB_URL',
    defaultValue: 'https://landscape.pockethost.io',
  );

  /// Canonical PocketBase collection names used by Thutter v1.
  static const cUsers = 'users';
  static const cWorkspace = 'workspace';
  static const cContacts = 'contactss';
  static const cCompanies = 'companies';
  static const cLeads = 'leads';
  static const cTasks = 'tasks';
  static const cEmployees = 'employees';
  static const cTimelogs = 'timelogs';
  static const cProperty = 'property';
  static const cWorkorders = 'workorders';
  static const cEquipment = 'equipment';

  /// Every collection the sync service manages, in dependency order
  /// (referenced-before-referencing where it matters for display).
  static const syncedCollections = <String>[
    cWorkspace,
    cUsers,
    cContacts,
    cCompanies,
    cProperty,
    cEmployees,
    cLeads,
    cWorkorders,
    cTasks,
    cEquipment,
    cTimelogs,
  ];

  /// How often to run a background sync while the app is foregrounded.
  static const syncInterval = Duration(minutes: 5);
}
