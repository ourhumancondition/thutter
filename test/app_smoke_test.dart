import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thutter/src/core/config.dart';
import 'package:thutter/src/data/db/database.dart';
import 'package:thutter/src/data/dev/demo_seed.dart';
import 'package:thutter/src/data/models/models.dart';
import 'package:thutter/src/data/net/connection_check.dart';
import 'package:thutter/src/data/pb/credential_store.dart';
import 'package:thutter/src/data/pb/pocketbase_client.dart';
import 'package:thutter/src/data/providers.dart';
import 'package:thutter/src/data/repositories/collection_repository.dart';
import 'package:thutter/src/common/record_picker.dart';
import 'package:thutter/src/common/widgets.dart';
import 'package:thutter/src/data/status/employee_status.dart';
import 'package:thutter/src/data/sync/sync_service.dart';
import 'package:thutter/src/data/repositories/providers.dart';
import 'package:thutter/src/features/tenant/tenant_switcher.dart';
import 'package:flutter/material.dart' show Color;

AppDatabase _memDb() => AppDatabase(NativeDatabase.memory());

CollectionRepository<Contact> _contacts(AppDatabase db) => CollectionRepository(
      collection: Config.cContacts,
      fromJson: Contact.new,
      db: db,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('demo seed populates every synced collection and queues it for push',
      () async {
    final db = _memDb();
    addTearDown(db.close);
    await loadDemoData(db);

    for (final c in Config.syncedCollections) {
      expect(await db.getCollection(c), isNotEmpty, reason: 'collection $c');
    }
    // Local edits are all dirty until the first successful push.
    expect((await db.dirtyRecords()).length, greaterThan(15));
  });

  test('typed models decode the seeded PocketBase JSON', () async {
    final db = _memDb();
    addTearDown(db.close);
    await loadDemoData(db);

    final companies = (await db.getCollection(Config.cCompanies))
        .map((r) => Company(jsonDecode(r.data) as Map<String, dynamic>))
        .toList();
    expect(companies.map((c) => c.name), contains('Northside Property Group'));
    expect(companies.firstWhere((c) => c.isCustomer).industry, 'Maintenance');

    final leads = (await db.getCollection(Config.cLeads))
        .map((r) => Lead(jsonDecode(r.data) as Map<String, dynamic>))
        .toList();
    expect(leads.every((l) => l.contactId != null), isTrue);
  });

  test('create → update → delete moves a record through the sync lifecycle',
      () async {
    final db = _memDb();
    addTearDown(db.close);
    final repo = _contacts(db);

    final id = await repo.create({'firstname': 'Test', 'lastname': 'Person'});
    expect(id, startsWith('local_'));

    var row = (await db.getRecord(Config.cContacts, id))!;
    expect(row.dirty, isTrue);
    expect(Contact(jsonDecode(row.data)).label, 'Test Person');

    await repo.update(id, {'title': 'Owner'});
    row = (await db.getRecord(Config.cContacts, id))!;
    expect(Contact(jsonDecode(row.data)).title, 'Owner');
    expect(row.dirty, isTrue);

    await repo.delete(id);
    row = (await db.getRecord(Config.cContacts, id))!;
    expect(row.deleted, isTrue);
    expect(row.dirty, isTrue);
  });

  test('tenant-scoped repos stamp the active tenant on create', () async {
    final db = _memDb();
    addTearDown(db.close);
    String? active;
    final repo = CollectionRepository(
      collection: Config.cContacts,
      fromJson: Contact.new,
      db: db,
      activeTenantId: () => active,
    );

    // No business chosen yet → refuse, rather than queue a create the server
    // will reject.
    expect(() => repo.create({'firstname': 'A'}), throwsStateError);

    active = 'natura';
    final id = await repo.create({'firstname': 'A'});
    expect((await repo.get(id))!.tenantId, 'natura');

    // An explicit tenant wins.
    final other = await repo.create({'firstname': 'B', 'tenant': 'kalmark'});
    expect((await repo.get(other))!.tenantId, 'kalmark');
  });

  test('pruneOutsideTenants drops synced rows from other tenants only',
      () async {
    final db = _memDb();
    addTearDown(db.close);
    Map<String, dynamic> row(String id, String tenant) =>
        {'id': id, 'updated': '2026-01-01 00:00:00.000Z', 'tenant': tenant};

    await db.upsertFromServer(Config.cContacts, row('keep', 'natura'));
    await db.upsertFromServer(Config.cContacts, row('gone', 'kalmark'));
    await db.upsertLocal(Config.cContacts, row('dirty', 'kalmark'));
    await db.setLastSynced(Config.cContacts, 'x');
    await db.setLastSynced(Config.cMemberships, 'y');

    await db.pruneOutsideTenants({Config.cContacts}, {'natura'});
    final ids = (await db.getCollection(Config.cContacts)).map((r) => r.id);
    expect(ids, unorderedEquals(['keep', 'dirty']));

    await db.clearCursors(keep: {Config.cMemberships});
    expect(await db.lastSynced(Config.cContacts), isNull);
    expect(await db.lastSynced(Config.cMemberships), 'y');
  });

  group('search and pickers', () {
    test('every word must match somewhere; blank matches all', () {
      final fields = ['James Okafor', 'Northside Property Group', null, 6475550142];
      expect(matchesSearch('', fields), isTrue);
      expect(matchesSearch('  ', fields), isTrue);
      expect(matchesSearch('james northside', fields), isTrue);
      expect(matchesSearch('JAMES', fields), isTrue);
      expect(matchesSearch('647555', fields), isTrue);
      expect(matchesSearch('james greenleaf', fields), isFalse);
    });

    test('property shows its name with the address after a comma', () {
      final named = Property({
        'id': 'p1',
        'name': 'Maple Court Estate',
        'number': '14',
        'street': 'Maple Court',
        'city': 'Toronto',
      });
      expect(named.labelWithAddress, 'Maple Court Estate, 14 Maple Court, Toronto');

      final withString = Property({
        'id': 'p2',
        'name': 'Plaza',
        'address_string': '900 Dundas St W, Mississauga, ON',
      });
      expect(withString.labelWithAddress, 'Plaza, 900 Dundas St W, Mississauga, ON');

      // No name → just the address; no address → just the name.
      expect(Property({'id': 'p3', 'street': 'Elm St', 'number': '5'}).labelWithAddress,
          '5 Elm St');
      expect(Property({'id': 'p4', 'name': 'Yard'}).labelWithAddress, 'Yard');
    });

    test('picker search covers the context line too', () {
      const o = PickerOption('c1', 'Marie Tremblay',
          subtitle: 'Owner · marie@example.com');
      expect(o.matches('marie'), isTrue);
      expect(o.matches('owner'), isTrue);
      expect(o.matches('example.com tremblay'), isTrue);
      expect(o.matches('james'), isFalse);
    });
  });

  group('business switcher', () {
    test('initials from the first two words', () {
      expect(tenantInitials('Kalmark Integrated Systems Ltd'), 'KI');
      expect(tenantInitials('Natura'), 'N');
      expect(tenantInitials('  natura   landscape '), 'NL');
    });

    test("owner's colour wins; otherwise a steady automatic one", () {
      final picked = Tenant({'id': 'abc', 'name': 'X', 'color': '#1565C0'});
      expect(tenantColor(picked), const Color(0xFF1565C0));

      final auto1 = Tenant({'id': 'zhshe5z3ncdvyy0', 'name': 'Natura'});
      final auto2 = Tenant({'id': 'zhshe5z3ncdvyy0', 'name': 'Renamed'});
      expect(tenantColor(auto1), tenantColor(auto2));
      expect(tenantPalette, contains(tenantColor(auto1)));

      // Junk in the field falls back rather than crashing.
      final junk = Tenant({'id': 'abc', 'name': 'X', 'color': 'green'});
      expect(tenantPalette, contains(tenantColor(junk)));
    });

    test('automatic colours never repeat while the palette has room', () {
      final many = [
        for (var i = 0; i < tenantPalette.length; i++)
          Tenant({'id': 'tenant$i', 'name': 'T$i'}),
      ];
      final colors = assignTenantColors(many);
      expect(colors.values.toSet().length, tenantPalette.length);

      // The live Natura + Kalmark ids collided under the old per-id colour.
      final pair = assignTenantColors([
        Tenant({'id': 'zhshe5z3ncdvyy0', 'name': 'Natura'}),
        Tenant({'id': 'uct1nxsasv3j378', 'name': 'Kalmark'}),
      ]);
      expect(pair['zhshe5z3ncdvyy0'], isNot(pair['uct1nxsasv3j378']));

      // An owner's pick is kept, and automatic ones avoid it.
      final mixed = assignTenantColors([
        Tenant({'id': 'a', 'name': 'A', 'color': '#2E7D32'}),
        Tenant({'id': 'b', 'name': 'B'}),
      ]);
      expect(mixed['a'], const Color(0xFF2E7D32));
      expect(mixed['b'], isNot(const Color(0xFF2E7D32)));
    });

    test('switching business arms the confirm-on-first-add guard', () async {
      SharedPreferences.setMockInitialValues({});
      final db = _memDb();
      addTearDown(db.close);
      Map<String, dynamic> t(String id) =>
          {'id': id, 'name': id, 'updated': '2026-01-01 00:00:00.000Z'};
      await db.upsertFromServer(Config.cTenants, t('natura'));
      await db.upsertFromServer(Config.cTenants, t('kalmark'));

      final c = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        pocketBaseClientProvider.overrideWithValue(
            PocketBaseClient.forTest(PocketBase('http://127.0.0.1:1'))),
      ]);
      addTearDown(c.dispose);
      c.listen(activeTenantProvider, (_, __) {});
      c.listen(myTenantsProvider, (_, __) {});
      await pumpEventQueue();
      final first = await c.read(activeTenantProvider.future);
      expect(first, isNotNull);
      expect(c.read(confirmAfterSwitchProvider), isFalse);

      final other = (await c.read(myTenantsProvider.future))
          .firstWhere((x) => x.id != first!.id);
      await c.read(activeTenantProvider.notifier).select(other);
      expect(c.read(activeTenantProvider).value?.id, other.id);
      expect(c.read(confirmAfterSwitchProvider), isTrue);
    });
  });

  group('connection check', () {
    Future<NetState> run({
      required bool iface,
      required bool server,
      required bool internet,
    }) async {
      final c = ProviderContainer(overrides: [
        interfaceCheckProvider.overrideWithValue(() async => iface),
        connectionProbeProvider.overrideWithValue((url) async =>
            url.path == '/api/health' ? server : internet),
      ]);
      addTearDown(c.dispose);
      return (await c.read(connectionProvider.notifier).check()).state;
    }

    test('server answers → online', () async {
      expect(await run(iface: true, server: true, internet: true),
          NetState.online);
    });
    test('Wi-Fi off → no network', () async {
      expect(await run(iface: false, server: true, internet: true),
          NetState.noNetwork);
    });
    test('on a network but nothing answers → no internet', () async {
      expect(await run(iface: true, server: false, internet: false),
          NetState.noInternet);
    });
    test('internet works but Thyme does not → server down', () async {
      expect(await run(iface: true, server: false, internet: true),
          NetState.serverDown);
    });
  });

  group('sync error descriptions', () {
    test('network failures read as "can\'t reach server"', () {
      final (p, msg, _) = SyncService.describeError(
          ClientException(statusCode: 0, originalError: 'Failed host lookup'),
          'downloading contacts');
      expect(p, SyncProblem.unreachable);
      expect(msg, contains("Can't reach the Thyme server"));
      expect(msg, contains('downloading contacts'));
    });

    test('a refused change shows the server message and field errors', () {
      final (p, msg, detail) = SyncService.describeError(
          ClientException(statusCode: 400, response: {
            'message': 'Failed to create record.',
            'data': {
              'tenant': {'code': 'validation_required'}
            },
          }),
          'uploading a change to tasks');
      expect(p, SyncProblem.rejected);
      expect(msg, contains('Failed to create record.'));
      expect(detail, contains('validation_required'));
    });

    test('401 means the sign-in expired', () {
      final (p, _, _) =
          SyncService.describeError(ClientException(statusCode: 401), 'x');
      expect(p, SyncProblem.signedOut);
    });
  });

  test('pull cursor + server upsert clears the dirty flag', () async {
    final db = _memDb();
    addTearDown(db.close);

    await db.upsertFromServer(Config.cContacts, {
      'id': 'srv1',
      'created': '2025-01-01 00:00:00.000Z',
      'updated': '2025-01-02 00:00:00.000Z',
      'firstname': 'Server',
      'lastname': 'Record',
    });
    final row = (await db.getRecord(Config.cContacts, 'srv1'))!;
    expect(row.dirty, isFalse);
    expect(row.updated, '2025-01-02 00:00:00.000Z');

    await db.setLastSynced(Config.cContacts, '2025-01-02T00:00:00.000Z');
    expect(await db.lastSynced(Config.cContacts), '2025-01-02T00:00:00.000Z');
  });

  test('watchCollection is live', () async {
    final db = _memDb();
    addTearDown(db.close);
    final repo = _contacts(db);

    final seen = <int>[];
    final sub = repo.watchAll().listen((list) => seen.add(list.length));
    await pumpEventQueue();
    await repo.create({'firstname': 'A'});
    await pumpEventQueue();
    await repo.create({'firstname': 'B'});
    await pumpEventQueue();
    await sub.cancel();

    expect(seen.last, 2);
  });

  group('duty status from time logs', () {
    Timelog log(String emp, String change, DateTime ts,
            {String? site, String? vehicle}) =>
        Timelog({
          'id': 'l${ts.millisecondsSinceEpoch}',
          'employee': emp,
          'change': change,
          'timestamp': ts.toUtc().toIso8601String(),
          if (site != null) 'site': site,
          if (vehicle != null) 'vehicle': vehicle,
        });

    final base = DateTime(2026, 6, 1, 7);

    ({DutyState state, String? site, String? vehicle}) statusOf(
        List<Timelog> events) {
      // Mirror employeeStatusProvider's per-employee reduction.
      events.sort((a, b) => a.timestamp!.compareTo(b.timestamp!));
      final state = dutyStateFor(events.last.change);
      String? site, vehicle;
      for (final e in events.reversed) {
        site ??= e.siteId;
        vehicle ??= e.vehicleId;
        if (e.change == 'Start Day') break;
      }
      if (state != DutyState.onSite) site = null;
      return (state: state, site: site, vehicle: vehicle);
    }

    test('on site after Site In', () {
      final s = statusOf([
        log('e1', 'Start Day', base),
        log('e1', 'Travel', base.add(const Duration(minutes: 15)),
            vehicle: 'truck'),
        log('e1', 'Site In', base.add(const Duration(hours: 1)), site: 'plaza'),
      ]);
      expect(s.state, DutyState.onSite);
      expect(s.site, 'plaza');
      expect(s.vehicle, 'truck');
    });

    test('off duty after End Day, site cleared', () {
      final s = statusOf([
        log('e2', 'Start Day', base),
        log('e2', 'Site In', base.add(const Duration(hours: 1)), site: 'maple'),
        log('e2', 'Site Out', base.add(const Duration(hours: 6))),
        log('e2', 'End Day', base.add(const Duration(hours: 7))),
      ]);
      expect(s.state, DutyState.offDuty);
      expect(s.site, isNull);
    });

    test('segments compute worked vs break time', () {
      final segs = segmentsFrom([
        log('e', 'Start Day', base),
        log('e', 'Site In', base.add(const Duration(hours: 1)), site: 's'),
        log('e', 'Start Break', base.add(const Duration(hours: 5))),
        log('e', 'Site In', base.add(const Duration(hours: 5, minutes: 30)),
            site: 's'),
        log('e', 'End Day', base.add(const Duration(hours: 9))),
      ]);
      final worked = segs
          .where((x) => x.counts)
          .fold(Duration.zero, (a, x) => a + x.duration);
      final brk = segs
          .where((x) => x.kind == DutyState.onBreak)
          .fold(Duration.zero, (a, x) => a + x.duration);
      expect(brk, const Duration(minutes: 30));
      expect(worked, const Duration(hours: 8, minutes: 30));
    });
  });

  test('CredentialStore round-trips and clears (remember me)', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await CredentialStore.load(), isNull);

    await CredentialStore.save('a@b.com', r'p@ss w:rd!');
    final saved = await CredentialStore.load();
    expect(saved!.email, 'a@b.com');
    expect(saved.password, r'p@ss w:rd!');

    await CredentialStore.clear();
    expect(await CredentialStore.load(), isNull);
  });

  test('PocketBaseClient.forTest wires a client without touching the keychain',
      () {
    final client =
        PocketBaseClient.forTest(PocketBase('http://127.0.0.1:1'));
    expect(client.isAuthenticated, isFalse);
    expect(client.authRecord, isNull);
  });

  test('provider graph builds with overrides', () {
    final db = _memDb();
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      pocketBaseClientProvider.overrideWithValue(
          PocketBaseClient.forTest(PocketBase('http://127.0.0.1:1'))),
    ]);
    addTearDown(container.dispose);

    expect(container.read(syncServiceProvider), isNotNull);
    expect(container.read(databaseProvider), same(db));
  });
}
