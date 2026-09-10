import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/data/auth/auth_controller.dart';
import 'src/data/dev/demo_seed.dart';
import 'src/data/pb/pocketbase_client.dart';
import 'src/data/providers.dart';

/// Debug convenience: `flutter run --dart-define=DEMO=1` boots straight into
/// the app with synthetic data (no network, no sign-in).
const _demoEnv = String.fromEnvironment('DEMO');
const _bootDemo = _demoEnv == '1' || _demoEnv == 'true';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final pbClient = await PocketBaseClient.create();

  final container = ProviderContainer(
    overrides: [pocketBaseClientProvider.overrideWithValue(pbClient)],
  );

  if (kDebugMode && _bootDemo) {
    await loadDemoData(container.read(databaseProvider));
    await container.read(authControllerProvider.notifier).enterDemoMode();
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ThutterApp(),
    ),
  );
}
