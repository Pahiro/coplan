import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../models/base_rule.dart';
import '../models/custody_request.dart';
import '../models/manual_override.dart';
import '../models/resolved_event.dart';
import '../models/weekday_rule.dart';

/// Pure Dart class — no Flutter framework dependencies beyond [TimeOfDay].
///
/// Priority for any given event slot:
///   1. Manual override      (date-specific record in manual_overrides)
///   2. Weekday rule         (recurring day-of-week record in custody_weekday_rules)
///   3. Base rotation        (even/odd week from [AppConstants.rotationAnchor])
///
/// Accepted [CustodyRequest]s layer on top:
///   - Day transfers  override [dayOwner] for that date (higher priority than weekday rules).
///   - Windows        affect [parentAtTime] during their pickup→return window only.
class ResolutionEngine {
  final List<BaseRule>       baseRules;
  final List<ManualOverride> overrides;
  final List<CustodyRequest> custodyRequests;
  final List<WeekdayRule>    weekdayRules;

  const ResolutionEngine({
    required this.baseRules,
    required this.overrides,
    this.custodyRequests = const [],
    this.weekdayRules    = const [],
  });

  // ── Public API ──────────────────────────────────────────────────────────────

  /// The day owner from weekday rules or base rotation only, ignoring any
  /// accepted day-transfer custody request. Used for split-colour rendering
  /// when a transfer pickup falls mid-day.
  Parent baseOwner(DateTime date) =>
      _weekdayRuleParent(date.weekday) ?? weekOwner(date);

  /// Returns the parent who "owns" the week containing [date] by rotation.
  Parent weekOwner(DateTime date) {
    final monday       = _toMonday(date);
    final anchorMonday = _toMonday(AppConstants.rotationAnchor);
    final weeks        = monday.difference(anchorMonday).inDays ~/ 7;
    return weeks.isEven ? Parent.bennet : Parent.jana;
  }

  /// The primary responsible parent for an entire day.
  ///
  /// Priority: accepted day-transfer request > weekday rule > week rotation.
  Parent dayOwner(DateTime date) {
    final transfer = custodyRequests.firstWhereOrNull(
        (r) => r.isAccepted && r.isDayTransfer && _sameDay(r.date, date));
    if (transfer != null) return parentFromString(transfer.toParent);
    return _weekdayRuleParent(date.weekday) ?? weekOwner(date);
  }

  /// Accepted window requests (those with a return time) for [date].
  /// Used by [parentAtTime] and by the month-grid split painter.
  List<CustodyRequest> custodyWindows(DateTime date) => custodyRequests
      .where((r) => r.isAccepted && !r.isDayTransfer && _sameDay(r.date, date))
      .toList();

  /// True when [date] has at least one accepted window request AND every
  /// base-rule event scheduled for that weekday falls entirely within a window.
  ///
  /// Used by the calendar strip/grid: when this returns true, the cell can
  /// show a solid window-recipient colour instead of a diagonal split.
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
  Parent parentAtTime(DateTime date, TimeOfDay time) {
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
        return parentFromString(r.toParent);
      }
    }
    // Day transfers only take effect from their pickup time onwards — events
    // before the handover still belong to the original day owner.
    final transfer = custodyRequests.firstWhereOrNull(
        (r) => r.isAccepted && r.isDayTransfer && _sameDay(r.date, date));
    if (transfer != null) {
      final p = _parseTime(transfer.pickupTime);
      if (timeMin >= p.hour * 60 + p.minute) return parentFromString(transfer.toParent);
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
        .map((o) => ResolvedEvent(
              date:           date,
              time:           _parseTime(o.overrideTime ?? '09:00'),
              activity:       o.adhocActivity ?? '',
              location:       o.adhocLocation ?? '',
              childName:      o.childName,
              assignedParent: parentFromString(o.assignedParent),
              overrideReason: o.reason.isEmpty ? null : o.reason,
              isAdhoc:        true,
              isShared:       o.isShared,
              overrideId:     o.id,
            ))
        .toList();

    // Accepted custody requests — day transfers and windows both appear as events.
    final custodyEvents = custodyRequests
        .where((r) => r.isAccepted && _sameDay(r.date, date))
        .map((r) {
          final label = r.isDayTransfer
              ? '${r.toParent} has ${r.childName}'
              : '${r.toParent} has ${r.childName} · ${r.timeWindowLabel}';
          return ResolvedEvent(
            date:                  date,
            time:                  _parseTime(r.pickupTime),
            activity:              label,
            location:              '',
            childName:             r.childName,
            assignedParent:        parentFromString(r.toParent),
            overrideReason:        r.note,
            isAdhoc:               true,
            custodyRequestId:      r.id,
            custodyTransportNote:  _transportNote(r),
          );
        })
        .toList();

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
        (o.childName == rule.childName || o.childName == 'All'));

    final eventTime = _parseTime(override?.overrideTime ?? rule.eventTime);

    // ── 2. Schedule parent: override > weekday rule > rotation ───────────────
    Parent scheduleParent;
    String? scheduleReason;

    if (override != null) {
      scheduleParent = parentFromString(override.assignedParent);
      scheduleReason = override.reason.isEmpty ? null : override.reason;
    } else {
      final weekdayParent = _weekdayRuleParent(date.weekday);
      if (weekdayParent != null) {
        // Weekday rules change the parent but their reason is standing context,
        // not a per-event annotation — don't show it on every event tile.
        scheduleParent = weekdayParent;
        scheduleReason = null;
      } else {
        scheduleParent = weekOwner(date);
        scheduleReason = null;
      }
    }

    // ── 3. Accepted custody requests may override responsible parent ──────────
    final note        = _custodyNoteAt(date, eventTime);
    final actualParent =
        note != null ? parentAtTime(date, eventTime) : scheduleParent;

    return ResolvedEvent(
      date:           date,
      time:           eventTime,
      activity:       rule.activity,
      location:       rule.location,
      childName:      rule.childName,
      assignedParent: actualParent,
      overrideReason: scheduleReason,
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
    final transfer = custodyRequests.firstWhereOrNull(
        (r) => r.isAccepted && r.isDayTransfer && _sameDay(r.date, date));
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

  Parent? _weekdayRuleParent(int weekday) {
    final rule = weekdayRules.firstWhereOrNull(
        (r) => r.active && r.dayOfWeek == weekday);
    return rule?.parent;
  }

  DateTime _toMonday(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  TimeOfDay _parseTime(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }
}
