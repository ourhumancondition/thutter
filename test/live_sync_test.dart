@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:thutter/src/core/config.dart';
import 'package:thutter/src/data/db/database.dart';
import 'package:thutter/src/data/sync/sync_service.dart';

/// Hits the real PocketBase server.
///
///   flutter test --tags live --run-skipped
///
/// The auth'd test needs admin creds:
///   flutter test --tags live --run-skipped \
///     --dart-define=PB_ADMIN=ourhumancondition@gmail.com \
///     --dart-define=PB_ADMIN_PW=...
void main() {
  test('pull (unauth): API rules keep data out of an anonymous sync', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final pb = PocketBase(Config.pocketBaseUrl);
    final sync = SyncService(db, pb);

    // No token — every collection's listRule filters everything out.
    for (final c in [Config.cTenants, Config.cContacts, Config.cCompanies]) {
      await sync.pullCollection(c);
      expect(await db.getCollection(c), isEmpty, reason: '$c leaked to anon');
      // The pull still succeeds and advances the cursor — it's just empty.
      expect(await db.lastSynced(c), isNotNull);
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('pull (authed): the API rules let a token read the data collections',
      () async {
    const admin = String.fromEnvironment('PB_ADMIN');
    const pw = String.fromEnvironment('PB_ADMIN_PW');
    if (admin.isEmpty || pw.isEmpty) {
      markTestSkipped('set --dart-define=PB_ADMIN / PB_ADMIN_PW');
      return;
    }

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final pb = PocketBase(Config.pocketBaseUrl);

    final client = HttpClient();
    final req = await client.postUrl(
        Uri.parse('${Config.pocketBaseUrl}/api/admins/auth-with-password'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'identity': admin, 'password': pw}));
    final resp = await req.close();
    final body = jsonDecode(await resp.transform(utf8.decoder).join())
        as Map<String, dynamic>;
    client.close();
    pb.authStore.save(body['token'] as String, null);
    expect(pb.authStore.isValid, isTrue);

    final sync = SyncService(db, pb);
    await sync.syncAll();

    for (final c in [
      Config.cContacts,
      Config.cCompanies,
      Config.cProperty,
      Config.cEmployees,
      Config.cLeads,
      Config.cTimelogs,
    ]) {
      expect(await db.getCollection(c), isNotEmpty, reason: 'pulled $c');
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
