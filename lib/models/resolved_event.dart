import 'package:flutter/material.dart';

import '../core/constants.dart';

enum Parent { bennet, jana }

extension ParentX on Parent {
  String get displayName =>
      this == Parent.bennet ? AppConstants.parentBennet : AppConstants.parentJana;

  /// High-contrast accent colour for card borders and badges.
  Color get color =>
      this == Parent.bennet ? const Color(0xFF1565C0) : const Color(0xFFD81B60);

  /// Soft background tint for time chips.
  Color get lightColor =>
      this == Parent.bennet ? const Color(0xFFBBDEFB) : const Color(0xFFFCE4EC);
}

Parent parentFromString(String s) =>
    s == AppConstants.parentBennet ? Parent.bennet : Parent.jana;

class ResolvedEvent {
  final DateTime date;
  final TimeOfDay time;
  final String activity;
  final String location;
  final String childName;
  final Parent assignedParent;

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

  const ResolvedEvent({
    required this.date,
    required this.time,
    required this.activity,
    required this.location,
    required this.childName,
    required this.assignedParent,
    this.overrideReason,
    this.isAdhoc = false,
    this.isShared = false,
    this.ruleId,
    this.overrideId,
    this.custodyNote,
    this.custodyRequestId,
    this.custodyTransportNote,
  });

  /// Serialised form written to SharedPreferences for the Android widget.
  Map<String, dynamic> toJson() => {
        'date': '${date.year}-${_p(date.month)}-${_p(date.day)}',
        'time': '${_p(time.hour)}:${_p(time.minute)}',
        'activity': activity,
        'location': location,
        'childName': childName,
        'parent': assignedParent.displayName,
        'parentColorValue': assignedParent.color.value,
      };

  String _p(int n) => n.toString().padLeft(2, '0');
}
