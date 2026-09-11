import 'package:flutter/material.dart';

class ResolvedEvent {
  final DateTime date;
  final TimeOfDay time;
  final TimeOfDay? endTime;
  final String activity;
  final String location;
  final String childName;
  final String? note;

  /// Display name of the responsible parent (e.g. "Bennet", "Jana").
  final String assignedParent;

  /// Non-null when a manual override or absence caused this assignment.
  final String? overrideReason;

  /// True for one-off events added via manual_overrides (is_adhoc = true) and
  /// for the synthetic custody-request banners.
  final bool isAdhoc;

  /// True when both parents attend this event regardless of whose day it is
  /// (e.g. a rugby match). The assignedParent still reflects who is
  /// responsible for taking the kids that day per the normal schedule.
  final bool isShared;

  /// One-off event kind: '' for an ordinary event, 'exam' for a school exam.
  final String kind;

  /// PocketBase id of the rules_base record that sourced this event.
  final String? ruleId;

  /// PocketBase id of the manual_overrides record applied to this event.
  /// Non-null for one-off events and for standing events with a date-specific
  /// override.
  final String? overrideId;

  /// Non-null when an accepted custody request changes the responsible parent
  /// for this event (day transfer or timed window). Displayed inline on the
  /// TimelineCard so the user can see why the parent changed.
  final String? custodyNote;

  /// PocketBase id of the custody_requests record that generated this event.
  /// Non-null only for the "X in Y's care" banners.
  final String? custodyRequestId;

  /// Swap group of that custody request, when it is one leg of a day swap.
  final String? swapGroup;

  /// Human-readable transport direction for custody-request events, e.g.
  /// "Bennet collects · Jana picks up". Null for all other event types.
  final String? custodyTransportNote;

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
    this.kind = '',
    this.ruleId,
    this.overrideId,
    this.custodyNote,
    this.custodyRequestId,
    this.swapGroup,
    this.custodyTransportNote,
  });

  bool get isExam => kind == 'exam';
  bool get isCustody => custodyRequestId != null;

  /// Serialised form written to SharedPreferences for the Android widget.
  /// [parentColor] is the parent's ARGB colour so the widget matches the app.
  Map<String, dynamic> toJson({int? parentColor}) => {
        'date': '${date.year}-${_p(date.month)}-${_p(date.day)}',
        'time': '${_p(time.hour)}:${_p(time.minute)}',
        'activity': isExam ? 'Exam · $activity' : activity,
        'location': location,
        'childName': childName,
        'parent': assignedParent,
        if (parentColor != null) 'parentColorValue': parentColor,
      };

  String _p(int n) => n.toString().padLeft(2, '0');
}
