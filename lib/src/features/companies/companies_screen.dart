import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/format.dart';
import '../../common/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/providers.dart';
import '../tenant/tenant_switcher.dart';

const _industries = [
  'Concrete', 'Construction', 'Gardening', 'Landscape', 'Maintenance',
  'Snow', 'Supply', 'Tree Service', 'Industrial', 'Other',
];

class CompaniesScreen extends ConsumerStatefulWidget {
  const CompaniesScreen({super.key});

  @override
  ConsumerState<CompaniesScreen> createState() => _CompaniesScreenState();
}

class _CompaniesScreenState extends ConsumerState<CompaniesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final companies = ref.watch(companiesListProvider);
    return Scaffold(
      body: Column(
        children: [
          ListSearchBar(
            hint: 'Search companies — name, industry, email, phone, address',
            onChanged: (v) => setState(() => _query = v),
          ),
          Expanded(
            child: companies.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (all) {
                final list = all
                    .where((c) => matchesSearch(_query, [
                          c.label,
                          c.industry,
                          c.billingEmail,
                          c.phone,
                          formatPhone(c.phone),
                          c.address,
                          if (c.isCustomer) 'customer',
                          if (c.isSupplier) 'supplier',
                        ]))
                    .toList();
                return list.isEmpty
                  ? EmptyState(
                      icon: Icons.business_outlined,
                      message: _query.trim().isEmpty
                          ? 'No companies'
                          : 'No companies match "${_query.trim()}"')
                  : SyncRefresh(
                      child: ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final c = list[i];
                          return ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.business)),
                            title: Text(c.label),
                            subtitle: Text([
                              c.industry,
                              if (c.isCustomer) 'Customer',
                              if (c.isSupplier) 'Supplier',
                            ].whereType<String>().join(' · ')),
                            trailing: c.isLocalOnly
                                ? const Icon(Icons.cloud_upload_outlined, size: 16)
                                : null,
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => CompanyDetailScreen(id: c.id),
                            )),
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
        onPressed: () => confirmTenantThen(
          context,
          ref,
          () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CompanyEditScreen()),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New company'),
      ),
    );
  }
}

class CompanyDetailScreen extends ConsumerWidget {
  const CompanyDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<Company?>(
      stream: ref.watch(companyRepoProvider).watch(id),
      builder: (context, snap) {
        final c = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(c?.label ?? 'Company'),
            actions: [
              if (c != null)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CompanyEditScreen(existing: c),
                  )),
                ),
              if (c != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await ref.read(companyRepoProvider).delete(id);
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
                    DetailRow('Name', c.name, icon: Icons.business_outlined),
                    DetailRow('Industry', c.industry, icon: Icons.category_outlined),
                    DetailRow('Phone', formatPhone(c.phone), icon: Icons.phone_outlined),
                    DetailRow('Billing email', c.billingEmail, icon: Icons.email_outlined),
                    DetailRow('Address', c.address, icon: Icons.location_on_outlined),
                    DetailRow('Customer', c.isCustomer ? 'Yes' : null),
                    DetailRow('Supplier', c.isSupplier ? 'Yes' : null),
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

class CompanyEditScreen extends ConsumerStatefulWidget {
  const CompanyEditScreen({super.key, this.existing});
  final Company? existing;

  @override
  ConsumerState<CompanyEditScreen> createState() => _CompanyEditScreenState();
}

class _CompanyEditScreenState extends ConsumerState<CompanyEditScreen> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _phone =
      TextEditingController(text: widget.existing?.phone?.toString());
  late final _address = TextEditingController(text: widget.existing?.address);
  late final _billing = TextEditingController(text: widget.existing?.billingEmail);
  late String? _industry = widget.existing?.industry;
  late bool _customer = widget.existing?.isCustomer ?? false;
  late bool _supplier = widget.existing?.isSupplier ?? false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _billing.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final fields = <String, dynamic>{
      'company': _name.text.trim(),
      'phone': num.tryParse(_phone.text.replaceAll(RegExp(r'[^0-9]'), '')),
      'address': _address.text.trim(),
      'billing_email': _billing.text.trim(),
      'industry': _industry,
      'customer': _customer,
      'supplier': _supplier,
    };
    final repo = ref.read(companyRepoProvider);
    if (widget.existing == null) {
      await repo.create(fields);
    } else {
      await repo.update(widget.existing!.id, fields);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New company' : 'Edit company'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tf(_name, 'Company name'),
          _tf(_phone, 'Phone', type: TextInputType.phone),
          _tf(_billing, 'Billing email', type: TextInputType.emailAddress),
          _tf(_address, 'Address'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _industry,
            decoration: const InputDecoration(
                labelText: 'Industry', border: OutlineInputBorder()),
            items: [
              for (final i in _industries)
                DropdownMenuItem(value: i, child: Text(i)),
            ],
            onChanged: (v) => setState(() => _industry = v),
          ),
          SwitchListTile(
            title: const Text('Customer'),
            value: _customer,
            onChanged: (v) => setState(() => _customer = v),
          ),
          SwitchListTile(
            title: const Text('Supplier'),
            value: _supplier,
            onChanged: (v) => setState(() => _supplier = v),
          ),
        ],
      ),
    );
  }

  Widget _tf(TextEditingController c, String label, {TextInputType? type}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
          controller: c,
          keyboardType: type,
          decoration:
              InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );
}
