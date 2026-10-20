import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config.dart';

/// Result of actually trying to reach the internet, not just whether Wi-Fi is
/// switched on.
enum NetState {
  /// Not checked yet.
  unknown,

  /// A check is in flight.
  checking,

  /// The Thyme server answered.
  online,

  /// No network interface at all (Wi-Fi off, cable unplugged).
  noNetwork,

  /// Connected to a network, but nothing on the internet answers.
  noInternet,

  /// The internet works but the Thyme server doesn't answer.
  serverDown,
}

class ConnectionCheck {
  const ConnectionCheck(this.state, {this.checkedAt});

  final NetState state;
  final DateTime? checkedAt;

  bool get isOnline => state == NetState.online;
  bool get isChecking => state == NetState.checking;

  /// No network or no internet — the user's side, not the server's.
  bool get noInternet =>
      state == NetState.noNetwork || state == NetState.noInternet;

  String get label => switch (state) {
        NetState.unknown => 'Not checked',
        NetState.checking => 'Checking connection…',
        NetState.online => 'Connected',
        NetState.noNetwork => 'No network',
        NetState.noInternet => 'No internet',
        NetState.serverDown => 'Thyme server not responding',
      };

  String get message => switch (state) {
        NetState.unknown || NetState.checking => 'Checking your connection…',
        NetState.online => 'Connected to the internet and the Thyme server.',
        NetState.noNetwork =>
          'No network connection — Wi-Fi is off or no network is connected.',
        NetState.noInternet =>
          "No internet connection — you're on a network, but it can't reach "
              'the internet.',
        NetState.serverDown =>
          "The internet works, but the Thyme server isn't responding.",
      };
}

/// Sends one request and reports whether anything answered. Swapped out in
/// tests.
typedef Probe = Future<bool> Function(Uri url);

Future<bool> _httpProbe(Uri url) async {
  try {
    await http.get(url).timeout(const Duration(seconds: 6));
    return true; // any HTTP answer at all means we reached it
  } catch (_) {
    return false;
  }
}

final connectionProbeProvider = Provider<Probe>((ref) => _httpProbe);

/// Whether the device has a network interface up (cheap, local only).
typedef InterfaceCheck = Future<bool> Function();

final interfaceCheckProvider = Provider<InterfaceCheck>((ref) => () async {
      final r = await Connectivity().checkConnectivity();
      return r.any((e) => e != ConnectivityResult.none);
    });

/// The one connection check the whole app uses: the sign-out dialog, the
/// sync banner and the status chip all read this.
class ConnectionController extends Notifier<ConnectionCheck> {
  Future<ConnectionCheck>? _inFlight;

  /// Used to tell "no internet" from "Thyme server down".
  static final _internetProbeUrl =
      Uri.parse('https://www.gstatic.com/generate_204');

  @override
  ConnectionCheck build() => const ConnectionCheck(NetState.unknown);

  /// A sync just reached the server, so we're online — no probe needed.
  void markOnline() =>
      state = ConnectionCheck(NetState.online, checkedAt: DateTime.now());

  /// Runs a fresh check. Concurrent callers share the same check.
  Future<ConnectionCheck> check() =>
      _inFlight ??= _run().whenComplete(() => _inFlight = null);

  Future<ConnectionCheck> _run() async {
    state = ConnectionCheck(NetState.checking, checkedAt: state.checkedAt);
    final probe = ref.read(connectionProbeProvider);

    final NetState result;
    if (!await ref.read(interfaceCheckProvider)()) {
      result = NetState.noNetwork;
    } else if (await probe(
        Uri.parse('${Config.pocketBaseUrl}/api/health'))) {
      result = NetState.online;
    } else if (await probe(_internetProbeUrl)) {
      result = NetState.serverDown;
    } else {
      result = NetState.noInternet;
    }
    state = ConnectionCheck(result, checkedAt: DateTime.now());
    return state;
  }
}

final connectionProvider =
    NotifierProvider<ConnectionController, ConnectionCheck>(
        ConnectionController.new);
