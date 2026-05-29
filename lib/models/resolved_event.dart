import 'package:flutter/material.dart';

/// Resolves a parent display name to a consistent key for colour lookups.
/// No longer throws on unknown — returns the input as-is (the household
/// config handles validation at a higher level).
String normalizeParentName(String s) => s.trim();

class ResolvedEvent {
  final DateTime date;
  final TimeOfDay time;
  final TimeOfDay? endTime;
  final String activity;
  final String location;
  final String childName;
  final String? note;

  /// Display name of the responsible parent (e.g. "Bennet", "Jana").
  /// Previously a `Parent` enum — now a plain string so it works with
  /// any household member.
  final String assignedParent;

  /// Non-null when a manual override caused this assignment.
  final String? overrideReason;

  /// True for one-off events added via manual_overrides (is_adhoc = true).
  /// These are not tied to any rules_base record.
  final bool isAdhoc;

  /// True when this event is a shared obligation that both parents should know
  /// about regardless of whose parenting day it is (e.g. birthday parties,
  /// recurring sports fixtures). The assignedParent still reflects who is
  /// responsible for taking the kids that day per the normal schedule.
  final bool isShared;

  /// PocketBase id of the rules_base record that sourced this event.
  /// Non-null for standing-rule events (including those modified by an override).
  final String? ruleId;

  /// PocketBase id of the manual_overrides record applied to this event.
  /// Non-null for adhoc one-off events and for standing-rule events that have
  /// a date-specific override.
  final String? overrideId;

  /// Non-null when an accepted custody request changes the responsible parent
  /// for this event (day transfer or timed window). Displayed inline on the
  /// TimelineCard so the user can see why the parent changed.
  final String? custodyNote;

  /// PocketBase id of the custody_requests record that generated this event.
  /// Non-null only for events synthesised from an accepted custody request
  /// (the "Bennet has ALL" banner rows). Used to wire up edit/delete in
  /// TimelineCard.
  final String? custodyRequestId;

  /// Human-readable transport direction for custody-request events, e.g.
  /// "Bennet collects · Jana picks up". Null for all other event types.
  final String? custodyTransportNote;

  /// PocketBase id of the custody_recurring arrangement that generated this
  /// (virtual) occurrence. Non-null only for live-expanded recurring banners;
  /// once an occurrence is frozen into a real request it carries
  /// [custodyRequestId] instead.
  final String? recurringId;

  const ResolvedEvent({
    required this.date,
    required this.time,
    this.endTime,
    required this.activity,
    required this.location,
    required this.childName,
    required this.assignedParent,
    this.overrideReason,
    this.note,
    this.isAdhoc = false,
    this.isShared = false,
    this.ruleId,
    this.overrideId,
    this.custodyNote,
    this.custodyRequestId,
    this.custodyTransportNote,
    this.recurringId,
  });

  /// Serialised form written to SharedPreferences for the Android widget.
  Map<String, dynamic> toJson() => {
        'date': '${date.year}-${_p(date.month)}-${_p(date.day)}',
        'time': '${_p(time.hour)}:${_p(time.minute)}',
        'activity': activity,
        'location': location,
        'childName': childName,
        'parent': assignedParent,
      };

  String _p(int n) => n.toString().padLeft(2, '0');
}
