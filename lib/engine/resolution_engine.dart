import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../models/absence_period.dart';
import '../models/base_rule.dart';
import '../models/custody_request.dart';
import '../models/manual_override.dart';
import '../models/recurring_arrangement.dart';
import '../models/resolved_event.dart';
import '../models/rotation_scheme.dart';
import '../models/weekday_rule.dart';

/// Pure Dart class — no Flutter framework dependencies beyond [TimeOfDay].
///
/// Priority for any given event slot:
///   1. Manual override      (date-specific record in manual_overrides)
///   2. Absence block        (absent parent → custody flips to the other parent)
///   3. Weekday rule         (recurring day-of-week record in custody_weekday_rules)
///   4. Base rotation        (pattern-based from [rotationScheme] and [rotationAnchor])
///
/// Accepted [CustodyRequest]s layer on top:
///   - Day transfers  override [dayOwner] for that date (higher priority than weekday rules).
///   - Windows        affect [parentAtTime] during their pickup→return window only.
///
/// Parent identity is now string-based (display names from the household).
/// [rotationParentEven] and [rotationParentOdd] replace the former hardcoded
/// `Parent.bennet` / `Parent.jana` enum values.
class ResolutionEngine {
  final List<BaseRule>             baseRules;
  final List<ManualOverride>       overrides;
  final List<CustodyRequest>       custodyRequests;
  final List<WeekdayRule>          weekdayRules;
  final List<RecurringArrangement> recurringArrangements;
  final List<AbsencePeriod>        absencePeriods;

  /// Rotation config — previously from AppConstants, now passed in.
  final DateTime rotationAnchor;
  final String   rotationParentEven;
  final String   rotationParentOdd;

  /// The rotation pattern scheme (default: weekly 7/7).
  final RotationScheme rotationScheme;

  /// Household mode: "custody" (rotation) or "shared" (no rotation, both
  /// parents responsible by default).
  final String householdMode;

  /// Per-date cache for [effectiveCustodyFor] to avoid recomputing the merged
  /// real + virtual custody list multiple times per [resolveDay] pass.
  final Map<int, List<CustodyRequest>> _custodyCache = {};

  ResolutionEngine({
    required this.baseRules,
    required this.overrides,
    required this.rotationAnchor,
    required this.rotationParentEven,
    required this.rotationParentOdd,
    RotationScheme? rotationScheme,
    this.householdMode         = 'custody',
    this.custodyRequests       = const [],
    this.weekdayRules          = const [],
    this.recurringArrangements = const [],
    this.absencePeriods        = const [],
  }) : rotationScheme = rotationScheme ?? RotationScheme.weekly();

  /// True when this engine operates in shared-household mode (no rotation).
  bool get isSharedMode => householdMode == 'shared';

  // ── Public API ──────────────────────────────────────────────────────────────

  /// The day owner from weekday rules or base rotation only, ignoring any
  /// accepted day-transfer custody request. Used for split-colour rendering
  /// when a transfer pickup falls mid-day.
  String baseOwner(DateTime date) {
    if (isSharedMode) return 'Both';
    return _weekdayRuleParent(date.weekday) ?? weekOwner(date);
  }

  /// Returns the rotation parent for [date] based on the configured scheme.
  ///
  /// Uses UTC epoch math so that DST transitions never shift [Duration.inDays]
  /// and flip the parity (see ISSUES.md #1).
  /// In shared mode, returns "Both" (no rotation applies).
  String weekOwner(DateTime date) {
    if (isSharedMode) return 'Both';
    final dateUtc   = DateTime.utc(date.year, date.month, date.day);
    final anchorUtc = DateTime.utc(rotationAnchor.year, rotationAnchor.month, rotationAnchor.day);
    final daysSince = (dateUtc.millisecondsSinceEpoch - anchorUtc.millisecondsSinceEpoch) ~/ 86400000;
    return rotationScheme.ownerAtDay(daysSince, rotationParentEven, rotationParentOdd);
  }

  /// The primary responsible parent for an entire day.
  ///
  /// Priority: accepted day-transfer request > weekday rule > week rotation >
  ///           absence flip. Manual overrides are applied per-event in
  ///           [_resolveRule] but day-level absence is checked here so the
  ///           calendar grid colours correctly.
  String dayOwner(DateTime date) {
    final transfer = dayTransferFor(date);
    if (transfer != null) return transfer.toParent;
    if (isSharedMode) return 'Both';
    final scheduled = _weekdayRuleParent(date.weekday) ?? weekOwner(date);
    return _applyAbsence(scheduled, date);
  }

  /// Returns the absence covering [date] where the absent parent matches
  /// [scheduledParent], or null if none.
  AbsencePeriod? absenceFor(DateTime date) =>
      absencePeriods.firstWhereOrNull((a) => a.coversDate(date));

  /// If [scheduledParent] is absent on [date], returns the other parent's name;
  /// otherwise returns [scheduledParent] unchanged.
  String _applyAbsence(String scheduledParent, DateTime date) {
    final absence = absenceFor(date);
    if (absence == null || absence.absentParent != scheduledParent) {
      return scheduledParent;
    }
    // Flip to whichever rotation parent is not absent.
    if (scheduledParent == rotationParentEven) return rotationParentOdd;
    if (scheduledParent == rotationParentOdd)  return rotationParentEven;
    return scheduledParent; // unknown parent name — leave unchanged
  }

  /// All accepted custody for [date]: real records plus virtual occurrences
  /// expanded from recurring arrangements.  This is the single source the rest
  /// of the engine reasons over, so every surface sees recurring transfers.
  ///
  /// Results are cached per date within this engine instance to avoid redundant
  /// recomputation across [parentAtTime], [_custodyNoteAt], etc. (ISSUES #7).
  List<CustodyRequest> effectiveCustodyFor(DateTime date) {
    final key = date.year * 10000 + date.month * 100 + date.day;
    final cached = _custodyCache[key];
    if (cached != null) return cached;

    final real = custodyRequests
        .where((r) => r.isAccepted && _sameDay(r.date, date))
        .toList();
    final result = recurringArrangements.isEmpty
        ? real
        : [...real, ..._virtualRecurringFor(date, real)];
    _custodyCache[key] = result;
    return result;
  }

  /// The effective day-transfer (real or virtual recurring) for [date], if any.
  CustodyRequest? dayTransferFor(DateTime date) =>
      effectiveCustodyFor(date).firstWhereOrNull((r) => r.isDayTransfer);

  /// Expands recurring arrangements into virtual requests for [date].
  /// Only fires for today/future dates (past is served by frozen real rows),
  /// on/after the arrangement start, on weeks the OTHER parent owns the day,
  /// and only when no real request already covers that date + child.
  List<CustodyRequest> _virtualRecurringFor(
      DateTime date, List<CustodyRequest> realForDate) {
    final now       = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final d         = DateTime(date.year, date.month, date.day);
    if (d.isBefore(todayDate)) return const [];

    final out = <CustodyRequest>[];
    final dayBaseOwner = baseOwner(date);
    for (final a in recurringArrangements) {
      if (!a.active) continue;
      if (a.dayOfWeek != date.weekday) continue;
      final start = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
      if (d.isBefore(start)) continue;
      // Conditional: skip weeks where the recipient already owns the day.
      if (dayBaseOwner == a.toParent) continue;
      // Suppress when a one-off request already covers this date + child.
      final covered = realForDate.any((r) =>
          r.childName == a.childName ||
          r.childName == 'All' ||
          a.childName == 'All');
      if (covered) continue;
      out.add(a.toVirtualRequest(date, fromParent: dayBaseOwner));
    }
    return out;
  }

  /// Accepted window requests (those with a return time) for [date].
  /// Used by [parentAtTime] and by the month-grid split painter.
  List<CustodyRequest> custodyWindows(DateTime date) =>
      effectiveCustodyFor(date).where((r) => !r.isDayTransfer).toList();

  /// True when [date] has at least one accepted window request AND every
  /// base-rule event scheduled for that weekday falls entirely within a window.
  ///
  /// Used by the calendar strip/grid.  When this returns true AND the window
  /// has no definite return time, the cell shows a solid window-recipient
  /// colour.  When the window has a known return time the base owner gets the
  /// kids back, so the cell shows a diagonal split regardless.
  bool windowCoversAllEvents(DateTime date) {
    final windows = custodyWindows(date);
    if (windows.isEmpty) return false;
    final dayRules =
        baseRules.where((r) => r.dayOfWeek == date.weekday).toList();
    // No events scheduled → there's nothing to "cover"; keep the split so
    // the window is still visible on the strip.
    if (dayRules.isEmpty) return false;
    return dayRules.every((rule) {
      final t    = _parseTime(rule.eventTime);
      final tMin = t.hour * 60 + t.minute;
      return windows.any((r) {
        final p    = _parseTime(r.pickupTime);
        final pMin = p.hour * 60 + p.minute;
        int retMin = 24 * 60;
        if (!r.returnTimeTbd && r.returnTime != null) {
          final ret = _parseTime(r.returnTime!);
          retMin = ret.hour * 60 + ret.minute;
        }
        return tMin >= pMin && tMin < retMin;
      });
    });
  }

  /// Returns the parent who actually has the kids at [time] on [date].
  String parentAtTime(DateTime date, TimeOfDay time) {
    final timeMin = time.hour * 60 + time.minute;
    for (final r in custodyWindows(date)) {
      final pickup    = _parseTime(r.pickupTime);
      final pickupMin = pickup.hour * 60 + pickup.minute;
      int returnMin   = 24 * 60;
      if (!r.returnTimeTbd && r.returnTime != null) {
        final ret = _parseTime(r.returnTime!);
        returnMin = ret.hour * 60 + ret.minute;
      }
      if (timeMin >= pickupMin && timeMin < returnMin) {
        return r.toParent;
      }
    }
    // Day transfers only take effect from their pickup time onwards — events
    // before the handover still belong to the original day owner.
    final transfer = dayTransferFor(date);
    if (transfer != null) {
      final p = _parseTime(transfer.pickupTime);
      if (timeMin >= p.hour * 60 + p.minute) return transfer.toParent;
      return _weekdayRuleParent(date.weekday) ?? weekOwner(date);
    }
    return dayOwner(date);
  }

  /// Resolves all scheduled events for [date], sorted chronologically.
  List<ResolvedEvent> resolveDay(DateTime date) {
    final rules  = baseRules.where((r) => r.dayOfWeek == date.weekday).toList();
    final events = rules.map((r) => _resolveRule(r, date)).toList();

    // Ad-hoc one-off events
    final adhoc = overrides
        .where((o) => _sameDay(o.targetDate, date) && o.isAdhoc)
        .map((o) {
          final t = _parseTime(o.overrideTime ?? '09:00');
          final custodyNote = _custodyNoteAt(date, t);
          final actualParent =
              custodyNote != null ? parentAtTime(date, t) : o.assignedParent;
          return ResolvedEvent(
            date:           date,
            time:           t,
            endTime:        o.endTime != null && o.endTime!.isNotEmpty
                                ? _parseTime(o.endTime!) : null,
            activity:       o.adhocActivity ?? '',
            location:       o.adhocLocation ?? '',
            childName:      o.childName,
            assignedParent: actualParent,
            note:           o.note,
            isAdhoc:        true,
            isShared:       o.isShared,
            overrideId:     o.id,
            custodyNote:    custodyNote,
          );
        })
        .toList();

    // Accepted custody — real records plus virtual recurring occurrences —
    // appear as banner events (day transfers and windows alike).
    final custodyEvents = effectiveCustodyFor(date).map((r) {
      final label = r.isDayTransfer
          ? '${r.toParent} has ${r.childName}'
          : '${r.toParent} has ${r.childName} · ${r.timeWindowLabel}';
      final recurringId = RecurringArrangement.recurringIdFrom(r.id);
      return ResolvedEvent(
        date:                  date,
        time:                  _parseTime(r.pickupTime),
        activity:              label,
        location:              '',
        childName:             r.childName,
        assignedParent:        r.toParent,
        overrideReason:        r.note,
        isAdhoc:               true,
        custodyRequestId:      recurringId == null ? r.id : null,
        recurringId:           recurringId,
        custodyTransportNote:  _transportNote(r),
      );
    }).toList();

    final all = [...events, ...adhoc, ...custodyEvents];
    all.sort((a, b) {
      final aMin = a.time.hour * 60 + a.time.minute;
      final bMin = b.time.hour * 60 + b.time.minute;
      if (aMin != bMin) return aMin.compareTo(bMin);
      // Tie-break: custody-request events (isAdhoc, no rule/override id)
      // sort before regular and adhoc-override events so the "who has the
      // kids" banner always appears above the events it covers.
      final aCust = a.isAdhoc && a.ruleId == null && a.overrideId == null;
      final bCust = b.isAdhoc && b.ruleId == null && b.overrideId == null;
      if (aCust == bCust) return 0;
      return aCust ? -1 : 1;
    });
    return all;
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  ResolvedEvent _resolveRule(BaseRule rule, DateTime date) {
    // ── 1. Date-specific manual override ─────────────────────────────────────
    final override = overrides.firstWhereOrNull((o) =>
        !o.isAdhoc &&
        _sameDay(o.targetDate, date) &&
        (o.childName == rule.childName || o.childName == 'All' || rule.childName == 'All'));

    final eventTime = _parseTime(override?.overrideTime ?? rule.eventTime);

    // ── 2. Schedule parent: override > absence > weekday rule > rotation ──────
    String scheduleParent;
    String? scheduleReason;

    if (override != null) {
      // Manual overrides are explicit decisions — they win over absence.
      scheduleParent = override.assignedParent;
      scheduleReason = override.reason.isEmpty ? null : override.reason;
    } else {
      final weekdayParent = _weekdayRuleParent(date.weekday);
      final rotationParent = weekdayParent ?? weekOwner(date);
      final absence = absenceFor(date);
      if (absence != null && absence.absentParent == rotationParent) {
        scheduleParent = _applyAbsence(rotationParent, date);
        scheduleReason = absence.reason.isNotEmpty ? absence.reason : 'Absence';
      } else {
        scheduleParent = rotationParent;
        scheduleReason = null;
      }
    }

    // ── 3. Accepted custody requests may override responsible parent ──────────
    final note        = _custodyNoteAt(date, eventTime);
    final actualParent =
        note != null ? parentAtTime(date, eventTime) : scheduleParent;
    // When a custody request changes the parent, drop the manual-override
    // reason — showing the override's reason with the custody parent is
    // confusing mixed provenance (see ISSUES.md #3).
    final actualReason = note != null ? null : scheduleReason;

    return ResolvedEvent(
      date:           date,
      time:           eventTime,
      activity:       rule.activity,
      location:       rule.location,
      childName:      rule.childName,
      assignedParent: actualParent,
      overrideReason: actualReason,
      isShared:       rule.isShared,
      ruleId:         rule.id,
      overrideId:     override?.id,
      custodyNote:    note,
    );
  }

  /// Returns a short human-readable note when an accepted custody request
  /// changes who is responsible for an event at [time] on [date].
  /// Returns null when no custody request affects this slot.
  String? _custodyNoteAt(DateTime date, TimeOfDay time) {
    final timeMin = time.hour * 60 + time.minute;

    // Window requests first (they apply only during pickup→return).
    for (final r in custodyWindows(date)) {
      final pickup    = _parseTime(r.pickupTime);
      final pickupMin = pickup.hour * 60 + pickup.minute;
      int returnMin   = 24 * 60;
      if (!r.returnTimeTbd && r.returnTime != null) {
        final ret = _parseTime(r.returnTime!);
        returnMin = ret.hour * 60 + ret.minute;
      }
      if (timeMin >= pickupMin && timeMin < returnMin) {
        final till = r.returnTimeTbd
            ? 'TBD'
            : (r.returnTime ?? '…');
        return '${r.toParent} · ${r.pickupTime}–$till';
      }
    }

    // Day transfer only takes effect from its pickup time onwards.
    final transfer = dayTransferFor(date);
    if (transfer != null) {
      final p = _parseTime(transfer.pickupTime);
      if (timeMin >= p.hour * 60 + p.minute) {
        return '${transfer.toParent} · day transfer';
      }
    }

    return null;
  }

  /// One-line transport summary for a custody-request event tile, e.g.
  /// "Bennet collects · Jana picks up".
  String _transportNote(CustodyRequest r) {
    final pickup = r.toParentCollects
        ? '${r.toParent} collects'
        : '${r.fromParent} drops off';
    if (r.isDayTransfer) return pickup;
    final ret = r.toParentReturns
        ? '${r.toParent} drops back'
        : '${r.fromParent} picks up';
    return '$pickup · $ret';
  }

  String? _weekdayRuleParent(int weekday) {
    final rule = weekdayRules.firstWhereOrNull(
        (r) => r.active && r.dayOfWeek == weekday);
    return rule?.assignedParent;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  TimeOfDay _parseTime(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }
}
