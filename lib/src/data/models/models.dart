import 'pb_record.dart';

export 'pb_record.dart';

/// A business using Thyme. Collection: `tenants`. Every operational record
/// points at one via its `tenant` relation.
class Tenant extends PbRecord {
  Tenant(super.data);

  String get name => str('name') ?? 'Untitled business';
  String? get slug => str('slug');
  String? get plan => str('plan'); // trial | active | suspended
  DateTime? get archivedAt => date('archived_at');
  bool get isArchived => archivedAt != null;
}

/// A user's role in one tenant. Collection: `memberships`.
class Membership extends PbRecord {
  Membership(super.data);

  String? get userId => rel('user');
  String? get role => str('role'); // owner | admin | manager | staff
  String? get status => str('status'); // active | invited | suspended
  bool get isActive => status == null || status == 'active';

  /// Owners and admins manage memberships; managers and up see all data.
  bool get canManageMembers => role == 'owner' || role == 'admin';
  bool get isStaff => role == 'staff';
}

/// An application user. Collection: `users`.
class AppUser extends PbRecord {
  AppUser(super.data);

  String? get email => str('email');
  String? get username => str('username');
  String? get firstName => str('first_name');
  String? get lastName => str('last_name');
  String? get displayName => str('display_name');
  String? get fullName => str('full_name');
  /// Cache of the tenants this user is an active member of. The API rules read
  /// it; the app uses it to know which tenants to offer.
  List<String> get tenantIds => relList('tenants');
  String? get employeeId => rel('employee');
  String? get contactProfileId => rel('contact_profile');
  bool get archived => flag('archive');

  String get label =>
      displayName ?? fullName ?? [firstName, lastName].whereType<String>().join(' ').trim().nullIfEmpty ?? email ?? username ?? id;
}

/// A contact. Collection: `contactss` (the richer of the three contact tables).
class Contact extends PbRecord {
  Contact(super.data);

  String? get firstname => str('firstname');
  String? get lastname => str('lastname');
  String? get title => str('title');
  String? get email => str('email');
  num? get mobile => num_('mobile');
  num? get phone => num_('phone');
  num? get extension => num_('extension');
  String? get companyId => rel('company');
  String? get referredId => rel('referred');
  String? get address => str('address');
  String? get unit => str('unit');
  String? get city => str('city');
  String? get province => str('province');
  String? get postal => str('postal');
  String? get notes => str('notes');
  String? get facebook => str('facebook');
  String? get source => str('source');
  String? get image => str('image');
  List<String> get propertyIds => relList('property');
  bool get archived => flag('archive');
  DateTime? get registered => date('registered');

  String get label {
    final name = [firstname, lastname].whereType<String>().join(' ').trim();
    return name.nullIfEmpty ?? email ?? id;
  }

  String? get addressLine {
    final parts = [
      [unit, address].whereType<String>().join(' ').trim().nullIfEmpty,
      city,
      province,
      postal,
    ].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(', ');
  }
}

/// A company. Collection: `companies`.
class Company extends PbRecord {
  Company(super.data);

  String? get name => str('company');
  num? get phone => num_('phone');
  String? get address => str('address');
  String? get billingEmail => str('billing_email');
  String? get industry => str('industry');
  bool get isCustomer => flag('customer');
  bool get isSupplier => flag('supplier');

  String get label => name ?? id;
}

/// A sales lead. Collection: `leads`.
class Lead extends PbRecord {
  Lead(super.data);

  String? get title => str('lead');
  String? get contactId => rel('contact');
  String? get propertyId => rel('property');
  String? get notes => str('notes');
  String? get status => str('status');
  DateTime? get followUp => date('followup');

  String get label => title ?? id;
}

/// A task. Collection: `tasks`.
class Task extends PbRecord {
  Task(super.data);

  String? get shortname => str('shortname');
  String? get notes => str('notes');
  DateTime? get due => date('due');
  DateTime? get start => date('start');
  DateTime? get finish => date('finish');
  String? get projectId => rel('project');
  String? get createdById => rel('created_by');
  List<String> get assignedToIds => relList('assigned_to');
  String? get parentId => rel('parent');
  bool get completed => flag('completed');
  String? get status => str('status');

  String get label => shortname ?? id;
}

/// An employee. Collection: `employees`.
class Employee extends PbRecord {
  Employee(super.data);

  String? get fullname => str('fullname');
  String? get firstname => str('firstname');
  String? get lastname => str('lastname');
  String? get email => str('email');
  DateTime? get birthday => date('birthday');
  DateTime? get hiredDate => date('hired_date');
  num? get rate => num_('rate');
  bool get canDrive => flag('drive');
  String? get licenseType => str('license_type');
  String? get licenseNo => str('license_no');
  DateTime? get licenseExpiry => date('license_expiry');
  DateTime? get healthSafety => date('health_safety');
  DateTime? get firstAid => date('first_aid');
  String? get contactProfileId => rel('contact_profile');
  String? get emergencyContactId => rel('emergency');
  bool get isActive => flag('isActive');
  bool get isSubcontractor => flag('isSubcontractor');
  String? get jobType => str('jobType');

  String get label {
    final name = fullname ??
        [firstname, lastname].whereType<String>().join(' ').trim().nullIfEmpty;
    return name ?? email ?? id;
  }
}

/// A time-clock entry. Collection: `timelogs`.
class Timelog extends PbRecord {
  Timelog(super.data);

  String? get employeeId => rel('employee');
  DateTime? get timestamp => date('timestamp');
  String? get change => str('change'); // Start Day | Site In | ...
  String? get noteIn => str('note_in');
  String? get noteOut => str('note_out');
  num? get lat => num_('lat');
  num? get long => num_('long');
  String? get siteId => rel('site');
  String? get vehicleId => rel('vehicle');
  String? get jobId => rel('job');
  String? get taskId => rel('task');
  bool get billable => flag('billable');

  String get label => change ?? 'Time entry';
}

/// A site / job location. Collection: `property`.
class Property extends PbRecord {
  Property(super.data);

  String? get name => str('name');
  List<String> get contactIds => relList('contact');
  String? get number => str('number');
  String? get street => str('street');
  String? get unit => str('unit');
  String? get city => str('city');
  String? get province => str('province');
  String? get postal => str('postal');
  String? get notes => str('notes');
  String? get type => str('type'); // Residence | Condo | Commercial | ...
  String? get photo => str('photo');
  String? get google => str('google');
  String? get addressString => str('address_string');

  String get label {
    final composed = [
      [number, street].whereType<String>().join(' ').trim().nullIfEmpty,
      city,
    ].whereType<String>().join(', ').nullIfEmpty;
    return name ?? addressString ?? composed ?? id;
  }
}

/// A job / project. Collection: `workorders`.
class WorkOrder extends PbRecord {
  WorkOrder(super.data);

  String? get name => str('name');
  String? get contactId => rel('contact');
  String? get propertyId => rel('property');
  String? get description => str('description');
  String? get scope => str('scope');
  String? get subtext => str('subtext');
  String? get leadId => rel('lead');
  DateTime? get startDate => date('start_date');
  DateTime? get endDate => date('end_date');

  String get label => name ?? id;
}

/// A vehicle or machine. Collection: `equipment`.
class Equipment extends PbRecord {
  Equipment(super.data);

  String? get name => str('name');
  String? get model => str('model');
  String? get shortcode => str('shortcode');
  String? get serialno => str('serialno');
  String? get brand => str('brand');
  String? get color => str('color');
  String? get locationId => rel('location');
  num? get odometer => num_('odometer');
  num? get purchaseValue => num_('purchase_value');
  DateTime? get purchaseDate => date('purchase_date');
  DateTime? get lastSeen => date('last_seen');
  DateTime? get annualSafety => date('annual_safety');
  DateTime? get registration => date('registration');
  bool get operable => flag('operable');
  bool get requiresSafety => flag('requires_safety');

  String get label {
    final parts = [name, brand, model].whereType<String>().toList();
    return parts.isEmpty ? id : parts.join(' · ');
  }
}

extension NullIfEmpty on String {
  String? get nullIfEmpty => trim().isEmpty ? null : this;
}
