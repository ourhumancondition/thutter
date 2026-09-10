import '../../core/config.dart';
import '../db/database.dart';

/// Fully synthetic sample data (no real records) so the UI can be exercised
/// before PocketBase API rules are in place. Debug builds only — surfaced from
/// the account menu. Everything it inserts is marked `dirty`, so once real sync
/// works it will try to push; call [clearDemo] first if you don't want that.
Future<void> loadDemoData(AppDatabase db) async {
  final now = DateTime.now().toUtc().toIso8601String();
  Map<String, dynamic> rec(String id, Map<String, dynamic> fields) => {
        'id': id,
        'created': now,
        'updated': now,
        ...fields,
      };

  await db.upsertLocal(Config.cWorkspace,
      rec('local_ws_demo', {'tenant_name': 'Demo Landscaping Co', 'owner_id': 'local_user_demo'}));

  await db.upsertLocal(Config.cUsers, rec('local_user_demo', {
    'email': 'demo@thyme.local',
    'first_name': 'Demo',
    'last_name': 'User',
    'display_name': 'Demo User',
    'type': 'admin',
    'workspaces': 'local_ws_demo',
  }));

  final contacts = [
    rec('local_c1', {'firstname': 'Marie', 'lastname': 'Tremblay', 'title': 'Owner', 'email': 'marie@example.com', 'mobile': 4165550111, 'city': 'Toronto', 'province': 'ON', 'source': 'Referral'}),
    rec('local_c2', {'firstname': 'James', 'lastname': 'Okafor', 'title': 'Facilities Manager', 'email': 'james@example.com', 'mobile': 6475550142, 'company': 'local_co1', 'city': 'Mississauga', 'province': 'ON', 'source': 'Google'}),
    rec('local_c3', {'firstname': 'Priya', 'lastname': 'Nair', 'email': 'priya@example.com', 'phone': 9055550190, 'city': 'Oakville', 'province': 'ON', 'source': 'Facebook'}),
  ];
  for (final c in contacts) {
    await db.upsertLocal(Config.cContacts, c);
  }

  final companies = [
    rec('local_co1', {'company': 'Northside Property Group', 'industry': 'Maintenance', 'billing_email': 'ap@northside.example', 'phone': 4165559000, 'customer': true, 'workspace_id': 'local_ws_demo'}),
    rec('local_co2', {'company': 'GreenLeaf Supply', 'industry': 'Supply', 'supplier': true, 'workspace_id': 'local_ws_demo'}),
  ];
  for (final c in companies) {
    await db.upsertLocal(Config.cCompanies, c);
  }

  final employees = [
    rec('local_e1', {'firstname': 'Sam', 'lastname': 'Rivera', 'fullname': 'Sam Rivera', 'email': 'sam@demo.local', 'jobType': 'Crew Lead', 'rate': 32, 'isActive': true, 'drive': true, 'license_type': 'G', 'workspace': 'local_ws_demo'}),
    rec('local_e2', {'firstname': 'Dana', 'lastname': 'Cho', 'fullname': 'Dana Cho', 'email': 'dana@demo.local', 'jobType': 'Operator', 'rate': 28, 'isActive': true, 'workspace': 'local_ws_demo'}),
    rec('local_e3', {'firstname': 'Alex', 'lastname': 'Boone', 'fullname': 'Alex Boone', 'jobType': 'Seasonal', 'isActive': false, 'isSubcontractor': true, 'workspace': 'local_ws_demo'}),
  ];
  for (final e in employees) {
    await db.upsertLocal(Config.cEmployees, e);
  }

  final leads = [
    rec('local_l1', {'lead': 'Spring cleanup + mulch', 'contact': 'local_c1', 'status': 'New', 'notes': '<p>Wants a quote for front and back beds.</p>', 'followup': now}),
    rec('local_l2', {'lead': 'Snow contract renewal', 'contact': 'local_c2', 'status': 'Follow up', 'notes': '<p>Renewal for the plaza lot.</p>'}),
    rec('local_l3', {'lead': 'Tree removal', 'contact': 'local_c3', 'status': 'Requires Visit'}),
  ];
  for (final l in leads) {
    await db.upsertLocal(Config.cLeads, l);
  }

  final tasks = [
    rec('local_t1', {'shortname': 'Quote Marie\'s beds', 'status': 'Open', 'completed': false, 'due': now, 'workspace': 'local_ws_demo'}),
    rec('local_t2', {'shortname': 'Service the mower', 'status': 'Open', 'completed': false, 'workspace': 'local_ws_demo'}),
    rec('local_t3', {'shortname': 'Send March invoices', 'status': 'Done', 'completed': true, 'workspace': 'local_ws_demo'}),
  ];
  for (final t in tasks) {
    await db.upsertLocal(Config.cTasks, t);
  }

  final properties = [
    rec('local_p1', {'name': 'Maple Court Estate', 'type': 'Residence', 'number': '14', 'street': 'Maple Court', 'city': 'Toronto', 'province': 'ON', 'contact': ['local_c1'], 'address_string': '14 Maple Court, Toronto, ON'}),
    rec('local_p2', {'name': 'Northside Plaza', 'type': 'Commercial', 'number': '900', 'street': 'Dundas St W', 'city': 'Mississauga', 'province': 'ON', 'contact': ['local_c2'], 'address_string': '900 Dundas St W, Mississauga, ON'}),
  ];
  for (final p in properties) {
    await db.upsertLocal(Config.cProperty, p);
  }

  final workorders = [
    rec('local_w1', {'name': 'Front bed redesign', 'contact': 'local_c1', 'property': 'local_p1', 'description': '<p>Replace overgrown junipers, add mulch and edging.</p>', 'start_date': now}),
    rec('local_w2', {'name': 'Plaza snow contract', 'contact': 'local_c2', 'property': 'local_p2', 'scope': '<p>Full-season plowing and salting.</p>'}),
  ];
  for (final w in workorders) {
    await db.upsertLocal(Config.cWorkorders, w);
  }

  final equipment = [
    rec('local_eq1', {'name': 'Skid steer', 'brand': 'Bobcat', 'model': 'S650', 'shortcode': 'SS-1', 'color': 'White', 'location': 'local_p2', 'operable': true, 'requires_safety': true}),
    rec('local_eq2', {'name': 'Crew truck', 'brand': 'Ford', 'model': 'F-250', 'shortcode': 'TRK-2', 'color': 'Blue', 'odometer': 84200, 'operable': true}),
    rec('local_eq3', {'name': 'Stump grinder', 'brand': 'Kubota', 'shortcode': 'SG-1', 'operable': false, 'requires_safety': true}),
  ];
  for (final e in equipment) {
    await db.upsertLocal(Config.cEquipment, e);
  }

  // A realistic clock sequence for today so the People / Sites views have
  // something to compute a live status from.
  final today = DateTime.now();
  String at(int h, int m) =>
      DateTime(today.year, today.month, today.day, h, m).toUtc().toIso8601String();

  final logs = [
    // Sam — on the clock, drove the truck, currently on site at Northside Plaza.
    rec('local_tl1', {'employee': 'local_e1', 'change': 'Start Day', 'timestamp': at(7, 0)}),
    rec('local_tl2', {'employee': 'local_e1', 'change': 'Travel', 'timestamp': at(7, 15), 'vehicle': 'local_eq2'}),
    rec('local_tl3', {'employee': 'local_e1', 'change': 'Site In', 'timestamp': at(8, 0), 'site': 'local_p2', 'billable': true, 'note_in': '<p>Plaza — spring cleanup</p>'}),
    // Dana — worked a morning at Maple Court, then clocked out.
    rec('local_tl4', {'employee': 'local_e2', 'change': 'Start Day', 'timestamp': at(6, 45)}),
    rec('local_tl5', {'employee': 'local_e2', 'change': 'Site In', 'timestamp': at(7, 30), 'site': 'local_p1', 'billable': true}),
    rec('local_tl6', {'employee': 'local_e2', 'change': 'Start Break', 'timestamp': at(11, 30)}),
    rec('local_tl7', {'employee': 'local_e2', 'change': 'Site In', 'timestamp': at(12, 0), 'site': 'local_p1', 'billable': true}),
    rec('local_tl8', {'employee': 'local_e2', 'change': 'Site Out', 'timestamp': at(15, 0)}),
    rec('local_tl9', {'employee': 'local_e2', 'change': 'End Day', 'timestamp': at(15, 30)}),
  ];
  for (final l in logs) {
    await db.upsertLocal(Config.cTimelogs, l);
  }
}

Future<void> clearDemo(AppDatabase db) => db.wipe();
