import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../common/format.dart';
import '../data/net/connection_check.dart';
import '../data/providers.dart';
import '../data/sync/sync_coordinator.dart';
import '../data/sync/sync_service.dart';

/// Short label for a sync failure, for the chip and banner.
String _problemLabel(SyncProblem p) => switch (p) {
      SyncProblem.unreachable => "Can't reach server",
      SyncProblem.signedOut => 'Sign-in expired',
      SyncProblem.rejected => 'Sync refused',
      _ => 'Sync failed',
    };

/// Small status pill for the app bar: online/offline + pending changes.
/// Tapping it syncs; when something is wrong it opens the details instead.
class SyncStatusChip extends ConsumerWidget {
  const SyncStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    final online =
        (ref.watch(onlineProvider).value ?? false) && !conn.noInternet;
    final status = ref.watch(syncStatusProvider).value ?? const SyncStatus();

    late final IconData icon;
    late final String label;
    Color? color;

    if (status.phase == SyncPhase.running) {
      icon = Icons.sync;
      label = 'Syncing…';
    } else if (!online) {
      icon = Icons.wifi_off;
      label = status.pendingPush > 0
          ? 'No internet · ${status.pendingPush} to sync'
          : 'No internet';
      color = Colors.orange;
    } else if (conn.state == NetState.serverDown) {
      icon = Icons.cloud_off;
      label = 'Server down';
      color = Theme.of(context).colorScheme.error;
    } else if (status.hasError) {
      icon = Icons.sync_problem;
      label = _problemLabel(status.problem);
      color = Theme.of(context).colorScheme.error;
    } else if (status.pendingPush > 0) {
      icon = Icons.cloud_upload_outlined;
      label = '${status.pendingPush} to sync';
    } else {
      icon = Icons.cloud_done_outlined;
      label = 'Synced ${relativeTime(status.lastRun)}';
    }

    final troubled =
        !online || conn.state == NetState.serverDown || status.hasError;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ActionChip(
        avatar: Icon(icon, size: 18, color: color),
        label: Text(label, style: TextStyle(color: color)),
        side: color == null ? null : BorderSide(color: color),
        tooltip: troubled ? 'Show sync details' : 'Sync now',
        onPressed: troubled
            ? () => showSyncDetails(context)
            : () => ref.read(syncCoordinatorProvider).syncNow(),
      ),
    );
  }
}

/// Full-width strip under the app bar, shown only while offline or while
/// sync is failing, so a problem can't go unnoticed.
class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    final online =
        (ref.watch(onlineProvider).value ?? true) && !conn.noInternet;
    final status = ref.watch(syncStatusProvider).value ?? const SyncStatus();
    final scheme = Theme.of(context).colorScheme;

    final keepWorking = status.pendingPush > 0
        ? '${status.pendingPush} change(s) are saved on this device and will '
            'sync when the connection is back.'
        : 'You can keep working; changes sync when the connection is back.';

    final String message;
    final Color background;
    final Color foreground;
    final IconData icon;
    if (!online) {
      icon = Icons.wifi_off;
      message = conn.state == NetState.noNetwork
          ? 'No network connection. $keepWorking'
          : 'No internet connection. $keepWorking';
      background = Colors.orange.shade100;
      foreground = Colors.orange.shade900;
    } else if (conn.state == NetState.serverDown) {
      icon = Icons.cloud_off;
      message = "The internet works, but the Thyme server isn't responding. "
          '$keepWorking';
      background = scheme.errorContainer;
      foreground = scheme.onErrorContainer;
    } else if (status.hasError) {
      icon = Icons.sync_problem;
      message = status.lastError ?? 'Sync failed.';
      background = scheme.errorContainer;
      foreground = scheme.onErrorContainer;
    } else {
      return const SizedBox.shrink();
    }

    final retrying = status.phase == SyncPhase.running || conn.isChecking;
    return Material(
      color: background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Icon(icon, color: foreground, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: TextStyle(color: foreground)),
            ),
            TextButton(
              onPressed: () => showSyncDetails(context),
              child: Text('Details', style: TextStyle(color: foreground)),
            ),
            TextButton(
              onPressed: retrying ? null : () => _retry(ref),
              child: Text(retrying ? 'Retrying…' : 'Retry',
                  style: TextStyle(color: foreground)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Check the connection first; only sync if it's actually there, so Retry
/// gives an honest answer instead of another timeout.
Future<void> _retry(WidgetRef ref) async {
  final result = await ref.read(connectionProvider.notifier).check();
  if (result.isOnline) await ref.read(syncCoordinatorProvider).syncNow();
}

/// Sheet with everything known about the sync state, including the raw
/// server error for troubleshooting.
Future<void> showSyncDetails(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (_) => const _SyncDetailsSheet(),
  );
}

class _SyncDetailsSheet extends ConsumerWidget {
  const _SyncDetailsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    final online =
        (ref.watch(onlineProvider).value ?? true) && !conn.noInternet;
    final status = ref.watch(syncStatusProvider).value ?? const SyncStatus();

    final state = switch (status.phase) {
      SyncPhase.running => 'Syncing now…',
      _ when !online => conn.label,
      _ when conn.state == NetState.serverDown => conn.label,
      SyncPhase.error => _problemLabel(status.problem),
      _ => 'Working normally',
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sync', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            DetailRow('Status', state),
            DetailRow(
                'Connection',
                conn.checkedAt == null || conn.isChecking
                    ? conn.message
                    : '${conn.message} (checked ${relativeTime(conn.checkedAt)})'),
            DetailRow(
                'Last synced',
                status.lastSuccess == null
                    ? 'Not since the app opened'
                    : '${formatDateTime(status.lastSuccess)} '
                        '(${relativeTime(status.lastSuccess)})'),
            DetailRow('Waiting to upload', '${status.pendingPush} change(s)'),
            if (status.hasError) ...[
              DetailRow('Problem', status.lastError),
              DetailRow('Technical detail', status.errorDetail),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: conn.isChecking
                      ? null
                      : () => ref.read(connectionProvider.notifier).check(),
                  icon: const Icon(Icons.network_check),
                  label:
                      Text(conn.isChecking ? 'Checking…' : 'Check connection'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed:
                      status.phase == SyncPhase.running || conn.isChecking
                          ? null
                          : () => _retry(ref),
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps a scrollable list body with pull-to-refresh that triggers a sync.
class SyncRefresh extends ConsumerWidget {
  const SyncRefresh({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.read(syncCoordinatorProvider).syncNow(),
      child: child,
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(icon, size: 64, color: Theme.of(context).disabledColor),
        const SizedBox(height: 12),
        Text(message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}

/// Read-only key/value row for detail screens.
class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {super.key, this.icon});

  final String label;
  final String? value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: Theme.of(context).hintColor),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(label,
                      style: TextStyle(color: Theme.of(context).hintColor)),
                ),
              ],
            ),
          ),
          Expanded(child: Text(value!)),
        ],
      ),
    );
  }
}

/// Strips HTML tags from PocketBase `editor` fields for compact display.
String plainText(String? html) {
  if (html == null) return '';
  return html
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
