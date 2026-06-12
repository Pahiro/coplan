import '../models/absence_period.dart';
import '../models/base_rule.dart';
import '../models/custody_request.dart';
import '../models/holiday_block.dart';
import '../models/household.dart';
import '../models/manual_override.dart';
import '../models/recurring_arrangement.dart';
import '../models/weekday_rule.dart';
import 'resolution_engine.dart';

/// Neutral fallback identities used only before the household has loaded.
/// Every surface must use these (not personal names) so behaviour is
/// consistent app-wide. See issue #21.
const kFallbackParentEven = 'Parent A';
const kFallbackParentOdd = 'Parent B';

/// Fallback rotation anchor used only before the household has loaded.
final DateTime kFallbackAnchor = DateTime(2025, 1, 6);

/// Builds a [ResolutionEngine] from a household config, applying the standard
/// fallbacks in one place. Previously this construction (and diverging
/// fallback names) was repeated at every call site.
ResolutionEngine buildEngine({
  required HouseholdConfig? household,
  List<BaseRule> baseRules = const [],
  List<ManualOverride> overrides = const [],
  List<CustodyRequest> custodyRequests = const [],
  List<WeekdayRule> weekdayRules = const [],
  List<RecurringArrangement> recurringArrangements = const [],
  List<AbsencePeriod> absencePeriods = const [],
  List<HolidayBlock> holidayBlocks = const [],
}) {
  return ResolutionEngine(
    baseRules:             baseRules,
    overrides:             overrides,
    custodyRequests:       custodyRequests,
    weekdayRules:          weekdayRules,
    recurringArrangements: recurringArrangements,
    absencePeriods:        absencePeriods,
    holidayBlocks:         holidayBlocks,
    rotationAnchor:        household?.rotationAnchorDate ?? kFallbackAnchor,
    rotationParentEven:    household?.rotationParentEvenName ?? kFallbackParentEven,
    rotationParentOdd:     household?.rotationParentOddName ?? kFallbackParentOdd,
    rotationScheme:        household?.rotationScheme,
    householdMode:         household?.mode ?? 'custody',
  );
}
