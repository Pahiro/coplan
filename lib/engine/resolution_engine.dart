import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../models/absence_period.dart';
import '../models/base_rule.dart';
import '../models/custody_request.dart';
import '../models/holiday_block.dart';
import '../models/manual_override.dart';
import '../models/resolved_event.dart';
import '../models/rotation_scheme.dart';

/// Pure Dart class — no Flutter framework dependencies beyond [TimeOfDay].
///
/// Who has the kids on a day:
///   1. Accepted day transfer   (from its pickup time onwards)
///   2. Absence                 (absent parent → the other rotation parent)
///   3. Holiday block
///   4. Base rotation           (pattern-based from [rotationScheme] and [rotationAnchor])
///
/// Per standing event, a date-specific manual override beats 2–4, and accepted
/// custody requests (day transfers and time windows) beat everything by time
/// of day. A day swap is simply two accepted day transfers.
///
/// Per-child custody: [parentAtTime], [dayTransferFor], and [_custodyNoteAt]
/// accept an optional [child] parameter. When supplied, only custody requests
/// that cover that child (or "All") are considered — so a transfer for Henri
/// does not affect Chris's events.
///
/// The Kotlin `CoplanSyncWorker` mirrors this logic for the home-screen
/// widgets — change one, update the other.
class ResolutionEngine {
  final List<BaseRule>       baseRules;
  final List<ManualOverride> overrides;
  final List<CustodyRequest> custodyRequests;
  final List<AbsencePeriod>  absencePeriods;
  final List<HolidayBlock>   holidayBlocks;

  final DateTime rotationAnchor;
  final String   rotationParentEven;
  final String   rotationParentOdd;

  /// The rotation pattern scheme (default: weekly 7/7).
  final RotationScheme rotationScheme;

  /// Household mode: "custody" (rotation) or "shared" (no rotation, both
  /// parents responsible by default).
  final String householdMode;

  /// Per-date cache for [effectiveCustodyFor].
  final Map<int, List<CustodyRequest>> _custodyCache = {};

  ResolutionEngine({
    required this.baseRules,
    required this.overrides,
    required this.rotationAnchor,
    required this.rotationParentEven,
    required this.rotationParentOdd,
    RotationScheme? rotationScheme,
    this.householdMode   = 'custody',
    this.custodyRequests = const [],
    this.absencePeriods  = const [],
    this.holidayBlocks   = const [],
  }) : rotationScheme = rotationScheme ?? RotationScheme.weekly();

  /// True when this engine operates in shared-household mode (no rotation).
  bool get isSharedMode => householdMode == 'shared';

  // ── Public API ──────────────────────────────────────────────────────────────

  /// The holiday block covering [date], if any.
  HolidayBlock? holidayBlockFor(DateTime date) =>
      holidayBlocks.firstWhereOrNull((b) => b.coversDate(date));

  /// The parent assigned by a holiday block on [date], or null if no block
  /// covers that date.
  String? holidayOwner(DateTime date) => holidayBlockFor(date)?.assignedParent;

  /// The scheduled owner from holiday blocks or the rotation only, ignoring
  /// absences and custody requests. Used for split-colour rendering and as the
  /// parent a transfer hands the kids over from.
  String baseOwner(DateTime date) {
    if (isSharedMode) return 'Both';
    return _scheduledOwner(date);
  }

  /// Returns the rotation parent for [date] based on the configured scheme.
  ///
  /// Uses UTC epoch math so that DST transitions never shift [Duration.inDays]
  /// and flip the parity. In shared mode, returns "Both".
  String weekOwner(DateTime date) {
    if (isSharedMode) return 'Both';
    final dateUtc   = DateTime.utc(date.year, date.month, date.day);
    final anchorUtc = DateTime.utc(rotationAnchor.year, rotationAnchor.month, rotationAnchor.day);
    final daysSince = (dateUtc.millisecondsSinceEpoch - anchorUtc.millisecondsSinceEpoch) ~/ 86400000;
    return rotationScheme.ownerAtDay(daysSince, rotationParentEven, rotationParentOdd);
  }

  /// The primary responsible parent for an entire day.
  String dayOwner(DateTime date) {
    final transfer = dayTransferFor(date);
    if (transfer != null) return transfer.toParent;
    if (isSharedMode) return 'Both';
    return _applyAbsence(_scheduledOwner(date), date);
  }

  /// The primary responsible parent for [child] on [date]. Falls back to
  /// [dayOwner] when the child has no specific custody request.
  String dayOwnerForChild(DateTime date, String child) {
    if (child == 'All') return dayOwner(date);
    final transfer = dayTransferFor(date, child: child);
    if (transfer != null) return transfer.toParent;
    if (isSharedMode) return 'Both';
    return _applyAbsence(_scheduledOwner(date), date);
  }

  /// Returns the absence covering [date], or null if none.
  AbsencePeriod? absenceFor(DateTime date) =>
      absencePeriods.firstWhereOrNull((a) => a.coversDate(date));

  /// All accepted custody requests for [date] (cached per date).
  List<CustodyRequest> effectiveCustodyFor(DateTime date) {
    final key = date.year * 10000 + date.month * 100 + date.day;
    return _custodyCache[key] ??= custodyRequests
        .where((r) => r.isAccepted && _sameDay(r.date, date))
        .toList();
  }

  /// The accepted day-transfer for [date], if any. When [child] is provided
  /// (and not "All"), only transfers covering that specific child count.
  CustodyRequest? dayTransferFor(DateTime date, {String? child}) =>
      effectiveCustodyFor(date).firstWhereOrNull(
          (r) => r.isDayTransfer && _requestMatchesChild(r, child));

  /// Accepted window requests (those with a return time) for [date].
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
      final tMin = _minutes(_parseTime(rule.eventTime));
      return windows.any((r) {
        final (pMin, retMin) = _windowBounds(r);
        return tMin >= pMin && tMin < retMin;
      });
    });
  }

  /// Returns the parent who actually has the kids at [time] on [date].
  /// When [child] is provided (and not "All"), only custody requests covering
  /// that child are considered — enabling per-child custody resolution.
  String parentAtTime(DateTime date, TimeOfDay time, {String? child}) {
    final timeMin = _minutes(time);
    for (final r in custodyWindows(date)) {
      if (!_requestMatchesChild(r, child)) continue;
      final (pMin, retMin) = _windowBounds(r);
      if (timeMin >= pMin && timeMin < retMin) return r.toParent;
    }
    // Day transfers only take effect from their pickup time onwards — events
    // before the handover still belong to the original day owner.
    final transfer = dayTransferFor(date, child: child);
    if (transfer != null) {
      if (timeMin >= _minutes(_parseTime(transfer.pickupTime))) {
        return transfer.toParent;
      }
    }
    // No custody request covers this slot (for this child): the scheduled
    // owner. Not dayOwner() — that would apply a sibling's transfer.
    if (isSharedMode) return 'Both';
    return _applyAbsence(_scheduledOwner(date), date);
  }

  /// Resolves all scheduled events for [date], sorted chronologically.
  List<ResolvedEvent> resolveDay(DateTime date) {
    final rules = baseRules.where((r) {
      if (r.dayOfWeek != date.weekday) return false;
      // Standing events stop repeating after their (inclusive) end date.
      if (r.endDate != null && _dateOnly(date).isAfter(_dateOnly(r.endDate!))) {
        return false;
      }
      // Directional handover rules only render when the named parent is the
      // outgoing custody holder (holiday block or rotation owner).
      if (r.handoverFrom != null && r.handoverFrom != baseOwner(date)) {
        return false;
      }
      return true;
    }).toList();
    final events = rules.map((r) => _resolveRule(r, date)).toList();

    // One-off events (including exams). The responsible parent is resolved
    // live, so later swaps, absences and holidays are always reflected.
    final adhoc = overrides
        .where((o) => _sameDay(o.targetDate, date) && o.isAdhoc)
        .map((o) {
          final t = _parseTime(o.overrideTime ?? '09:00');
          final adhocChild = o.childName == 'All' ? null : o.childName;
          return ResolvedEvent(
            date:           date,
            time:           t,
            endTime:        o.endTime != null && o.endTime!.isNotEmpty
                                ? _parseTime(o.endTime!) : null,
            activity:       o.adhocActivity ?? '',
            location:       o.adhocLocation ?? '',
            childName:      o.childName,
            assignedParent: parentAtTime(date, t, child: adhocChild),
            note:           o.note,
            isAdhoc:        true,
            isShared:       o.isShared,
            kind:           o.kind,
            overrideId:     o.id,
            custodyNote:    _custodyNoteAt(date, t, child: adhocChild),
          );
        })
        .toList();

    // Accepted custody requests appear as banner events.
    final custodyEvents = effectiveCustodyFor(date).map((r) {
      final who = _custodyChildLabel(r.childName);
      final String label;
      if (r.isSwapLeg) {
        label = '$who in ${r.toParent}\'s care · swap';
      } else if (r.isDayTransfer) {
        label = '$who in ${r.toParent}\'s care';
      } else {
        label = '$who in ${r.toParent}\'s care · ${r.timeWindowLabel}';
      }
      return ResolvedEvent(
        date:                  date,
        time:                  _parseTime(r.pickupTime),
        activity:              label,
        location:              '',
        childName:             r.childName,
        assignedParent:        r.toParent,
        overrideReason:        r.note,
        isAdhoc:               true,
        custodyRequestId:      r.id,
        swapGroup:             r.swapGroup,
        custodyTransportNote:  r.isSwapLeg ? null : _transportNote(r),
      );
    }).toList();

    final all = [...events, ...adhoc, ...custodyEvents];
    all.sort((a, b) {
      final byTime = _minutes(a.time).compareTo(_minutes(b.time));
      if (byTime != 0) return byTime;
      // Custody banners sort before the events they cover at the same minute.
      if (a.isCustody == b.isCustody) return 0;
      return a.isCustody ? -1 : 1;
    });
    return all;
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  String _scheduledOwner(DateTime date) =>
      holidayOwner(date) ?? weekOwner(date);

  /// If [scheduledParent] is absent on [date], returns the other rotation
  /// parent; otherwise returns [scheduledParent] unchanged.
  String _applyAbsence(String scheduledParent, DateTime date) {
    final absence = absenceFor(date);
    if (absence == null || absence.absentParent != scheduledParent) {
      return scheduledParent;
    }
    if (scheduledParent == rotationParentEven) return rotationParentOdd;
    if (scheduledParent == rotationParentOdd)  return rotationParentEven;
    return scheduledParent; // unknown parent name — leave unchanged
  }

  ResolvedEvent _resolveRule(BaseRule rule, DateTime date) {
    // ── 1. Date-specific manual override ─────────────────────────────────────
    final override = overrides.firstWhereOrNull((o) =>
        !o.isAdhoc &&
        _sameDay(o.targetDate, date) &&
        (o.childName == rule.childName || o.childName == 'All' || rule.childName == 'All'));

    final eventTime = _parseTime(override?.overrideTime ?? rule.eventTime);

    // ── 2. Schedule parent: override > absence > holiday > rotation ──────────
    String scheduleParent;
    String? scheduleReason;

    if (override != null) {
      // Manual overrides are explicit decisions — they win over absence.
      scheduleParent = override.assignedParent;
      scheduleReason = override.reason.isEmpty ? null : override.reason;
    } else {
      final scheduled = _scheduledOwner(date);
      final absence = absenceFor(date);
      if (absence != null && absence.absentParent == scheduled) {
        scheduleParent = _applyAbsence(scheduled, date);
        scheduleReason = absence.reason.isNotEmpty ? absence.reason : 'Absence';
      } else {
        scheduleParent = scheduled;
        scheduleReason = null;
      }
    }

    // ── 3. Accepted custody requests may override responsible parent ──────────
    final child       = rule.childName == 'All' ? null : rule.childName;
    final note        = _custodyNoteAt(date, eventTime, child: child);
    final actualParent =
        note != null ? parentAtTime(date, eventTime, child: child) : scheduleParent;
    // When a custody request changes the parent, drop the override reason —
    // showing it next to the custody parent is confusing mixed provenance.
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

  /// A short note when an accepted custody request changes who is responsible
  /// at [time] on [date], or null when no request affects this slot.
  String? _custodyNoteAt(DateTime date, TimeOfDay time, {String? child}) {
    final timeMin = _minutes(time);

    // Window requests first (they apply only during pickup→return).
    for (final r in custodyWindows(date)) {
      if (!_requestMatchesChild(r, child)) continue;
      final (pMin, retMin) = _windowBounds(r);
      if (timeMin >= pMin && timeMin < retMin) {
        final till = r.returnTimeTbd ? 'TBD' : (r.returnTime ?? '…');
        return '${r.toParent} · ${r.pickupTime}–$till';
      }
    }

    // Day transfer only takes effect from its pickup time onwards.
    final transfer = dayTransferFor(date, child: child);
    if (transfer != null &&
        timeMin >= _minutes(_parseTime(transfer.pickupTime))) {
      return '${transfer.toParent} · ${transfer.isSwapLeg ? 'day swap' : 'day transfer'}';
    }

    return null;
  }

  /// True when [r] covers [child]. Matches when child is null/"All", when the
  /// request covers "All" children, or when the request's comma-separated
  /// child list contains [child].
  bool _requestMatchesChild(CustodyRequest r, String? child) {
    if (child == null || child == 'All' || r.childName == 'All') return true;
    return r.childName
        .split(',')
        .map((s) => s.trim())
        .contains(child);
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

  /// (pickup, return) in minutes; an open-ended window runs to midnight.
  (int, int) _windowBounds(CustodyRequest r) {
    final pMin = _minutes(_parseTime(r.pickupTime));
    var retMin = 24 * 60;
    if (!r.returnTimeTbd && r.returnTime != null) {
      retMin = _minutes(_parseTime(r.returnTime!));
    }
    return (pMin, retMin);
  }

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  TimeOfDay _parseTime(String hhmm) {
    final p = hhmm.split(':');
    if (p.length < 2) return const TimeOfDay(hour: 0, minute: 0);
    return TimeOfDay(
        hour: int.tryParse(p[0]) ?? 0, minute: int.tryParse(p[1]) ?? 0);
  }

  /// "All" → "All", "Henri" → "Henri", "Henri,Chris" → "Henri & Chris".
  static String _custodyChildLabel(String childName) {
    if (childName == 'All') return 'All';
    final parts = childName.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (parts.length <= 1) return childName;
    return '${parts.sublist(0, parts.length - 1).join(', ')} & ${parts.last}';
  }
}
