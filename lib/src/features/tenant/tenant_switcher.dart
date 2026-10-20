import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/repositories/providers.dart';
import '../../data/sync/sync_coordinator.dart';

/// Colours an owner can pick for their business, also used (by id) as the
/// automatic colour until they do. Dark enough for white initials.
const tenantPalette = <Color>[
  Color(0xFF2E7D32), // green
  Color(0xFF1565C0), // blue
  Color(0xFF6A1B9A), // purple
  Color(0xFFEF6C00), // orange
  Color(0xFF00838F), // teal
  Color(0xFFC62828), // red
  Color(0xFF283593), // indigo
  Color(0xFF6D4C41), // brown
  Color(0xFFAD1457), // pink
  Color(0xFF827717), // olive
];

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Color? _parseHex(String? hex) {
  if (hex == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) return null;
  return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}

int _hash(String s) =>
    s.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) & 0x7fffffff);

/// One business on its own: the owner's pick, else a steady palette colour
/// from its id. Prefer [assignTenantColors] when showing several businesses.
Color tenantColor(Tenant t) =>
    _parseHex(t.colorHex) ?? tenantPalette[_hash(t.id) % tenantPalette.length];

/// Colours for a set of businesses that never repeat while the palette has a
/// free one: owner picks first, then automatic colours (in id order, starting
/// from each id's own slot) skip anything already taken. Deterministic, so a
/// user sees the same colours on every device.
Map<String, Color> assignTenantColors(List<Tenant> tenants) {
  final out = <String, Color>{};
  final used = <int>{};
  for (final t in tenants) {
    final picked = _parseHex(t.colorHex);
    if (picked != null) {
      out[t.id] = picked;
      used.add(picked.toARGB32());
    }
  }
  final rest = tenants.where((t) => !out.containsKey(t.id)).toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  final n = tenantPalette.length;
  for (final t in rest) {
    final start = _hash(t.id) % n;
    var color = tenantPalette[start];
    for (var i = 0; i < n; i++) {
      final candidate = tenantPalette[(start + i) % n];
      if (!used.contains(candidate.toARGB32())) {
        color = candidate;
        break;
      }
    }
    out[t.id] = color;
    used.add(color.toARGB32());
  }
  return out;
}

/// Colour of each business the user can switch between, by tenant id.
final tenantColorsProvider = Provider<Map<String, Color>>((ref) =>
    assignTenantColors(ref.watch(myTenantsProvider).value ?? const []));

Color _colorOf(WidgetRef ref, Tenant t) =>
    ref.watch(tenantColorsProvider)[t.id] ?? tenantColor(t);

/// "Kalmark Integrated Systems Ltd" → "KI", "Natura" → "N".
String tenantInitials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  return words.take(2).map((w) => w[0].toUpperCase()).join();
}

String roleLabel(String? role) => switch (role) {
      'owner' => 'Owner',
      'admin' => 'Admin',
      'manager' => 'Manager',
      'staff' => 'Staff',
      _ => 'Member',
    };

/// Round initials badge in the business's colour.
class TenantBadge extends ConsumerWidget {
  const TenantBadge(this.tenant, {super.key, this.size = 28, this.color});

  final Tenant tenant;
  final double size;

  /// Overrides the business's colour (for previews).
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: color ?? _colorOf(ref, tenant),
      child: Text(
        tenantInitials(tenant.name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}

/// Always-visible business switcher for the top bar: badge + name, and a ▾
/// menu when the user belongs to more than one business. With a single
/// business it's just the name.
class TenantSwitcher extends ConsumerWidget {
  const TenantSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeTenantProvider).value;
    final tenants = ref.watch(myTenantsProvider).value ?? const [];
    final memberships = ref.watch(myMembershipsProvider).value ?? const [];
    final roleByTenant = {for (final m in memberships) m.tenantId: m.role};
    final canEdit =
        ref.watch(activeMembershipProvider)?.canManageMembers ?? false;

    if (active == null) {
      return Text('No business',
          style: TextStyle(color: Theme.of(context).hintColor));
    }

    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TenantBadge(active),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            active.name,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );

    if (tenants.length < 2) {
      return Tooltip(message: 'Your business', child: label);
    }

    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      builder: (context, controller, _) => Tooltip(
        message: 'Switch business',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: label),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
      ),
      menuChildren: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Switch business'),
        ),
        for (final t in tenants)
          MenuItemButton(
            leadingIcon: TenantBadge(t, size: 24),
            trailingIcon: t.id == active.id
                ? const Icon(Icons.check)
                : const SizedBox(width: 24),
            onPressed: t.id == active.id
                ? null
                : () => ref.read(activeTenantProvider.notifier).select(t),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.name),
                  Text(roleLabel(roleByTenant[t.id]),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        if (canEdit) ...[
          const Divider(height: 1),
          MenuItemButton(
            leadingIcon: const Icon(Icons.palette_outlined),
            onPressed: () => showTenantColorPicker(context),
            child: const Text('Business colour…'),
          ),
        ],
      ],
    );
  }
}

/// Thin stripe in the active business's colour, for the bottom of the top
/// bar — a second at-a-glance cue for which business you're in.
class TenantStripe extends ConsumerWidget implements PreferredSizeWidget {
  const TenantStripe({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(4);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeTenantProvider).value;
    return Container(
      height: 4,
      color: active == null ? Colors.transparent : _colorOf(ref, active),
    );
  }
}

/// Lets an owner/admin pick the active business's colour. Saved to the
/// `tenants.color` field and synced, so it's the same on every device.
Future<void> showTenantColorPicker(BuildContext context) {
  return showDialog(
    context: context,
    builder: (_) => const _ColorPickerDialog(),
  );
}

class _ColorPickerDialog extends ConsumerStatefulWidget {
  const _ColorPickerDialog();

  @override
  ConsumerState<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends ConsumerState<_ColorPickerDialog> {
  /// null = automatic.
  String? _picked;
  bool _initialised = false;

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(activeTenantProvider).value;
    if (tenant == null) return const SizedBox.shrink();
    if (!_initialised) {
      _picked = _parseHex(tenant.colorHex) == null ? null : tenant.colorHex;
      _initialised = true;
    }
    // What "Automatic" would give this business next to the user's others.
    final others = (ref.watch(myTenantsProvider).value ?? const <Tenant>[])
        .where((t) => t.id != tenant.id);
    final autoColor = assignTenantColors(
        [...others, Tenant({...tenant.data, 'color': ''})])[tenant.id]!;
    final previewColor = _parseHex(_picked) ?? autoColor;

    Widget swatch(Color? c) {
      final hex = c == null ? null : _hex(c);
      final selected = _picked?.toUpperCase() == hex;
      final fill = c ?? autoColor;
      return Tooltip(
        message: c == null ? 'Automatic' : hex!,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => setState(() => _picked = hex),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.onSurface
                    : Colors.transparent,
                width: 3,
              ),
            ),
            child: c == null
                ? const Icon(Icons.auto_awesome, color: Colors.white, size: 18)
                : selected
                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                    : null,
          ),
        ),
      );
    }

    return AlertDialog(
      icon: TenantBadge(tenant, size: 48, color: previewColor),
      title: Text('Colour for ${tenant.name}', textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Shown on the business badge and the stripe under the top bar, '
            'for everyone in this business.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              swatch(null),
              for (final c in tenantPalette) swatch(c),
            ],
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            await ref
                .read(tenantRepoProvider)
                .update(tenant.id, {'color': _picked ?? ''});
            ref.read(syncCoordinatorProvider).syncNow();
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Runs [action] (opening a "New …" form), but the first time after a
/// business switch, asks the user to confirm which business it's going into.
Future<void> confirmTenantThen(
  BuildContext context,
  WidgetRef ref,
  void Function() action,
) async {
  final tenant = ref.read(activeTenantProvider).value;
  if (!ref.read(confirmAfterSwitchProvider) || tenant == null) {
    action();
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: TenantBadge(tenant, size: 48),
      title: Text('Add this to ${tenant.name}?', textAlign: TextAlign.center),
      content: const Text(
        "You just switched business. New records are saved to the business "
        'shown at the top left.',
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          autofocus: true,
          style: FilledButton.styleFrom(
              backgroundColor: ref.read(tenantColorsProvider)[tenant.id] ??
                  tenantColor(tenant)),
          onPressed: () => Navigator.pop(context, true),
          child: Text('Yes, add to ${tenant.name}'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  ref.read(confirmAfterSwitchProvider.notifier).set(false);
  if (context.mounted) action();
}
