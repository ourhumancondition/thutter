import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../common/format.dart';
import '../data/providers.dart';
import '../data/sync/sync_coordinator.dart';
import '../data/sync/sync_service.dart';

/// Small status pill for the app bar: online/offline + pending changes.
class SyncStatusChip extends ConsumerWidget {
  const SyncStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineProvider).value ?? false;
    final status =
        ref.watch(syncStatusProvider).value ?? const SyncStatus();

    late final IconData icon;
    late final String label;
    Color? color;

    if (status.phase == SyncPhase.running) {
      icon = Icons.sync;
      label = 'Syncing…';
    } else if (!online) {
      icon = Icons.cloud_off;
      label = status.pendingPush > 0 ? '${status.pendingPush} to sync' : 'Offline';
      color = Colors.orange;
    } else if (status.phase == SyncPhase.error) {
      icon = Icons.sync_problem;
      label = 'Sync error';
      color = Theme.of(context).colorScheme.error;
    } else if (status.pendingPush > 0) {
      icon = Icons.cloud_upload_outlined;
      label = '${status.pendingPush} to sync';
    } else {
      icon = Icons.cloud_done_outlined;
      label = 'Synced ${relativeTime(status.lastRun)}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ActionChip(
        avatar: Icon(icon, size: 18, color: color),
        label: Text(label),
        onPressed: () => ref.read(syncCoordinatorProvider).syncNow(),
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
