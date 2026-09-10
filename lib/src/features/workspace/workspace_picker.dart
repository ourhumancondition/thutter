import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/providers.dart';

Future<void> showWorkspacePicker(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (_) => const _WorkspaceSheet(),
  );
}

class _WorkspaceSheet extends ConsumerWidget {
  const _WorkspaceSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaces = ref.watch(myWorkspacesProvider);
    final active = ref.watch(activeWorkspaceProvider).value;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text('Workspace'),
            subtitle: Text('Companies, tasks and employees are scoped to this'),
          ),
          workspaces.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('$e'),
            ),
            data: (list) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No workspaces yet.'),
                  )
                : Column(
                    children: [
                      for (final w in list)
                        RadioListTile<String>(
                          value: w.id,
                          groupValue: active?.id,
                          title: Text(w.tenantName),
                          onChanged: (_) {
                            ref
                                .read(activeWorkspaceProvider.notifier)
                                .select(w);
                            Navigator.pop(context);
                          },
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
