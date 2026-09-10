import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/format.dart';
import '../../common/pb_image.dart';
import '../../common/photo_field.dart';
import '../../common/widgets.dart';
import '../../core/config.dart';
import '../../data/models/models.dart';
import '../../data/repositories/providers.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsListProvider);
    final companies = ref.watch(companiesByIdProvider).value ?? const {};

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SearchBar(
              hintText: 'Search contacts',
              leading: const Icon(Icons.search),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: contacts.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (list) {
                final filtered = _query.isEmpty
                    ? list
                    : list
                        .where((c) =>
                            c.label.toLowerCase().contains(_query) ||
                            (c.email ?? '').toLowerCase().contains(_query))
                        .toList();
                if (filtered.isEmpty) {
                  return const EmptyState(
                      icon: Icons.contacts_outlined,
                      message: 'No contacts');
                }
                return SyncRefresh(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final c = filtered[i];
                      final company = companies[c.companyId];
                      return ListTile(
                        leading: PbImage(
                          collection: Config.cContacts,
                          recordId: c.id,
                          filename: c.image,
                          size: 40,
                          fallbackIcon: Icons.person_outline,
                        ),
                        title: Text(c.label),
                        subtitle: Text([
                          c.title,
                          company?.name,
                          c.email,
                        ].whereType<String>().join(' · ')),
                        trailing: c.isLocalOnly
                            ? const Icon(Icons.cloud_upload_outlined, size: 16)
                            : null,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ContactDetailScreen(id: c.id),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ContactEditScreen()),
        ),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('New contact'),
      ),
    );
  }
}

class ContactDetailScreen extends ConsumerWidget {
  const ContactDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = ref.watch(contactRepoProvider).watch(id);
    final companies = ref.watch(companiesByIdProvider).value ?? const {};

    return StreamBuilder<Contact?>(
      stream: contact,
      builder: (context, snap) {
        final c = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(c?.label ?? 'Contact'),
            actions: [
              if (c != null)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ContactEditScreen(existing: c),
                    ),
                  ),
                ),
              if (c != null)
                IconButton(
                  icon: const Icon(Icons.archive_outlined),
                  tooltip: 'Archive',
                  onPressed: () async {
                    await ref
                        .read(contactRepoProvider)
                        .update(id, {'archive': true});
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
            ],
          ),
          body: c == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(
                      child: PbImage(
                        collection: Config.cContacts,
                        recordId: c.id,
                        filename: c.image,
                        size: 96,
                        fallbackIcon: Icons.person_outline,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DetailRow('Name', c.label, icon: Icons.person_outline),
                    DetailRow('Title', c.title, icon: Icons.badge_outlined),
                    DetailRow('Email', c.email, icon: Icons.email_outlined),
                    DetailRow('Mobile', formatPhone(c.mobile),
                        icon: Icons.smartphone_outlined),
                    DetailRow('Phone', formatPhone(c.phone),
                        icon: Icons.phone_outlined),
                    DetailRow('Company', companies[c.companyId]?.name,
                        icon: Icons.business_outlined),
                    DetailRow('Address', c.addressLine,
                        icon: Icons.location_on_outlined),
                    DetailRow('Source', c.source, icon: Icons.input_outlined),
                    DetailRow('Facebook', c.facebook, icon: Icons.link_outlined),
                    if ((c.notes ?? '').isNotEmpty) ...[
                      const Divider(height: 32),
                      Text('Notes',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 6),
                      Text(plainText(c.notes)),
                    ],
                    const Divider(height: 32),
                    Text(
                      c.isLocalOnly
                          ? 'Not yet synced to the server'
                          : 'Updated ${formatDateTime(c.updatedAt) ?? '—'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class ContactEditScreen extends ConsumerStatefulWidget {
  const ContactEditScreen({super.key, this.existing});

  final Contact? existing;

  @override
  ConsumerState<ContactEditScreen> createState() => _ContactEditScreenState();
}

class _ContactEditScreenState extends ConsumerState<ContactEditScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _pendingPhoto;
  late final Map<String, TextEditingController> _c = {
    'firstname': TextEditingController(text: widget.existing?.firstname),
    'lastname': TextEditingController(text: widget.existing?.lastname),
    'title': TextEditingController(text: widget.existing?.title),
    'email': TextEditingController(text: widget.existing?.email),
    'mobile': TextEditingController(text: widget.existing?.mobile?.toString()),
    'phone': TextEditingController(text: widget.existing?.phone?.toString()),
    'address': TextEditingController(text: widget.existing?.address),
    'city': TextEditingController(text: widget.existing?.city),
    'province': TextEditingController(text: widget.existing?.province),
    'postal': TextEditingController(text: widget.existing?.postal),
    'notes': TextEditingController(text: widget.existing?.notes),
  };

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    num? parseNum(String s) => s.trim().isEmpty ? null : num.tryParse(s.replaceAll(RegExp(r'[^0-9]'), ''));

    final fields = <String, dynamic>{
      'firstname': _c['firstname']!.text.trim(),
      'lastname': _c['lastname']!.text.trim(),
      'title': _c['title']!.text.trim(),
      'email': _c['email']!.text.trim(),
      'mobile': parseNum(_c['mobile']!.text),
      'phone': parseNum(_c['phone']!.text),
      'address': _c['address']!.text.trim(),
      'city': _c['city']!.text.trim(),
      'province': _c['province']!.text.trim(),
      'postal': _c['postal']!.text.trim(),
      'notes': _c['notes']!.text.trim(),
    };

    final repo = ref.read(contactRepoProvider);
    final String id;
    if (widget.existing == null) {
      id = await repo.create(fields);
    } else {
      id = widget.existing!.id;
      await repo.update(id, fields);
    }
    if (_pendingPhoto != null) {
      await repo.attachFile(id, 'image', _pendingPhoto!);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    Widget field(String key, String label,
            {TextInputType? type, int maxLines = 1}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: TextFormField(
            controller: _c[key],
            keyboardType: type,
            maxLines: maxLines,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'New contact' : 'Edit contact'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            PhotoField(
              collection: Config.cContacts,
              recordId: widget.existing?.id ?? 'local_new',
              filename: widget.existing?.image,
              pendingPath: _pendingPhoto,
              label: 'Contact photo',
              onPick: (p) => setState(() => _pendingPhoto = p),
            ),
            Row(children: [
              Expanded(child: field('firstname', 'First name')),
              const SizedBox(width: 12),
              Expanded(child: field('lastname', 'Last name')),
            ]),
            field('title', 'Title'),
            field('email', 'Email', type: TextInputType.emailAddress),
            Row(children: [
              Expanded(
                  child: field('mobile', 'Mobile', type: TextInputType.phone)),
              const SizedBox(width: 12),
              Expanded(
                  child: field('phone', 'Phone', type: TextInputType.phone)),
            ]),
            field('address', 'Street address'),
            Row(children: [
              Expanded(child: field('city', 'City')),
              const SizedBox(width: 12),
              Expanded(child: field('province', 'Province')),
              const SizedBox(width: 12),
              Expanded(child: field('postal', 'Postal')),
            ]),
            field('notes', 'Notes', maxLines: 4),
          ],
        ),
      ),
    );
  }
}
