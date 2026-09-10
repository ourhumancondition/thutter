import 'package:flutter/material.dart';

import '../data/status/employee_status.dart';

IconData dutyIcon(DutyState s) => switch (s) {
      DutyState.onSite => Icons.location_on,
      DutyState.travelling => Icons.local_shipping,
      DutyState.atShop => Icons.warehouse_outlined,
      DutyState.onBreak => Icons.coffee_outlined,
      DutyState.onDuty => Icons.badge_outlined,
      DutyState.offDuty => Icons.nightlight_outlined,
    };

Color dutyColor(BuildContext context, DutyState s) => switch (s) {
      DutyState.onSite => Colors.green,
      DutyState.travelling => Colors.blue,
      DutyState.atShop => Colors.blueGrey,
      DutyState.onBreak => Colors.orange,
      DutyState.onDuty => Theme.of(context).colorScheme.primary,
      DutyState.offDuty => Theme.of(context).disabledColor,
    };
