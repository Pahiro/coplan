import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'absence_provider.dart';
import 'custody_provider.dart';
import 'expense_provider.dart';
import 'holiday_provider.dart';
import 'household_provider.dart';
import 'needs_provider.dart';
import 'schedule_provider.dart';

/// Re-fetches every source collection the app is built from. Derived views
/// (dashboard, calendar weeks, day owners, balances) recompute by themselves
/// because they watch these providers.
///
/// Pass `ref.invalidate` from a `Ref` or `WidgetRef`.
void refreshAppData(void Function(ProviderOrFamily provider) invalidate) {
  invalidate(householdProvider);
  invalidate(baseRulesProvider);
  invalidate(manualOverridesProvider);
  invalidate(acceptedCustodyProvider);
  invalidate(custodyRequestsProvider);
  invalidate(absencePeriodsProvider);
  invalidate(holidayBlocksProvider);
  invalidate(expensesProvider);
  invalidate(expenseSummaryProvider);
  invalidate(needsProvider);
}
